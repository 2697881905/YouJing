/**
 * 伴随助手 · 行程页顶部请示横幅（取代旧的全局浮层）。
 *
 * 助手只活在行程页：有事（到站/规划外到访/该调整）时在页面顶部固定槽位浮一条横幅，
 * 占布局位置、不盖内容、不随列表滚走、不移动用户滚动位置（用户否掉了「自动滚到顶」）。
 * 收起 = AI 图标 + 一句标题 + 展开箭头 + 划掉；点横幅就地展开成完整请示卡（CompanionCard）。
 * 点选/划掉/纠正都抛给行程页处理（执行器恒在本页，无需跳转）。
 */

import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { CompanionCard } from './CompanionCard';
import { CompanionPrompt } from '../companion/CompanionTypes';

const EMPTY_PROMPT: CompanionPrompt = {
  id: '', kind: 'unplanned_arrival', title: '', detail: '',
  options: [], recommendedIndex: 0, stake: 'low', mode: 'ask'
};

@Component
export struct CompanionBanner {
  @Prop @Watch('onPromptChange') prompt: CompanionPrompt = EMPTY_PROMPT;
  @State private expanded: boolean = false;
  /** 行程页每次 build 都重新 parse 出新对象，@Watch 会频繁触发；只在 id 真变（新提示）时才收起 */
  private lastPromptId: string = '';
  onSelect?: (index: number) => void = undefined;
  onDismiss?: () => void = undefined;
  onCorrect?: () => void = undefined;

  onPromptChange(): void {
    if (this.prompt.id !== this.lastPromptId) {
      this.lastPromptId = this.prompt.id;
      this.expanded = false;
    }
  }

  build() {
    if (this.expanded) {
      CompanionCard({
        prompt: this.prompt,
        onSelect: (idx: number): void => {
          this.expanded = false;
          if (this.onSelect !== undefined) {
            this.onSelect(idx);
          }
        },
        onDismiss: (): void => {
          if (this.onDismiss !== undefined) {
            this.onDismiss();
          }
        },
        onCorrect: (): void => {
          if (this.onCorrect !== undefined) {
            this.onCorrect();
          }
        }
      })
    } else {
      Row({ space: SpaceTokens.xs }) {
        SymbolGlyph($r('sys.symbol.wand_and_stars'))
          .fontSize(IconSizes.control)
          .fontColor([ColorTokens.primary])
        Text(this.prompt.title)
          .fontSize(TypeTokens.small.size)
          .fontWeight(600)
          .fontColor(ColorTokens.ink)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(IconSizes.control)
          .fontColor([ColorTokens.muted])
        Button() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(IconSizes.control)
            .fontColor([ColorTokens.muted])
        }
        .width(LayoutTokens.minTouchTarget)
        .height(LayoutTokens.minTouchTarget)
        .backgroundColor(Color.Transparent)
        .onClick((): void => {
          if (this.onDismiss !== undefined) {
            this.onDismiss();
          }
        })
      }
      .width('100%')
      .padding(SpaceTokens.base)
      .borderRadius(RadiusTokens.card)
      .backgroundColor(ColorTokens.surfaceElevated)
      .onClick((): void => {
        this.expanded = true;
      })
    }
  }
}