/**
 * 阴影 tokens · 闭集（handoff §4），一条都不许多。
 *
 * 深色模式零阴影（DESIGN.md §9 决议 8）：elevation 在深色下不启用，
 * 层次靠亮度阶梯 #121212→#1E1E1E→#232326→#28282C。消费方按 ColorMode 门控：
 * 深色下不调用 .shadow()。
 *
 * 决议 4：hero 永不带影，elevation 只给卡片与浮层。
 * 决议 8 补充：dark-glass-bar-shadow 只描述 ArkTS 侧 HDS 材质自带的系统投影，
 * 不在此表内、不得翻成显式阴影声明。
 *
 * T10 前置半步（契约 v2 批次二）：**只加不改不删**地新增 `none`/`cardContact`/
 * `cardAmbient`/`pillFloat` 四档（值逐字取有据 shadow.ets），旧名 `contact`/`card`
 * 保留为别名——现存 4 个页面调用点（TripsPage/StayPickPage/MapPage/EditItineraryPage）
 * 还在用旧名。别名删除 + `floating` #17→#18 + 与契约 YAML 同批，全部随 T2；
 * 本轮**没有任何 .shadow( 新消费点**（带影件与判据反转必须同原子批，见 task-10 简报 §0.1）。
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
  /** 卡片下沿的实边（旧名，= cardContact 的别名；别名随批次二 T2 删除） */
  contact: ElevationSpec;
  /** 行程卡 / 摘要卡（旧名，= cardAmbient 的别名；别名随批次二 T2 删除） */
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
  floating: { radius: 16, offsetX: 0, offsetY: 6, color: '#17000000' },
  segmented: { radius: 8, offsetX: 0, offsetY: 0, color: '#0F000000' },
  popover: { radius: 8, offsetX: 0, offsetY: 0, color: '#12000000' }
};
