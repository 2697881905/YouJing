/**
 * 间距 tokens · 阶梯封闭（handoff §4，脚本自 DESIGN.md 解析）：
 * 4/8/12/16/18/20/24/28/32/48/94，基线 4px，所有尺寸取 4 的倍数。
 *
 * 稿件全 38 帧有离表间距 194 处（2/3/6/10/14px 为主），实现期一律并到本阶梯
 * （对照 handoff §7 逐帧必改表），不得照抄稿件值。
 * 屏专属滚动预留与缩进（60/72/76/81/100/124/138/180）走 LayoutTokens 具名层，
 * 未具名的离表值仍算缺陷（DESIGN.md §9 决议 6）。
 */

export interface SpaceTokensType {
  xs: number;
  sm: number;
  md: number;
  lg: number;
  xl: number;
  /** 18 · 具名档 */
  lgLoose: number;
  /** 20 */
  twoXl: number;
  /** 28 */
  threeXl: number;
  /** 32 */
  fourXl: number;
  /** 48 */
  fiveXl: number;
  /** 94 · 通用底部滚动预留 */
  bottomReserve: number;
}

export const SpaceTokens: SpaceTokensType = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 24,
  lgLoose: 18,
  twoXl: 20,
  threeXl: 28,
  fourXl: 32,
  fiveXl: 48,
  bottomReserve: 94
};

/** 允许间距封闭集（不含 Layout 具名层），audit 用 */
export const ALLOWED_SPACINGS: number[] = [0, 4, 8, 12, 16, 18, 20, 24, 28, 32, 48, 94];
