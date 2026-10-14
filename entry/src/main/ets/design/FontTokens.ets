/**
 * 字体 tokens · 字号单位 fp，字重为数值档位。
 * pages/components 中 fontSize/fontWeight 一律引用本文件，禁止裸数值。
 */

export interface FontTokensType {
  /** 说明文字/标签 */
  sizeCaption: number;
  /** 正文 */
  sizeBody: number;
  /** 小标题/列表主文案 */
  sizeSubtitle: number;
  /** 页面标题 */
  sizeTitle: number;
  /** 大标题/数字强调 */
  sizeHeadline: number;
  weightRegular: number;
  weightMedium: number;
  weightBold: number;
}

export const FontTokens: FontTokensType = {
  sizeCaption: 12,
  sizeBody: 14,
  sizeSubtitle: 16,
  sizeTitle: 20,
  sizeHeadline: 24,
  weightRegular: 400,
  weightMedium: 500,
  weightBold: 700
};
