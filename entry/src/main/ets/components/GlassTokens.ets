/**
 * 玻璃材质共享令牌 · 2026-11-07 按有据 `design/tokens/GlassTokens.ets` 移植。
 *
 * 两处消费方（GlowInput 分段玻璃 / 自绘玻璃栏面）此前各自维护同值常量，本文件统一上收。
 * 色值全部走本仓 ColorTokens（资源名不带 ds_ 前缀），深浅由系统 ColorMode 自动切换。
 *
 * 避让（三条，写在这里供所有自绘件共用）：
 * ① 材质生效时自绘 border / shadow / backgroundBlurStyle 必须归零，否则双圈描边 + 灰缝；
 * ② systemMaterial 只在 Navigation/NavDestination 标题栏或系统 TabBar 生效，内容区一律
 *    backgroundBlurStyle + 实色兜底；
 * ③ API 门禁（@since 23 / @since 26）只住在 utils/immersiveMaterial.ets，别处不得直写。
 */

import { ColorTokens } from '../design/ColorTokens';

export class GlassTokens {
  /** 分段玻璃底：浅色烟灰 / 深色白玻璃 */
  static readonly SEGMENT_BG: ResourceColor = ColorTokens.glassSegmentBg;
  /** 分段控件组件内成文例外（契约 v2），不是第五块栏面玻璃 */
  static readonly SEGMENT_BLUR: number = 20;
  static readonly SEGMENT_BORDER: ResourceColor = ColorTokens.glassSegmentBorder;
  /** 非分段玻璃时的系统玻璃底 */
  static readonly NORMAL_BG: ResourceColor = ColorTokens.glassBarSurface;
  static readonly CARD_BG: ResourceColor = ColorTokens.glassCardBg;
  static readonly BAR_BG: ResourceColor = ColorTokens.glassBarBg;
  static readonly PILL_FILL: ResourceColor = ColorTokens.glassPillFill;
  static readonly PILL_RIM: ResourceColor = ColorTokens.glassPillRim;
}
