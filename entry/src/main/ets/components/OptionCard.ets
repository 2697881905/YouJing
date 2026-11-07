/**
 * 追问选项卡（屏3/3b）。
 *
 * 2026-11-07 按有据源码全量对齐：选中态改为 `brandSolid` 实心底 + `onBrand` 字 +
 * 右上对勾，不再用 primary-tint + 1px primary 描边（C6 裁决已推翻）。
 * 外壳仍是官方 Button（按压态/焦点/无障碍由系统给），只把颜色换成契约 token。
 * 品牌实心底上的白字对比度：浅色 #0066CC ≥4.5:1，深色 #0050A0 7.91:1。
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
    return this.selected ? ColorTokens.onBrand : ColorTokens.ink;
  }

  private subColor(): Resource {
    return this.selected ? ColorTokens.onBrand : ColorTokens.muted;
  }

  private surface(): Resource {
    return this.selected ? ColorTokens.brandSolid : ColorTokens.surfaceElevated;
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
            .fontColor([ColorTokens.onBrand])
        }
      }
      .width('100%')
    }
    .width('100%')
    // 契约 option-chip minHeight 56（44 只是最小命中区）
    .constraintSize({ minHeight: LayoutTokens.questionOptionMinHeight })
    .padding({ left: SpaceTokens.base, right: SpaceTokens.base, top: SpaceTokens.base, bottom: SpaceTokens.base })
    .type(ButtonType.Normal)
    .borderRadius(RadiusTokens.card)
    .buttonStyle(ButtonStyleMode.NORMAL)
    .backgroundColor(this.surface())
    .onClick(() => {
      if (this.onAction !== undefined) {
        this.onAction();
      }
    })
  }
}
