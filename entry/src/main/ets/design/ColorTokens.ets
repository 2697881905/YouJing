/**
 * 色彩 tokens · 视觉常量单一事实源。
 *
 * 命名一律语义化（用途导向），禁止物理命名（如 red1、gray200）。
 * 当前仅浅色值（工程基线占位，数值以用户 UI 设计定稿为准替换）；
 * 暗色模式待接入 resources/dark 时扩展：届时同名 token 在暗色资源下取另一组值，
 * 或改走 $r 资源引用，切换方案在接入时评审。
 */

export interface ColorTokensType {
  /** 页面底色 */
  bgPage: string;
  /** 卡片/浮层表面色 */
  bgSurface: string;
  /** 主文本色 */
  textPrimary: string;
  /** 次级文本色（说明、辅助信息） */
  textSecondary: string;
  /** 主强调色（按钮、选中态、品牌色，占位待设计定稿） */
  accentPrimary: string;
  /** 分割线/描边色 */
  divider: string;
}

export const ColorTokens: ColorTokensType = {
  bgPage: '#F5F6F7',
  bgSurface: '#FFFFFF',
  textPrimary: '#1A1A1A',
  textSecondary: '#666666',
  accentPrimary: '#2E6BE6',
  divider: '#E5E5E5'
};
