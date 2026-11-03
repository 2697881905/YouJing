/**
 * 间距 tokens · 契约阶梯（DESIGN.md §spacing）：xxs4 / xs8 / sm12 / base16 / md20 / lg24 / xl32 / xxl48。
 *
 * 2026-11-03（契约 v2 T6）把实现档名改成**契约同名同值**。此前是「值对齐、名字整体错一档」
 * （契约 xxs 在实现里叫 xs、契约 xs 叫 sm……），跨 App 复制一段组件时同一个 `md` 在
 * 有据是 20、在有径是 12，肉眼看不出、只在排版上错位。改名全程**零像素**：
 * 644 个调用点按值一一映射（xs→xxs、sm→xs、md→sm、lg→base、xl→lg、fiveXl→xxl），
 * 没有消费方的 lgLoose(18)/threeXl(28)/twoXl(20)/fourXl(32)/bottomReserve(94) 一并删除。
 *
 * 稿件全 38 帧有离表间距 194 处（2/3/6/10/14px 为主），实现期一律并到本阶梯
 * （对照 handoff §7 逐帧必改表），不得照抄稿件值。
 * 屏专属滚动预留与缩进（60/72/76/81/100/124/138/180）走 LayoutTokens 具名层，
 * 未具名的离表值仍算缺陷（DESIGN.md §9 决议 6）。
 */

export interface SpaceTokensType {
  xxs: number;
  xs: number;
  sm: number;
  base: number;
  md: number;
  lg: number;
  xl: number;
  xxl: number;
}

export const SpaceTokens: SpaceTokensType = {
  xxs: 4,
  xs: 8,
  sm: 12,
  base: 16,
  md: 20,
  lg: 24,
  xl: 32,
  xxl: 48
};

/** 允许间距封闭集：契约 spacing 八档 + 0（audit 用） */
export const ALLOWED_SPACINGS: number[] = [0, 4, 8, 12, 16, 20, 24, 32, 48];
