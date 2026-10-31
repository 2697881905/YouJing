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
 * 所以本轮 `avatarOf()` 恒返回符号占位，`displayName()` 回脱敏 ID。
 */

import { AccountStore } from './AccountStore';

/**
 * 头像描述。ArkTS V1 不支持联合类型，用 `kind` 字符串判别，
 * 两个取值由 `KIND_*` 常量给出，页面侧不要写字面量比较。
 */
export interface AvatarSpec {
  kind: string;
  /** kind='symbol' 时用：官方符号 */
  symbol?: Resource;
  /** kind='image' 时用：可访问的图片地址（本轮不产出） */
  url?: string;
}

export class ProfileStore {
  static readonly KIND_SYMBOL: string = 'symbol';
  static readonly KIND_IMAGE: string = 'image';

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

  /** 昵称位：游客说清是游客，已登录给脱敏 UnionID（不铺全串） */
  static displayName(): string {
    return AccountStore.isGuest() ? '游客空间' : AccountStore.masked();
  }

  /** 副标题：把"数据只在本机"这件事说在资料区，而不是只写在隐私政策里 */
  static displayHint(): string {
    return AccountStore.isGuest() ? '登录后行程留在本机，换设备不同步'
      : '行程与记账只存本机，不上传服务器';
  }
}
