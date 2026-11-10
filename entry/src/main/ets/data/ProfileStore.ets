/**
 * 「这个账号该显示什么」的唯一出口。
 *
 * 为什么要单独一层而不是在「我的」页里直接写死图标：头像同步是**已确认的后续需求**，
 * 但两条实现路各有代价、都还没拍——
 *   ① Account Kit 换 `AuthorizationWithHuaweiIDRequest` + `scopes:['profile']`：
 *      能拿到真昵称和头像 URL，但**会弹系统授权框**，破坏现在的静默登录，
 *      且头像 URL 的有效期/缓存要自己管；
 *   ② 接服务端存 URL（照姊妹应用「有据」那条 `user.avatar` → COS 直传的路）：
 *      静默不变，但本应用的定位是**纯客户端无后端**，开后端是产品形态变更。
 * 选哪条会改数据落点，但不会改 UI —— 所以这里只留出口：将来接真头像就是
 * 改 `avatarOf()` 的返回值再加一个写入点，页面结构与渲染分支一行不动。
 *
 * 现状：本仓 Account Kit 走的是 `authentication` 直取 `unionID`
 * （`AccountStore.ets:109`），`LoginWithHuaweiIDCredential` 的字段里
 * **没有头像也没有昵称**（只有 authorizationCode/idToken/openID/unionID），
 * 所以本轮 `avatarOf()` 恒返回符号占位；昵称/简介/性别由用户在编辑资料页
 * 自填，落本机 preferences（`saveProfile`）。
 *
 * 【与「有据」共享资料的前置口径（2026-11-10 用户确认）】
 * 资料区和账号信息未来要与有据共享，所以 `UserProfileData` 的字段名与语义
 * **逐一照抄有据 `models/types.ets` 的 `User`**：nickname / bio / gender(0=未设
 * 1=男 2=女) / avatar。共享方案落地时只换 `loadProfile/saveProfile` 这对读写
 * 的落点（本机 preferences → 共享服务端），模型、编辑页、显示层一行不动。
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AccountStore } from './AccountStore';
import { AccountConfig } from '../common/config/AccountConfig';
import { Logger } from '../common/logger/Logger';

const TAG: string = 'Data.ProfileStore';

/**
 * 用户资料。字段名与有据 `User` 同形（共享资料的模型契约），编辑资料页读写、
 * 资料区显示都只认这份结构。
 */
export interface UserProfileData {
  /** 空串 = 未自定义，显示层退账号派生名（脱敏 UnionID / 游客空间） */
  nickname: string;
  /** 一句话简介，空串 = 未填写 */
  bio: string;
  /** 0=未设 1=男 2=女（有据 User.gender 同语义） */
  gender: number;
  /**
   * 头像图源：base64 data URI（本轮本地选图）或 URL（共享后端落地后）。
   * 空串 = 未设置，显示层退符号占位（avatarOf）。
   */
  avatar: string;
  /**
   * 资料封面背景图源：同 avatar。有据 User.profileBackground 同名字段——
   * 资料卡（ProfileCoverCard）16:10 封面位的图源。
   */
  profileBackground: string;
}

function emptyProfile(): UserProfileData {
  const p: UserProfileData = { nickname: '', bio: '', gender: 0, avatar: '', profileBackground: '' };
  return p;
}

/**
 * AppStorage 键：资料写回广播（EntitlementStore.TICK_KEY 同款惯例）。
 * 资料区显示层订阅它，编辑页保存后即时回显——dock 根页不是 NavDestination，
 * 挂不上 onShown，跨页刷新只能靠广播。
 */
export const PROFILE_TICK_KEY: string = 'profileTick';

export class ProfileStore {
  static readonly KIND_SYMBOL: string = 'symbol';
  static readonly KIND_IMAGE: string = 'image';

  /** preferences key 前缀：按 uid 分键，与账号数据同一条 preferences 分片 */
  private static readonly KEY_PREFIX: string = 'profile_data_';

  /**
   * 取当前账号该显示的头像。`uid` 本轮没参与计算——
   * 留给接真头像之后按账号取图（本地图/服务端 URL 都要按 uid 分），
   * 现在删掉这个参数等于将来再改一次所有调用方。
   */
  static avatarOf(uid: string): AvatarSpec {
    const spec: AvatarSpec = {
      kind: ProfileStore.KIND_SYMBOL,
      symbol: $r('sys.symbol.person_crop_circle_fill_1')
    };
    return spec;
  }

  /**
   * 读用户资料（本机 preferences，JSON 串）。读不到/解析失败给全空缺省——
   * 资料本来就是可再填的，坏档不该拦住页面。
   */
  static async loadProfile(ctx: common.UIAbilityContext, uid: string): Promise<UserProfileData> {
    try {
      const prefs: preferences.Preferences =
        await preferences.getPreferences(ctx, AccountConfig.PREFERENCES_NAME);
      const raw: preferences.ValueType =
        prefs.getSync(ProfileStore.KEY_PREFIX + uid, '');
      if (typeof raw !== 'string' || raw.length === 0) {
        return emptyProfile();
      }
      const p: UserProfileData = JSON.parse(raw) as UserProfileData;
      // 缺字段补缺省（老 key 无新字段时结构兜底）
      return {
        nickname: typeof p.nickname === 'string' ? p.nickname : '',
        bio: typeof p.bio === 'string' ? p.bio : '',
        gender: typeof p.gender === 'number' ? p.gender : 0,
        avatar: typeof p.avatar === 'string' ? p.avatar : '',
        profileBackground: typeof p.profileBackground === 'string' ? p.profileBackground : ''
      };
    } catch (err) {
      const e = err as Error;
      Logger.warn(TAG, `读用户资料失败: ${e.message}`);
      return emptyProfile();
    }
  }

  /** 写回用户资料。JSON 串整存整取：加字段不用迁移旧 key。 */
  static async saveProfile(ctx: common.UIAbilityContext, uid: string, data: UserProfileData): Promise<void> {
    const prefs: preferences.Preferences =
      await preferences.getPreferences(ctx, AccountConfig.PREFERENCES_NAME);
    prefs.putSync(ProfileStore.KEY_PREFIX + uid, JSON.stringify(data));
    await prefs.flush();
    AppStorage.setOrCreate(PROFILE_TICK_KEY, Date.now());
    Logger.info(TAG, `用户资料已保存 uid=${uid} gender=${data.gender}`);
  }

  /**
   * 显示名：用户自填昵称优先（trim 后非空），否则退账号派生——
   * 游客说清是游客，已登录给脱敏 UnionID（不铺全串）。
   */
  static displayName(profile: UserProfileData): string {
    if (profile.nickname.trim().length > 0) {
      return profile.nickname.trim();
    }
    return AccountStore.isGuest() ? '游客空间' : AccountStore.masked();
  }

  /**
   * 资料区副标题：用户简介优先（有据 bio 同位），没填就退隐私说明——
   * 那句「行程与记账只存本机」是本应用与有据的实质差异，不能被空 bio 吃掉。
   */
  static profileSubtitle(profile: UserProfileData): string {
    if (profile.bio.trim().length > 0) {
      return profile.bio.trim();
    }
    return ProfileStore.displayHint();
  }

  /** 隐私说明（资料区副标题缺省位） */
  static displayHint(): string {
    return AccountStore.isGuest() ? '登录后行程留在本机，换设备不同步'
      : '行程与记账只存本机，不上传服务器';
  }
}

/** 头像描述。ArkTS V1 不支持联合类型，用 `kind` 字符串判别 */
export interface AvatarSpec {
  /** kind='symbol' 时用：官方符号 */
  symbol?: Resource;
  /** kind='image' 时用：可访问的图片地址（本轮不产出） */
  url?: string;
  /** 判别字符串，两个取值由 `KIND_*` 常量给出，页面侧不要写字面量比较 */
  kind: string;
}
