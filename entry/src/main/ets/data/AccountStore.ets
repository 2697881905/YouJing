/**
 * 登录态单点：UnionID 静默登录 + 本机游客兜底（开发文档 §6 阶段 8）。
 *
 * 契约：
 * - login() 永不抛错。取不到 UnionID 就退回本机游客分区，保证首启流程无阻断；
 *   失败原因只进日志（屏1 法务行已承诺「仅使用 UnionID 静默授权，行程数据保留于本地」）。
 * - uid() 同步可读，供 DAO 打分区键；因此 init() 必须在任何读写行程前完成
 *   （EntryAbility 在 loadContent 回调里先 await init 再灌种子数据）。
 * - 只持久化 UnionID，不写入任何敏感字段。
 */

import { preferences } from '@kit.ArkData';
import { authentication } from '@kit.AccountKit';
import { common } from '@kit.AbilityKit';
import { AccountConfig } from '../common/config/AccountConfig';
import { AccountKind, AccountState } from '../model/Account';
import { Logger } from '../common/logger/Logger';
import { AppError } from '../common/error/AppError';
import { ErrorCode } from '../common/error/ErrorCode';

const TAG: string = 'Data.AccountStore';

function guestState(): AccountState {
  const state: AccountState = {
    uid: AccountConfig.GUEST_UID,
    kind: AccountKind.GUEST,
    loginAt: 0
  };
  return state;
}

export class AccountStore {
  private static current: AccountState = guestState();
  private static prefs: preferences.Preferences | null = null;

  /** 当前登录态快照（未 init 时为游客态，绝不会是空 uid） */
  static state(): AccountState {
    return AccountStore.current;
  }

  /** RDB 分区键 */
  static uid(): string {
    return AccountStore.current.uid;
  }

  static isGuest(): boolean {
    return AccountStore.current.kind === AccountKind.GUEST;
  }

  /** 打开偏好分片并恢复上次登录态；须在首次读写行程之前调用 */
  static async init(context: common.Context): Promise<AccountState> {
    try {
      const prefs: preferences.Preferences =
        await preferences.getPreferences(context, AccountConfig.PREFERENCES_NAME);
      AccountStore.prefs = prefs;
      const rawUid: preferences.ValueType = prefs.getSync(AccountConfig.KEY_UNION_ID, '');
      const uid: string = typeof rawUid === 'string' ? rawUid : '';
      if (uid.length > 0) {
        const rawAt: preferences.ValueType = prefs.getSync(AccountConfig.KEY_LOGIN_AT, 0);
        const state: AccountState = {
          uid: uid,
          kind: AccountKind.HUAWEI,
          loginAt: typeof rawAt === 'number' ? rawAt : 0
        };
        AccountStore.current = state;
      }
      Logger.info(TAG, `恢复登录态 kind=${AccountStore.current.kind} uid=${AccountStore.masked()}`);
      return AccountStore.current;
    } catch (err) {
      throw new AppError(ErrorCode.ACCOUNT_PREFERENCES_FAILED,
        `登录态读取失败: ${(err as Error).message}`, err as Error);
    }
  }

  /**
   * 静默登录：forceLogin=false 不拉起账号界面，取 UnionID。
   * AGC Client ID / 证书指纹未配置时（AccountConfig.ACCOUNT_KIT_ENABLED=false）直接走游客分区。
   */
  static async login(context: common.Context): Promise<AccountState> {
    if (!AccountConfig.ACCOUNT_KIT_ENABLED) {
      Logger.warn(TAG, 'Account Kit 未启用，保持本机游客分区');
      return AccountStore.current;
    }
    try {
      const provider: authentication.HuaweiIDProvider = new authentication.HuaweiIDProvider();
      const request: authentication.LoginWithHuaweiIDRequest = provider.createLoginWithHuaweiIDRequest();
      request.forceLogin = false;
      const controller: authentication.AuthenticationController =
        new authentication.AuthenticationController(context);
      const response: authentication.LoginWithHuaweiIDResponse =
        await controller.executeRequest(request) as authentication.LoginWithHuaweiIDResponse;
      const unionId: string = response.data === undefined ? '' : response.data.unionID;
      if (unionId.length === 0) {
        throw new AppError(ErrorCode.ACCOUNT_LOGIN_FAILED, '静默登录响应缺少 UnionID');
      }
      await AccountStore.persist(unionId);
      Logger.info(TAG, `静默登录成功 uid=${AccountStore.masked()}`);
    } catch (err) {
      Logger.warn(TAG, `静默登录失败，退回游客分区: ${(err as Error).message}`);
    }
    return AccountStore.current;
  }

  /** 日志用：UnionID 只留前 6 位，避免完整标识落 hilog */
  static masked(): string {
    const uid: string = AccountStore.current.uid;
    return uid.length <= 6 ? uid : `${uid.substring(0, 6)}***`;
  }

  private static async persist(unionId: string): Promise<void> {
    const state: AccountState = {
      uid: unionId,
      kind: AccountKind.HUAWEI,
      loginAt: Date.now()
    };
    AccountStore.current = state;
    const prefs: preferences.Preferences | null = AccountStore.prefs;
    if (prefs === null) {
      throw new AppError(ErrorCode.ACCOUNT_PREFERENCES_FAILED, '登录态持久化前未 init');
    }
    prefs.putSync(AccountConfig.KEY_UNION_ID, unionId);
    prefs.putSync(AccountConfig.KEY_LOGIN_AT, state.loginAt);
    await prefs.flush();
  }
}
