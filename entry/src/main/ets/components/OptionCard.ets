/**
 * 追问选项卡（屏3/3b · handoff §6 徽章胶囊第③式）。
 *
 * 2026-10-24 去自绘：外壳改官方 `Button`（ButtonType.Normal + 圆角 card），
 * 选中/未选走官方 `ButtonStyleMode.EMPHASIZED / NORMAL` 两档，
 * 不再自己写 primaryTint 底色 + 1px primary 描边（那是手抄官方选中态）。
 * 文字颜色跟着档位翻：EMPHASIZED 档的实底上要换 onPrimary，否则深蓝字压蓝底。
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
    return this.selected ? ColorTokens.onPrimary : ColorTokens.ink;
  }

  private subColor(): Resource {
    return this.selected ? ColorTokens.onPrimary : ColorTokens.body;
  }

  build() {
    Button() {
      Row() {
        Column({ space: 0 }) {
          Text(this.label)
            .fontSize(TypeTokens.body.size)
            .fontWeight(600)
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
            .fontColor([this.subColor()])
        }
      }
      .width('100%')
    }
    .width('100%')
    .constraintSize({ minHeight: LayoutTokens.minTouchTarget })
    .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, top: SpaceTokens.lg, bottom: SpaceTokens.lg })
    .type(ButtonType.Normal)
    .borderRadius(RadiusTokens.card)
    .buttonStyle(this.selected ? ButtonStyleMode.EMPHASIZED : ButtonStyleMode.NORMAL)
    .onClick(() => {
      if (this.onAction !== undefined) {
        this.onAction();
      }
    })
  }
}
