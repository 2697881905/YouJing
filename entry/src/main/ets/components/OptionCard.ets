/**
 * 追问选项卡（屏3/3b · handoff §6 徽章胶囊第③式）：
 * 未选 surfaceSubtle 实底；选中 primaryTint 底 + 1px primary 描边 + 右侧 check 图标。
 * 状态切换禁用 opacity（禁令 10），一律换 token。
 */

import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { LayoutTokens } from '../design/LayoutTokens';

@Component
export struct OptionCard {
  @Prop label: string = '';
  @Prop subline: string = '';
  @Prop selected: boolean = false;
  onAction?: () => void = undefined;

  build() {
    Row() {
      Column({ space: 0 }) {
        Text(this.label)
          .fontSize(TypeTokens.body.size)
          .fontWeight(600)
          .fontColor(ColorTokens.ink)
        Text(this.subline)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.body)
          .fontFeature("'tnum' on")
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.selected) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(22)
          .fontColor([ColorTokens.primary])
      }
    }
    .width('100%')
    .constraintSize({ minHeight: LayoutTokens.minTouchTarget })
    .padding(SpaceTokens.lg)
    .borderRadius(RadiusTokens.card)
    .backgroundColor(this.selected ? ColorTokens.primaryTint : ColorTokens.surfaceSubtle)
    .border({
      width: this.selected ? 1 : 0,
      color: ColorTokens.primary,
      radius: RadiusTokens.card
    })
    .onClick(() => {
      if (this.onAction !== undefined) {
        this.onAction();
      }
    })
  }
}
