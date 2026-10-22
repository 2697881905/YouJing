/**
 * 契约按钮（handoff §6）：主/次/文本三变体，一屏只许一个实心主按钮（禁令 1）。
 * 主按钮：实心 primary，高 44，圆角 pill，标签 16/600 onPrimary；
 * 按下 primaryPress + scale(0.97)/140ms（MotionTokens 契约值）。
 * 次按钮：透明底 + borderSubtle 1px，标签 14/400 ink，命中 44。
 * 状态表达禁用 opacity（禁令 10）。
 */

import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { MotionTokens } from '../design/MotionTokens';
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
  @State private pressed: boolean = false;

  private applyPress(down: boolean): void {
    this.getUIContext().animateTo({
      duration: MotionTokens.pressDuration,
      curve: Curve.Sharp
    }, () => {
      this.pressed = down;
    });
  }

  build() {
    Row({ space: 8 }) {
      if (this.leadingSymbol !== undefined) {
        SymbolGlyph(this.leadingSymbol)
          .fontSize(18)
          .fontColor([this.variant === YoujingButtonVariant.PRIMARY
            ? ColorTokens.onPrimary : ColorTokens.ink])
      }
      Text(this.label)
        .fontSize(TypeTokens.body.size)
        .fontWeight(this.variant === YoujingButtonVariant.PRIMARY ? 600 : 400)
        .fontColor(this.variant === YoujingButtonVariant.PRIMARY
          ? ColorTokens.onPrimary : ColorTokens.ink)
        .fontFeature("'tnum' on")
      if (this.trailingSymbol !== undefined) {
        SymbolGlyph(this.trailingSymbol)
          .fontSize(18)
          .fontColor([this.variant === YoujingButtonVariant.PRIMARY
            ? ColorTokens.onPrimary : ColorTokens.ink])
      }
    }
    .justifyContent(FlexAlign.Center)
    .height(LayoutTokens.minTouchTarget)
    .width(this.fullWidth ? '100%' : this.buttonWidth)
    .padding({ left: 16, right: 16 })
    .borderRadius(RadiusTokens.pill)
    .backgroundColor(this.variant === YoujingButtonVariant.PRIMARY
      ? (this.pressed ? ColorTokens.primaryPress : ColorTokens.primary)
      : ColorTokens.canvas)
    .border(this.variant === YoujingButtonVariant.SECONDARY
      ? { width: 1, color: ColorTokens.borderSubtle, radius: RadiusTokens.pill }
      : { width: 0 })
    .scale({ x: this.pressed ? MotionTokens.pressScale : 1, y: this.pressed ? MotionTokens.pressScale : 1 })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.applyPress(true);
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.applyPress(false);
      }
    })
    .onClick(() => {
      if (this.onAction !== undefined) {
        this.onAction();
      }
    })
  }
}
