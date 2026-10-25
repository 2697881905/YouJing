/**
 * 隐私政策 / 用户协议的明示同意闸门（对齐「有据」的规范环节）。
 *
 * 为什么必须有一道闸门而不是只在界面上写一句说明：个保法口径下，
 * 采集任何设备标识（这里是华为账号 UnionID）之前必须拿到明示同意，
 * 且「不同意」要能退出而不是静默继续。有据把这条做实到
 * 「同意前连主界面内容都不构建」（有据 Index.ets:1523/1544），本文件是有径侧的同款收口。
 *
 * 版本号跟着协议文本走：文案改了就把 CONSENT_VERSION 抬一档，
 * 老用户会被重新问一次（有据 auth.ets:17 同一做法）。
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Logger } from '../common/logger/Logger';

const TAG: string = 'ConsentStore';
const STORE_NAME: string = 'consent';
const KEY_AGREED: string = 'privacyAgreedAt';
const KEY_VERSION: string = 'privacyVersion';

/** 协议版本。改《隐私政策》/《用户协议》正文时同步抬这个值 */
export const CONSENT_VERSION: string = 'v1';

/** AppStorage 键：UI 侧用它做响应式闸门（@StorageProp + @Watch） */
export const CONSENT_AGREED_KEY: string = 'privacyAgreed';

export class ConsentStore {
  private static prefs: preferences.Preferences | null = null;
  private static agreed: boolean = false;

  /** 必须在任何采集动作之前调用；会把已存状态同步到 AppStorage 供 UI 门控 */
  static async init(context: common.Context): Promise<boolean> {
    try {
      ConsentStore.prefs = await preferences.getPreferences(context, STORE_NAME);
      const storedVersion: string =
        typeof ConsentStore.prefs.getSync(KEY_VERSION, '') === 'string'
          ? ConsentStore.prefs.getSync(KEY_VERSION, '') as string : '';
      const at: number = typeof ConsentStore.prefs.getSync(KEY_AGREED, 0) === 'number'
        ? ConsentStore.prefs.getSync(KEY_AGREED, 0) as number : 0;
      ConsentStore.agreed = at > 0 && storedVersion === CONSENT_VERSION;
    } catch (err) {
      // 读不到偏好就按「未同意」处理：闸门宁严勿松，误放行是合规事故，误重问只是多点一下
      Logger.warn(TAG, `同意态读取失败，按未同意处理: ${(err as Error).message}`);
      ConsentStore.agreed = false;
    }
    AppStorage.setOrCreate(CONSENT_AGREED_KEY, ConsentStore.agreed ? '1' : '0');
    return ConsentStore.agreed;
  }

  static isAgreed(): boolean {
    return ConsentStore.agreed;
  }

  /** 用户点「同意并继续」 */
  static async agree(): Promise<void> {
    ConsentStore.agreed = true;
    AppStorage.setOrCreate(CONSENT_AGREED_KEY, '1');
    const prefs: preferences.Preferences | null = ConsentStore.prefs;
    if (prefs === null) {
      Logger.warn(TAG, '未 init 就写同意态，只落了 AppStorage');
      return;
    }
    try {
      prefs.putSync(KEY_AGREED, Date.now());
      prefs.putSync(KEY_VERSION, CONSENT_VERSION);
      await prefs.flush();
      Logger.info(TAG, `已记录明示同意 version=${CONSENT_VERSION}`);
    } catch (err) {
      Logger.warn(TAG, `同意态持久化失败: ${(err as Error).message}`);
    }
  }

  /** 用户点「不同意」：调用方负责 terminateSelf，这里只留一行日志口径 */
  static decline(): void {
    ConsentStore.agreed = false;
    AppStorage.setOrCreate(CONSENT_AGREED_KEY, '0');
    Logger.info(TAG, '用户不同意隐私政策，按个保法口径退出应用');
  }
}
