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
 */

export interface ElevationSpec {
  radius: number;
  offsetX: number;
  offsetY: number;
  color: string;
}

export interface ShadowTokensType {
  /** 卡片下沿的实边 */
  contact: ElevationSpec;
  /** 行程卡 / 摘要卡 */
  card: ElevationSpec;
  /** dock / 弹层 / 拖动中的行 */
  floating: ElevationSpec;
  /** 分段控件轨道 */
  segmented: ElevationSpec;
  /** 浮层菜单 */
  popover: ElevationSpec;
}

export const ShadowTokens: ShadowTokensType = {
  contact: { radius: 1, offsetX: 0, offsetY: 0, color: '#08000000' },
  card: { radius: 10, offsetX: 0, offsetY: 3, color: '#12000000' },
  floating: { radius: 16, offsetX: 0, offsetY: 6, color: '#17000000' },
  segmented: { radius: 8, offsetX: 0, offsetY: 0, color: '#0F000000' },
  popover: { radius: 8, offsetX: 0, offsetY: 0, color: '#12000000' }
};
