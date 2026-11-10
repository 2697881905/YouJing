/**
 * 圆角 tokens · 封闭八值（handoff §4）：0/6/10/14/20/28/30/999，不许收紧也不许加宽。
 */

export interface RadiusTokensType {
  /** 直角 */
  none: number;
  /** 媒体与卡内嵌套 */
  media: number;
  /** 胶囊与输入 */
  capsule: number;
  /** 理由件 */
  reason: number;
  /** 卡片与弹层 */
  card: number;
  /** hero 面板 */
  hero: number;
  /** dock 与分段控件 */
  dock: number;
  /** 所有按钮/徽标/头像 */
  pill: number;
  /** 有据同名档：玻璃胶囊按钮圆角（GlassPillButton） */
  floatingBar: number;
  /** 有据同名档 = 20（资料卡/预览卡圆角，EditableProfilePreview 用） */
  lg: number;
}

export const RadiusTokens: RadiusTokensType = {
  none: 0,
  media: 6,
  capsule: 10,
  reason: 14,
  card: 20,
  hero: 28,
  dock: 30,
  pill: 999,
  /** 有据同名档 = 30（glass_radius_floating_bar）：玻璃胶囊按钮（GlassPillButton） */
  floatingBar: 30,
  lg: 20
};

/** 允许圆角封闭集，audit 用 */
export const ALLOWED_RADII: number[] = [0, 6, 10, 14, 20, 28, 30, 999];
