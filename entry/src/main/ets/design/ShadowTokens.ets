/**
 * 阴影 tokens · 闭集（handoff §4），一条都不许多。
 *
 * 深色模式零阴影是 **v1 旧口径（§9 决议 8）**：契约 v2 §Elevation 已反转（阴影 black-with-alpha、
 * 主题中立、不带归零分支），但尺子判据反转与 4 个页面的 isDark 门控删除**同属 T4 原子批**（ledger R32）。
 * T4 之前以尺为准：audit_elevation 仍要求 `.shadow(` 带 isDark/ColorMode/glassOn 门控。
 *
 * 决议 4：hero 永不带影，elevation 只给卡片与浮层。
 * 决议 8 补充：dark-glass-bar-shadow 只描述 ArkTS 侧 HDS 材质自带的系统投影，
 * 不在此表内、不得翻成显式阴影声明。
 *
 * T10 前置半步（契约 v2 批次二）：**只加不改不删**地新增 `none`/`cardContact`/
 * `cardAmbient`/`pillFloat` 四档（值逐字取有据 shadow.ets），旧名 `contact`/`card`
 * 保留为别名——现存 4 个页面调用点（TripsPage/StayPickPage/MapPage/EditItineraryPage）
 * 还在用旧名。T2′ 契约批已落：§Elevation 六档 YAML/散文升 v2，`floating` #17→#18
 * 随该批同改（有据 9.4%）；别名删除 + 深色门控移除 + BaseCard **并入 T4 原子批**
 * （ledger R32），本轮 `pages/**` 一个字未动、没有任何 .shadow( 新消费点。
 */

export interface ElevationSpec {
  radius: number;
  offsetX: number;
  offsetY: number;
  color: string;
}

export interface ShadowTokensType {
  /**
   * 显式关掉阴影（T10 前置档）：契约 v2 的 `none` 档。
   * 只作**值**用（`.shadow(ShadowTokens.none)` 或零值判据），本轮无消费点。
   */
  none: ElevationSpec;
  /** 卡片下沿的实边（`contact`≡`cardContact` 同值别名；T4 与门控删除/BaseCard 同原子批删） */
  contact: ElevationSpec;
  /** 行程卡 / 摘要卡（`card`≡`cardAmbient` 同值别名；T4 与门控删除/BaseCard 同原子批删） */
  card: ElevationSpec;
  /** 契约 v2 新档：卡片接触影（与 contact 同值，命名改为「接触/环境」二分） */
  cardContact: ElevationSpec;
  /** 契约 v2 新档：卡片环境影（与 card 同值） */
  cardAmbient: ElevationSpec;
  /** 契约 v2 新档：浮动胶囊的托起影（dock / 浮动 chip，非卡片） */
  pillFloat: ElevationSpec;
  /** dock / 弹层 / 拖动中的行 */
  floating: ElevationSpec;
  /** 分段控件轨道 */
  segmented: ElevationSpec;
  /** 浮层菜单 */
  popover: ElevationSpec;
}

export const ShadowTokens: ShadowTokensType = {
  none: { radius: 0, offsetX: 0, offsetY: 0, color: '#00000000' },
  contact: { radius: 1, offsetX: 0, offsetY: 0, color: '#08000000' },
  card: { radius: 10, offsetX: 0, offsetY: 3, color: '#12000000' },
  cardContact: { radius: 1, offsetX: 0, offsetY: 0, color: '#08000000' },
  cardAmbient: { radius: 10, offsetX: 0, offsetY: 3, color: '#12000000' },
  pillFloat: { radius: 8, offsetX: 0, offsetY: 3, color: '#26000000' },
  floating: { radius: 16, offsetX: 0, offsetY: 6, color: '#18000000' },
  segmented: { radius: 8, offsetX: 0, offsetY: 0, color: '#0F000000' },
  popover: { radius: 8, offsetX: 0, offsetY: 0, color: '#12000000' }
};
