/**
 * 屏3 偏好追问状态机（帧 b6b3126b）+ 屏3b 节奏多选数据态（帧 480d5d03，同屏非新路由）。
 * 必改表已落：option-text-group gap 2→0。
 * 兜底口径（§4.2）：每题有 defaultValues，「帮我选」一键填当前题默认并推进；
 * 全部答完（或直接推进到底）触发 SpotPick（批次 4 落地，暂进占位页）。
 */

import { APP_NAV } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { QuestionFlowConfig } from '../common/constants/QuestionFlowConfig';
import { FlowQuestion, QuestionOption } from '../model/PlanParams';
import { OptionCard } from '../components/OptionCard';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';

@Component
export struct PreferenceQAPage {
  private pathStack: NavPathStack = APP_NAV;
  @State private qIndex: number = 0;
  @State private singleAnswers: string[] = ['leisure', 'comfort', 'public', ''];
  @State private paceAnswers: string[] = [];
  private questions: FlowQuestion[] = QuestionFlowConfig.QUESTIONS;

  private isMulti(q: FlowQuestion): boolean {
    return q.multiSelect;
  }

  private isSelected(q: FlowQuestion, value: string, qIdx: number): boolean {
    if (this.isMulti(q)) {
      return this.paceAnswers.indexOf(value) >= 0;
    }
    return this.singleAnswers[qIdx] === value;
  }

  private toggle(q: FlowQuestion, value: string, qIdx: number): void {
    if (this.isMulti(q)) {
      const next: string[] = this.paceAnswers.slice();
      const at: number = next.indexOf(value);
      if (at >= 0) {
        next.splice(at, 1);
      } else {
        next.push(value);
      }
      this.paceAnswers = next;
    } else {
      const next: string[] = this.singleAnswers.slice();
      next[qIdx] = value;
      this.singleAnswers = next;
    }
  }

  private helpPick(): void {
    const q: FlowQuestion = this.questions[this.qIndex];
    this.toggleAllDefaultsOf(q);
    this.advance();
  }

  private toggleAllDefaultsOf(q: FlowQuestion): void {
    if (this.isMulti(q)) {
      this.paceAnswers = q.defaultValues.slice();
    } else {
      const next: string[] = this.singleAnswers.slice();
      next[this.qIndex] = q.defaultValues[0];
      this.singleAnswers = next;
    }
  }

  private advance(): void {
    if (this.qIndex < this.questions.length - 1) {
      this.qIndex += 1;
    } else {
      // 批次 4：进入屏4 景点挑选；当前进占位
      this.pathStack.pushPath({ name: 'SpotPick' });
    }
  }

  private goBack(): void {
    if (this.qIndex > 0) {
      this.qIndex -= 1;
    } else {
      this.pathStack.pop();
    }
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
          Text(`第 ${this.qIndex + 1}/${this.questions.length} 步`)
            .fontSize(TypeTokens.overline.size)
            .fontWeight(600)
            .fontColor(ColorTokens.muted)
            .fontFeature("'tnum' on")
          Blank()
          Text('偏好追问')
            .fontSize(TypeTokens.body.size)
            .fontWeight(600)
            .fontColor(ColorTokens.ink)
        }
        .width('100%')
        .height(LayoutTokens.titleBarHeight)
        .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })

        Row() {
          Row()
            .height(4)
            .layoutWeight(this.qIndex + 1)
            .borderRadius(RadiusTokens.pill)
            .backgroundColor(ColorTokens.primary)
          Row()
            .height(4)
            .layoutWeight(this.questions.length - this.qIndex - 1)
            .borderRadius(RadiusTokens.pill)
            .backgroundColor(ColorTokens.hairline)
        }
        .width('100%')
        .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })

        Scroll() {
          Column() {
            Text(this.questions[this.qIndex].title)
              .fontSize(TypeTokens.title.size)
              .fontWeight(700)
              .fontFamily(TypeTokens.title.family)
              .fontColor(ColorTokens.ink)
              .margin({ top: SpaceTokens.xl, bottom: SpaceTokens.xs })
            Text(this.questions[this.qIndex].helper === undefined ? '' : this.questions[this.qIndex].helper as string)
              .fontSize(TypeTokens.small.size)
              .fontColor(ColorTokens.body)
              .margin({ bottom: SpaceTokens.xl })

            Column({ space: LayoutTokens.questionOptionGap }) {
              ForEach(this.questions[this.qIndex].options,
                (opt: QuestionOption) => {
                  OptionCard({
                    label: opt.label,
                    subline: opt.desc === undefined ? '' : opt.desc,
                    selected: this.isSelected(this.questions[this.qIndex], opt.value, this.qIndex),
                    onAction: (): void => {
                      this.toggle(this.questions[this.qIndex], opt.value, this.qIndex);
                    }
                  })
                }, (opt: QuestionOption): string =>
                  `${this.questions[this.qIndex].id}-${opt.value}-${this.isSelected(this.questions[this.qIndex], opt.value, this.qIndex)}`)
            }
          }
          .alignItems(HorizontalAlign.Start)
          .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, bottom: LayoutTokens.bottomScrollReserve })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)

        Row({ space: SpaceTokens.md }) {
          YoujingButton({
            variant: YoujingButtonVariant.SECONDARY,
            label: '上一题',
            buttonWidth: 96,
            onAction: (): void => {
              this.goBack();
            }
          })
          YoujingButton({
            variant: YoujingButtonVariant.TEXT,
            label: '帮我选',
            buttonWidth: 80,
            onAction: (): void => {
              this.helpPick();
            }
          })
          Blank()
          YoujingButton({
            variant: YoujingButtonVariant.PRIMARY,
            label: this.qIndex === this.questions.length - 1 ? '生成行程' : '下一题',
            buttonWidth: 150,
            onAction: (): void => {
              this.advance();
            }
          })
        }
        .width('100%')
        .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, top: SpaceTokens.md, bottom: SpaceTokens.md })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ColorTokens.canvas)
    }
    .hideTitleBar(true)
  }
}
