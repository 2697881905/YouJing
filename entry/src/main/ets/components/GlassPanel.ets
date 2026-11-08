/**
 * 普通内容卡玻璃面 · 2026-11-07 按有据 `design/components/GlassPanel.ets:17-29` 移植。
 *
 * 内容卡只在登记点位走系统背景模糊，不加 HDS 双边流光（浮层才需要）。
 * useSystemMaterial=true 且系统材质生效时，自绘描边/阴影/模糊全部归零，避免双圈描边与灰缝。
 * 三条避让：材质生效归零 / 内容区 systemMaterial 不渲染 / API 门禁只住 utils/immersiveMaterial.ets。
 */

import { ColorTokens } from '../design/ColorTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { ShadowTokens } from '../design/ShadowTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { GlassBlurStyle, isSystemMaterialActive } from '../utils/immersiveMaterial';
import { GlassTokens } from './GlassTokens';

@Component
export struct GlassPanel {
  @BuilderParam content: () => void = this.emptyContent;
  @Prop panelPadding: number = SpaceTokens.base;
  @Prop radius: number = RadiusTokens.hero;
  /** 由系统材质接管表面时置 true，自绘层归零 */
  @Prop useSystemMaterial: boolean = false;

  @Builder
  emptyContent(): void {
  }

  private materialOn(): boolean {
    return this.useSystemMaterial && isSystemMaterialActive();
  }

  private surfaceBlur(): BlurStyle {
    return this.materialOn() ? BlurStyle.NONE : GlassBlurStyle.Card;
  }

  private edgeWidth(): number {
    return this.materialOn() ? 0 : LayoutTokens.glassBorderWidth;
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .padding(this.panelPadding)
    .backgroundBlurStyle(this.surfaceBlur())
    .backgroundColor(this.materialOn() ? Color.Transparent : GlassTokens.CARD_BG)
    .border({ width: this.edgeWidth(), color: ColorTokens.separator, style: BorderStyle.Solid })
    .borderRadius(this.radius)
    .shadow(this.materialOn() ? ShadowTokens.none : ShadowTokens.cardAmbient)
    .clip(true)
  }
}
