/**
 * 屏3 偏好追问状态机（帧 b6b3126b）+ 屏3b 节奏多选数据态（帧 480d5d03，同屏非新路由）。
 * 必改表已落：option-text-group gap 2→0。
 * 兜底口径（§4.2）：每题有 defaultValues，「帮我选」一键填当前题默认并推进；
 * 全部答完（或直接推进到底）触发 SpotPick（批次 4 落地，暂进占位页）。
 */

import { HOST_NAV, markDraftDirty } from '../common/constants/AppNav';
import { KEY_CURRENT_BREAKPOINT } from '../utils/breakpointCenter';
import { listLanesForBreakpoint } from '../utils/responsive';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { QuestionFlowConfig } from '../common/constants/QuestionFlowConfig';
import { FlowQuestion, QuestionOption, TravelStyle, TransitPreference, PaceOption, SelectedSpot, SpotPriority } from '../model/PlanParams';
import { PlanDraft } from '../data/PlanDraft';
import { PlanRepository } from '../data/PlanRepository';
import { Spot } from '../model/Spot';
import { Area } from '../model/Area';
import { common } from '@kit.AbilityKit';
import { OptionCard } from '../components/OptionCard';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';
import { HdsNavDestination, HdsNavDestinationTitleMode, HideMode } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';
import { FlowSteps, FLOW_STEP_PREFERENCE_QA } from '../components/FlowSteps';
import { requestSystemBarRefresh } from '../utils/systemBar';

@Component
export struct PreferenceQAPage {
  // 深浅档代 tick：翻档时 EntryAbility 自增，@StorageProp 变化带动本页 build 重跑，
  // 把新 tick 传进 HdsChrome.bar → 标题内容换新 ComponentContent 重挂载、按当前档重解色
  // （官方 HdsTitleBar 自绘内容不随配置切换重渲染，真机实证见 HdsChrome.themeTick）
  @StorageProp('chromeThemeTick') chromeThemeTick: number = 0;

  /** 断点（唯一来源 utils/breakpointCenter.ets）：宽屏下列表并成多栏，不再被整屏拉宽 */
  @StorageProp(KEY_CURRENT_BREAKPOINT) bp: string = 'sm';

  // 二级页全屏化（2026-11-11）：本页固定落宿主栈，push SpotPick 同栈
  private pathStack: NavPathStack = HOST_NAV;
  @State private qIndex: number = 0;
  @State private singleAnswers: string[] = ['leisure', 'comfort', 'public', ''];
  @State private paceAnswers: string[] = [];
  private questions: FlowQuestion[] = QuestionFlowConfig.QUESTIONS;
  /** 顶栏磨砂两态：由**绝对**滚动偏移驱动（每帧增量会被松手回弹的负帧打灭，契约 §Translucency） */
  @State private barScrolled: boolean = false;
  private barScroller: Scroller = new Scroller();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

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
    markDraftDirty(true);
    const d: PlanDraft = PlanDraft.get();
    d.style = this.singleAnswers[0] as TravelStyle;
    d.stayTier = this.singleAnswers[1];
    d.transit = this.singleAnswers[2] as TransitPreference;
    d.paces = this.paceAnswers.length > 0
      ? this.paceAnswers.map((v: string): PaceOption => v as PaceOption)
      : [PaceOption.STANDARD];
    PlanDraft.persist();
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

  /**
   * 草案先行逃生口（Phase4-B）：不想逐题挑景点/住宿时，一键按当前偏好直接生成。
   * 自动选前 8 热门景点（前 3 必去）+ 首个住宿区，跳过 SpotPick/StayPick 直达生成。
   * 表单/追问主次不变——这只是给「先看见草案再调」一条快路。
   */
  private async generateDirect(): Promise<void> {
    this.syncDraft();
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const d: PlanDraft = PlanDraft.get();
    const city: string = d.basic.destination;
    try {
      if (d.selectedSpots.length === 0) {
        const spots: Spot[] = await PlanRepository.loadSpots(ctx, city);
        d.selectedSpots = spots.slice(0, 8).map((s: Spot, i: number): SelectedSpot => {
          const sel: SelectedSpot = { spotId: s.id, priority: i < 3 ? SpotPriority.MUST : SpotPriority.WANT };
          return sel;
        });
      }
      if (d.selectedArea.areaId.length === 0) {
        const areas: Area[] = await PlanRepository.loadAreas(ctx, city);
        if (areas.length > 0) {
          d.selectedArea = { areaId: areas[0].id };
        }
      }
    } catch (err) {
      // 自动选点/区失败也推进：Generating 会给出失败页与重试/降级出口，不静默卡死
    }
    PlanDraft.flush();
    this.pathStack.pushPath({ name: 'Generating' });
  }

  /** 绝对滚动偏移 → 顶栏磨砂开关（>0 即开，静止归零） */
  private syncBarScroll(): void {
    const y: number = this.barScroller.currentOffset().yOffset;
    const on: boolean = y > 0;
    if (on !== this.barScrolled) {
      this.barScrolled = on;
      if (!on) {
        // 偏移回到 0：HDS 在这一帧回写系统栏内容色，补设通道连发四发压住它（utils/systemBar.ets）
        requestSystemBarRefresh();
      }
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
        .padding({ left: SpaceTokens.base, right: SpaceTokens.base, top: SpaceTokens.sm })

        // 契约 question-card 进度形态：6px 圆点串（active primary / 其余 surface-sunken）
        // + overline「问题 N/M」——原来是一条 4px 通栏轨道，与组件规格对不上
        Row({ space: SpaceTokens.xxs }) {
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
            .margin({ left: SpaceTokens.xs })
        }
        .width('100%')
        .padding({ left: SpaceTokens.base, right: SpaceTokens.base, top: SpaceTokens.sm })

        // 官方 List：题干占一个 ListItem，每个选项一个 ListItem（不再 Scroll+Column 手排间距）
        List({ space: LayoutTokens.questionOptionGap, scroller: this.barScroller }) {
          ListItem() {
            Column() {
              Text(this.questions[this.qIndex].title)
                .fontSize(TypeTokens.title.size)
                .fontWeight(700)
                .fontFamily(TypeTokens.title.family)
                .fontColor(ColorTokens.ink)
                .margin({ top: SpaceTokens.lg, bottom: SpaceTokens.xxs })
              Text(this.questions[this.qIndex].helper === undefined ? '' : this.questions[this.qIndex].helper as string)
                .fontSize(TypeTokens.small.size)
                .fontColor(ColorTokens.body)
                .margin({ bottom: SpaceTokens.base })
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
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .cachedCount(6)
        .alignListItem(ListItemAlign.Start)
        .padding({ left: SpaceTokens.base, right: SpaceTokens.base })
        // 顶部让位已在外层 Column 承担（固定头不让位会叠标题），List 起点不再重复让位
        .contentStartOffset(0)
        .onDidScroll((): void => {
          this.syncBarScroll();
        })

        Row({ space: SpaceTokens.sm }) {
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
            buttonWidth: 120,  // 150 装 3 个汉字本来就富余，钉底条里 返回+帮我选+Blank+这颗 在 363.5vp 手机上
                                            // 合计超过内容宽 → Blank 塌成 0、这颗被顶出屏幕右缘 15.5vp（真机实测）,
            onAction: (): void => {
              this.advance();
            }
          })
        }
        .width('100%')
        // 底部动作条原来让出 dock 净空 112；2026-11-11 二级页全屏化后 dock 作废，
        // 按契约「CTA 距底 ≥16」留一档呼吸
        .padding({ left: SpaceTokens.base, right: SpaceTokens.base, top: SpaceTokens.sm,
          bottom: SpaceTokens.base })
      }
      .width('100%')
      .height('100%')
      // 顶部让位放外层：FlowSteps 与「问题 N/M」是 List 之外的固定头，
      // 不让位会顶到标题栏下与主标题叠字；List 不再重复让位（否则头下多空一条缝）
      .padding({ top: HdsChrome.contentTopInset(this.statusBarHeight) })
    }
    // 不收栏（2026-11-08）：NavDestination 内容区恒预留 56vp 栏位、收栏后不回收，收起只留一条 175px 白带
    .bindToScrollable([this.barScroller])
    .clip(false)
    // HDS 深色档这层默认纯黑，透明栏会把它露成一条比画布暗一档的带（成因与实测见 Docs/INIT_REPORT.md §5ci 续 80）
    .backgroundColor(ColorTokens.canvas)
    // 向导其余四屏的标题栏都只写主标题，步序交给页内；这里原来还把
    // 「问题 N/M」同时写进副标题和页内翻页器，同一句话在 200vp 内出现两遍
    .titleBar(HdsChrome.bar({ themeTick: this.chromeThemeTick, mainTitle: '偏好追问', scrolled: this.barScrolled,
      menu: [HdsChrome.item($r('sys.symbol.wand_and_stars'), '直接生成', (): void => {
        this.generateDirect();
      })] }))
    .titleMode(HdsNavDestinationTitleMode.MINI)
  }
}
