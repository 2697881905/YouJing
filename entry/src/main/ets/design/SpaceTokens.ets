/**
 * 间距 tokens · 单位 vp。
 * 五档间距梯度，pages/components 中 padding/margin/gap 一律引用本文件，禁止裸数值。
 */

export interface SpaceTokensType {
  xs: number;
  sm: number;
  md: number;
  lg: number;
  xl: number;
}

export const SpaceTokens: SpaceTokensType = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 24
};
