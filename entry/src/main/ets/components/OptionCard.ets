/**
 * 追问选项卡（屏3/3b · handoff §6 徽章胶囊第③式 + DESIGN §9 选中配方）。
 *
 * 选中态按契约 recipe：primary-tint 底 + 1px primary 描边 + **ink 字** + 右上对勾。
 * 不用官方 EMPHASIZED 实心蓝——DESIGN.md §9 实测：tint 底上压蓝字双端 sub-AA，
 * 且实心 chip 会与同屏主按钮形成双实心蓝（禁令 1）。外壳仍是官方 Button
 * （NORMAL 档：按压态/焦点/无障碍由系统给），只把颜色换回契约 token。
 * 2026-10-24 曾一段时期走 EMPHASIZED「去自绘」，本轮按契约配方回摆并留痕。
 *
 * 状态切换禁用 opacity（禁令 10）。
 */

import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';

@Component
export struct OptionCard {
  @Prop label: string = '';
  @Prop subline: string = '';
  @Prop selected: boolean = false;
  onAction?: () => void = undefined;

  private titleColor(): Resource {
    // tint 底上永远是 ink 字（14.44:1），不是蓝字（4.49:1 sub-AA）
    return ColorTokens.ink;
  }

  private subColor(): Resource {
    return this.selected ? ColorTokens.body : ColorTokens.muted;
  }

  build() {
    Button() {
      Row() {
        Column({ space: 0 }) {
          Text(this.label)
            .fontSize(TypeTokens.body.size)
            .fontWeight(400)
            .fontColor(this.titleColor())
          Text(this.subline)
            .fontSize(TypeTokens.caption.size)
            .fontWeight(450)
            .fontColor(this.subColor())
            .fontFeature("'tnum' on")
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.selected) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(IconSizes.control)
            .fontColor([ColorTokens.primary])
        }
      }
      .width('100%')
    }
    .width('100%')
    // 契约 option-chip minHeight 56（44 只是最小命中区）
    .constraintSize({ minHeight: LayoutTokens.questionOptionMinHeight })
    .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, top: SpaceTokens.lg, bottom: SpaceTokens.lg })
    .type(ButtonType.Normal)
    .borderRadius(RadiusTokens.card)
    .buttonStyle(ButtonStyleMode.NORMAL)
    .backgroundColor(this.selected ? ColorTokens.primaryTint : ColorTokens.surfaceElevated)
    .border({
      width: this.selected ? LayoutTokens.glassBorderWidth : 0,
      color: ColorTokens.primary
    })
    .onClick(() => {
      if (this.onAction !== undefined) {
        this.onAction();
      }
    })
  }
}
