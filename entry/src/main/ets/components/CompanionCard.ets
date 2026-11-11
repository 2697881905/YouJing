/**
 * 伴随助手 · 请示卡（决策卡）。
 *
 * 组件一致性：不造新视觉语言——玻璃面用 GlassPanel，选项用 OptionCard（选中态=品牌实心，
 * 与屏3 追问选项同源），文字/间距/圆角走现有 token。一张卡 = 标题 + 后果说明 + 可点选选项，
 * 推荐项高亮（保姆级：思考做完，用户多数只确认）。通知态多一句「照你习惯」透明化提示。
 *
 * 本组件只渲染 CompanionPrompt 并把点选/划掉回调抛给集成层；不直接改行程。
 */

import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { IconSizes } from '../design/LayoutTokens';
import { GlassPanel } from './GlassPanel';
import { OptionCard } from './OptionCard';
import { CompanionOption, CompanionPrompt } from '../companion/CompanionTypes';

const EMPTY_PROMPT: CompanionPrompt = {
  id: '', kind: 'unplanned_arrival', title: '', detail: '',
  options: [], recommendedIndex: 0, stake: 'low', mode: 'ask'
};

@Component
export struct CompanionCard {
  @Prop prompt: CompanionPrompt = EMPTY_PROMPT;
  /** 点选第 index 个选项 */
  onSelect?: (index: number) => void = undefined;
  /** 划掉/关闭（沉默也是回答） */
  onDismiss?: () => void = undefined;

  build() {
    GlassPanel({ radius: RadiusTokens.hero, useSystemMaterial: true }) {
      Column({ space: SpaceTokens.sm }) {
        Row() {
          Text(this.prompt.title)
            .fontSize(TypeTokens.headline.size)
            .fontWeight(TypeTokens.headline.weight)
            .fontFamily(TypeTokens.title.family)
            .fontColor(ColorTokens.ink)
            .layoutWeight(1)
          Button() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(IconSizes.control)
              .fontColor([ColorTokens.muted])
          }
          .width(44)
          .height(44)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            if (this.onDismiss !== undefined) {
              this.onDismiss();
            }
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        Text(this.prompt.detail)
          .fontSize(TypeTokens.small.size)
          .fontWeight(450)
          .fontColor(ColorTokens.body)
          .width('100%')

        if (this.prompt.mode === 'notify') {
          Text('照你之前的习惯，先这么安排了，可随时撤销')
            .fontSize(TypeTokens.caption.size)
            .fontWeight(450)
            .fontColor(ColorTokens.muted)
            .width('100%')
        }

        ForEach(this.prompt.options, (opt: CompanionOption, idx: number) => {
          OptionCard({
            label: opt.label,
            subline: opt.subline,
            selected: idx === this.prompt.recommendedIndex,
            onAction: (): void => {
              if (this.onSelect !== undefined) {
                this.onSelect(idx);
              }
            }
          })
        }, (opt: CompanionOption, idx: number): string => `${this.prompt.id}-${opt.key}`)
      }
      .width('100%')
    }
  }
}