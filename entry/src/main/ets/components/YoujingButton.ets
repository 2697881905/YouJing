/**
 * 契约按钮（handoff §6）：主/次/文本三变体，一屏只许一个实心主按钮（禁令 1）。
 *
 * 2026-10-24 去自绘：外壳改用官方 `Button`（ButtonType.Capsule + ButtonStyleMode 三档），
 * 背景/圆角/描边/按压态/阴影全部交回官方——原来的 primaryPress 换色 + onTouch + scale(0.97)
 * 是手抄官方行为，官方 stateEffect 本就有，且深色模式色板由系统管，手抄那份在深色下会偏。
 * 只保留文字与 symbol 的字号/颜色（官方 Button 的子内容不自动染色）。
 *
 * 状态表达仍禁用 opacity（禁令 10）。
 */

import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { LayoutTokens } from '../design/LayoutTokens';

export enum YoujingButtonVariant {
  PRIMARY = 'primary',
  SECONDARY = 'secondary',
  TEXT = 'text'
}

@Component
export struct YoujingButton {
  @Prop variant: YoujingButtonVariant = YoujingButtonVariant.PRIMARY;
  @Prop label: string = '';
  @Prop fullWidth: boolean = false;
  /** 非满宽时的按钮宽度（屏3 上一题/下一题 ≈150vp） */
  @Prop buttonWidth: Length = 150;
  @Prop leadingSymbol: Resource | undefined = undefined;
  @Prop trailingSymbol: Resource | undefined = undefined;
  onAction?: () => void = undefined;

  private labelColor(): Resource {
    return this.variant === YoujingButtonVariant.PRIMARY ? ColorTokens.onPrimary : ColorTokens.ink;
  }

  build() {
    Button() {
      Row({ space: 8 }) {
        if (this.leadingSymbol !== undefined) {
          SymbolGlyph(this.leadingSymbol)
            .fontSize(18)
            .fontColor([this.labelColor()])
        }
        Text(this.label)
          .fontSize(TypeTokens.body.size)
          .fontWeight(this.variant === YoujingButtonVariant.PRIMARY ? 600 : 400)
          .fontColor(this.labelColor())
          .fontFeature("'tnum' on")
        if (this.trailingSymbol !== undefined) {
          SymbolGlyph(this.trailingSymbol)
            .fontSize(18)
            .fontColor([this.labelColor()])
        }
      }
      .justifyContent(FlexAlign.Center)
    }
    .type(this.variant === YoujingButtonVariant.TEXT ? ButtonType.Normal : ButtonType.Capsule)
    .buttonStyle(this.variant === YoujingButtonVariant.PRIMARY
      ? ButtonStyleMode.EMPHASIZED
      : (this.variant === YoujingButtonVariant.SECONDARY ? ButtonStyleMode.NORMAL : ButtonStyleMode.TEXTUAL))
    .height(LayoutTokens.minTouchTarget)
    .width(this.fullWidth ? '100%' : this.buttonWidth)
    .onClick(() => {
      if (this.onAction !== undefined) {
        this.onAction();
      }
    })
  }
}
