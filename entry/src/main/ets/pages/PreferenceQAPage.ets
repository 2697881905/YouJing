/**
 * 屏3 偏好追问状态机（帧 b6b3126b）+ 屏3b 节奏多选数据态（帧 480d5d03，同屏非新路由）。
 * 必改表已落：option-text-group gap 2→0。
 * 兜底口径（§4.2）：每题有 defaultValues，「帮我选」一键填当前题默认并推进；
 * 全部答完（或直接推进到底）触发 SpotPick（批次 4 落地，暂进占位页）。
 */

import { APP_NAV } from '../common/constants/AppNav';
import { KEY_CURRENT_BREAKPOINT } from '../utils/breakpointCenter';
import { listLanesForBreakpoint } from '../utils/responsive';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { QuestionFlowConfig } from '../common/constants/QuestionFlowConfig';
import { FlowQuestion, QuestionOption, TravelStyle, TransitPreference, PaceOption } from '../model/PlanParams';
import { PlanDraft } from '../data/PlanDraft';
import { OptionCard } from '../components/OptionCard';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';
import { FlowSteps, FLOW_STEP_PREFERENCE_QA } from '../components/FlowSteps';

@Component
export struct PreferenceQAPage {
  /** 断点（唯一来源 utils/breakpointCenter.ets）：宽屏下列表并成多栏，不再被整屏拉宽 */
  @StorageProp(KEY_CURRENT_BREAKPOINT) bp: string = 'sm';

  private pathStack: NavPathStack = APP_NAV;
  @State private qIndex: number = 0;
  @State private singleAnswers: string[] = ['leisure', 'comfort', 'public', ''];
  @State private paceAnswers: string[] = [];
  private questions: FlowQuestion[] = QuestionFlowConfig.QUESTIONS;

  /**
   * 起答从草稿读，不从字面量读。
   * 原来是 `['leisure','comfort','public','']` 硬编码初值，`syncDraft()` 只往
   * `PlanDraft` 写、这里不读回来——用户走到屏4 想改偏好、回退一进这屏，
   * 前面四道题全回到默认档（主链复审 P1）。
   * 新行程仍从默认档起：首页进链时 `PlanDraft.fresh()` 已把实例置空。
   */
  aboutToAppear(): void {
    const d: PlanDraft = PlanDraft.get();
    const seeded: string[] = ['', '', '', ''];
    seeded[0] = d.style as string;
    seeded[1] = d.stayTier;
    seeded[2] = d.transit as string;
    this.singleAnswers = seeded;
    this.paceAnswers = d.paces.map((p: PaceOption): string => p as string);
  }

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

  private syncDraft(): void {
    const d: PlanDraft = PlanDraft.get();
    d.style = this.singleAnswers[0] as TravelStyle;
    d.stayTier = this.singleAnswers[1];
    d.transit = this.singleAnswers[2] as TransitPreference;
    d.paces = this.paceAnswers.length > 0
      ? this.paceAnswers.map((v: string): PaceOption => v as PaceOption)
      : [PaceOption.STANDARD];
  }

  private advance(): void {
    this.syncDraft();
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
    HdsNavDestination() {
      Column() {
        // 主链进度（第 2/5 步）。原来这一屏只有「第 N/4 步」，说的是**本屏四道题**，
        // 但用户读到的意思是"整条流程只有四步"——两套进度同名不同义，先各改各的名字
        Column() {
          FlowSteps({ step: FLOW_STEP_PREFERENCE_QA })
        }
        .width('100%')
        .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, top: SpaceTokens.md })

        // 契约 question-card 进度形态：6px 圆点串（active primary / 其余 surface-sunken）
        // + overline「问题 N/M」——原来是一条 4px 通栏轨道，与组件规格对不上
        Row({ space: SpaceTokens.xs }) {
          ForEach(this.questions, (q: FlowQuestion, i: number) => {
            Circle()
              .width(LayoutTokens.questionProgressDot)
              .height(LayoutTokens.questionProgressDot)
              .fill(i <= this.qIndex ? ColorTokens.primary : ColorTokens.surfaceSunken)
          }, (q: FlowQuestion): string => `qdot-${q.id}`)
          Text(`问题 ${this.qIndex + 1}/${this.questions.length}`)
            .fontSize(TypeTokens.overline.size)
            .fontWeight(600)
            .fontColor(ColorTokens.muted)
            .fontFeature("'tnum' on")
            .margin({ left: SpaceTokens.sm })
        }
        .width('100%')
        .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, top: SpaceTokens.md })

        // 官方 List：题干占一个 ListItem，每个选项一个 ListItem（不再 Scroll+Column 手排间距）
        List({ space: LayoutTokens.questionOptionGap }) {
          ListItem() {
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
                .margin({ bottom: SpaceTokens.lg })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
          }

          ForEach(this.questions[this.qIndex].options,
            (opt: QuestionOption) => {
              ListItem() {
                OptionCard({
                  label: opt.label,
                  subline: opt.desc === undefined ? '' : opt.desc,
                  selected: this.isSelected(this.questions[this.qIndex], opt.value, this.qIndex),
                  onAction: (): void => {
                    this.toggle(this.questions[this.qIndex], opt.value, this.qIndex);
                  }
                })
              }
              .width('100%')
              // key 只含稳定 id：选中态变化靠 @State 重渲染，不带进 key
            }, (opt: QuestionOption): string => `${this.questions[this.qIndex].id}-${opt.value}`)
        }
        .lanes(listLanesForBreakpoint(this.bp))
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .cachedCount(6)
        .alignListItem(ListItemAlign.Start)
        .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, bottom: LayoutTokens.bottomScrollReserve })

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
            // 末题这枚按钮做的是"去选景点"，不是"生成"（生成在屏4 之后的屏6）——
            // 底稿写「生成行程」会让用户以为点完就出行程，按实际行为改口
            label: this.qIndex === this.questions.length - 1 ? '选景点' : '下一题',
            buttonWidth: 150,
            onAction: (): void => {
              this.advance();
            }
          })
        }
        .width('100%')
        .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, top: SpaceTokens.md,
          bottom: LayoutTokens.floatingDockClearance })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ColorTokens.canvas)
    }
    .titleBar(HdsChrome.bar({ mainTitle: '偏好追问', subTitle: `问题 ${this.qIndex + 1}/${this.questions.length}` }))
    .titleMode(HdsNavDestinationTitleMode.MINI)
  }
}
