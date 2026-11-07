/**
 * 按钮 · 2026-11-07 按有据 `design/components/DesignButton.ets:9-130` 移植（组件体系主件）。
 *
 * 四变体：primary（brandSolid + onBrand，一屏只许一颗）/ outlined（透明 + 1vp barBorder + pill）/
 * ghost（primary 字 + reason 圆角）/ glass（elevated 底 + separator 描边 + cardAmbient 影）。
 * 字档 callout 14 / headline.weight 600；禁用 `.opacity(0.45)`；按下反馈交给 Pressable
 * （opacity 0.92 + scale 0.97 / 140ms），不在本件重复实现 stateStyles。
 *
 * 三条避让：材质生效时自绘 border/shadow/blur 归零；内容区 systemMaterial 不渲染；
 * API 门禁只住 utils/immersiveMaterial.ets。不做 hover（有据源码 0 处）。
 */

import { ColorTokens } from '../design/ColorTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { MotionCurves, MotionTokens } from '../design/MotionTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { ShadowTokens } from '../design/ShadowTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { TypeTokens } from '../design/TypeTokens';
import { isSystemMaterialActive, TopButtonMaterialModifier } from '../utils/immersiveMaterial';
import { Pressable } from './Pressable';

export enum DesignButtonVariant {
  PRIMARY = 'primary',
  OUTLINED = 'outlined',
  GHOST = 'ghost',
  GLASS = 'glass'
}

@Component
export struct DesignButton {
  @Prop label: string = '';
  @Prop variant: DesignButtonVariant = DesignButtonVariant.PRIMARY;
  @Prop disabled: boolean = false;
  @Prop fillWidth: boolean = false;
  /** 非满宽时的按钮宽度 */
  @Prop visualWidth: Length = 150;
  @Prop leadingSymbol: Resource | undefined = undefined;
  @Prop trailingSymbol: Resource | undefined = undefined;
  /** 驻留 Navigation 标题栏时由系统材质接管按钮表面 */
  @Prop useSystemMaterial: boolean = false;
  onAction?: () => void = undefined;
  private materialModifier: TopButtonMaterialModifier = new TopButtonMaterialModifier();

  private isPrimary(): boolean {
    return this.variant === DesignButtonVariant.PRIMARY;
  }

  private isGlass(): boolean {
    return this.variant === DesignButtonVariant.GLASS;
  }

  private materialOn(): boolean {
    return this.useSystemMaterial && isSystemMaterialActive();
  }

  private labelColor(): Resource {
    return this.isPrimary() ? ColorTokens.onBrand : ColorTokens.primary;
  }

  private surface(): ResourceColor {
    if (this.isPrimary()) {
      return ColorTokens.brandSolid;
    }
    if (this.isGlass()) {
      return ColorTokens.surfaceElevated;
    }
    return Color.Transparent;
  }

  private edgeWidth(): number {
    if (this.materialOn() || this.isPrimary()) {
      return 0;
    }
    return LayoutTokens.glassBorderWidth;
  }

  private edgeColor(): ResourceColor {
    if (this.isGlass()) {
      return ColorTokens.separator;
    }
    return this.variant === DesignButtonVariant.OUTLINED
      ? ColorTokens.glassBarBorder : ColorTokens.primary;
  }

  private cornerRadius(): number {
    return this.variant === DesignButtonVariant.GHOST
      ? RadiusTokens.reason : RadiusTokens.pill;
  }

  private safeLabel(): string {
    return this.label ?? '';
  }

  build() {
    Pressable({
      disabled: this.disabled,
      fillWidth: this.fillWidth,
      visualHeight: LayoutTokens.minTouchTarget,
      touchTargetHeight: LayoutTokens.minTouchTarget,
      action: () => {
        if (this.onAction !== undefined) {
          this.onAction();
        }
      }
    }) {
      Row({ space: SpaceTokens.xxs }) {
        if (this.leadingSymbol !== undefined) {
          SymbolGlyph(this.leadingSymbol)
            .fontSize(IconSizes.control)
            .fontColor([this.labelColor()])
        }
        Text(this.safeLabel())
          .fontSize(TypeTokens.callout.size)
          .fontWeight(TypeTokens.headline.weight)
          .fontFamily(TypeTokens.callout.family)
          .fontColor(this.labelColor())
          .fontFeature("'tnum' on")
        if (this.trailingSymbol !== undefined) {
          SymbolGlyph(this.trailingSymbol)
            .fontSize(IconSizes.control)
            .fontColor([this.labelColor()])
        }
      }
      .justifyContent(FlexAlign.Center)
      .width(this.fillWidth ? '100%' : this.visualWidth)
      .height(LayoutTokens.minTouchTarget)
      .padding({ left: SpaceTokens.base, right: SpaceTokens.base })
      .backgroundColor(this.materialOn() ? Color.Transparent : this.surface())
      .border({ width: this.edgeWidth(), color: this.edgeColor(), style: BorderStyle.Solid })
      .borderRadius(this.cornerRadius())
      .shadow(this.materialOn() ? ShadowTokens.none
        : (this.isGlass() ? ShadowTokens.cardAmbient : ShadowTokens.none))
      .opacity(this.disabled ? 0.45 : 1)
      .animation({ duration: MotionTokens.fast, curve: MotionCurves.standard })
      .attributeModifier(this.materialOn() ? this.materialModifier : undefined)
    }
  }
}
