/**
 * 屏2 行程基础输入（帧 7d2eafa8）。
 * 必改表已落：budget-container gap 10→8；budget-track-wrapper gap 6→4；field-col gap 2→0。
 * 目的地/日期选择器与预算滑杆交互在批次 4 接入，本批为静态展示态 + 可选人数。
 */

import { APP_NAV, markDraftDirty } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { MoneyText } from '../utils/MoneyText';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';
import { PlanDraft } from '../data/PlanDraft';
import { PlanRepository } from '../data/PlanRepository';
import { PaceOption, SelectedSpot, TransitPreference, TravelStyle, TripBasicInput } from '../model/PlanParams';
import { Spot } from '../model/Spot';
import { Area } from '../model/Area';
import { DateUtils } from '../utils/DateUtils';
import { TripIntent, TripIntentParser } from '../utils/TripIntentParser';
import { PlanAutoPick, tagLabel, tierLabel } from '../utils/PlanAutoPick';
import { Logger } from '../common/logger/Logger';
import { common } from '@kit.AbilityKit';
import { BudgetConfig } from '../common/constants/BudgetConfig';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';
import { getSheetImmersiveMaterial } from '../utils/immersiveMaterial';
import { FlowSteps, FLOW_STEP_TRIP_INPUT } from '../components/FlowSteps';
import { KEY_CURRENT_BREAKPOINT } from '../utils/breakpointCenter';
import { longFormMaxWidth } from '../utils/responsive';
import { SUPPORTED_CITIES, POPULAR_MAP_CITIES, isMapCity } from '../common/constants/Cities';

// 京都为 mock 演示城（底稿帧同源），标注「示例数据」不谎报是正式内置库；
// 正式种子城从 Cities 单点取（DataSeeder 与一句话解析读同一份）
const CITIES: string[] = SUPPORTED_CITIES.concat(['京都（示例数据）']);

/** 示例句：五类字段全命中，用户改几个词就能得到自己的句子 */
const SAMPLE_SENTENCE: string = '下周五去上海玩三天，两个人，喜欢历史和美食，预算一万';

@Component
export struct TripInputPage {
  private pathStack: NavPathStack = APP_NAV;
  /** 断点（唯一来源 utils/breakpointCenter.ets） */
  @StorageProp(KEY_CURRENT_BREAKPOINT) bp: string = 'sm';
  @State private party: number = 2;
  @State private city: string = '北京';
  @State private startDate: string = '';
  @State private endDate: string = '';
  @State private showCity: boolean = false;
  /** 城市面板里的“其他城市”：未内置城市走 Map Kit，不写死城市列表 */
  @State private otherCity: string = '';
  @State private budget: number = BudgetConfig.DEFAULT;
  // 一句话成行程：原句只在内存里，识别结果先落表单与草稿，再由用户决定生成或去调整
  @State private sentence: string = '';
  @State private recognizing: boolean = false;
  @State private intentError: string = '';
  @State private previewOpen: boolean = false;
  @State private pvCity: string = '';
  @State private pvWhen: string = '';
  @State private pvPeople: string = '';
  @State private pvBudget: string = '';
  @State private pvPref: string = '';
  @State private pvPick: string = '';
  @State private pvNotes: string = '';
  @State private pvCanGenerate: boolean = false;
  /** 数据读取期间用户可能按返回；await 回来后不再写已销毁页面的状态 */
  private alive: boolean = true;
  private basePartyOptions: number[] = [1, 2, 4];

  /** 屏2 是草稿的展示方：外部拉起（小艺/深链）预填与返回本屏都要回显真值 */
  aboutToAppear(): void {
    this.alive = true;
    this.recognizing = false;
    // 默认日期按今天起算：写死的 2026-07-01 早已在过去，picker 也不该允许选过去
    const today: string = DateUtils.todayIso();
    this.startDate = today;
    this.endDate = DateUtils.addDays(today, 2);
    const b: TripBasicInput = PlanDraft.get().basic;
    // 预填城市不在支持列表也如实回显（屏4 空态会说明暂不支持），
    // 不静默改成北京——那会让「小艺说已记下杭州、界面显示北京」对不上
    if (b.destination.length > 0) {
      this.city = b.destination;
    }
    // 草稿里的日期若已经过去就丢弃，按今天起算：
    // 老版本的 PlanDraft 默认值写死过 2026-07-01，装在机上的旧草稿会带着它进来
    if (DateUtils.isValidIsoDate(b.startDate) && b.startDate >= today) {
      this.startDate = b.startDate;
    }
    if (DateUtils.isValidIsoDate(b.endDate) && b.endDate >= this.startDate
      && DateUtils.spanDays(this.startDate, b.endDate) >= 1) {
      this.endDate = b.endDate;
    }
    if (b.people > 0) {
      this.party = b.people;
    }
    if (b.budget >= BudgetConfig.MIN && b.budget <= BudgetConfig.MAX) {
      this.budget = b.budget;
    }
  }

  aboutToDisappear(): void {
    this.alive = false;
  }

  /** 快捷档位固定 1/2/4；小艺带来 3 或 5 等人数时把它补进选项，避免数字对但 chip 不高亮 */
  private partyOptions(): number[] {
    if (this.basePartyOptions.indexOf(this.party) < 0) {
      const options: number[] = this.basePartyOptions.slice();
      options.push(this.party);
      options.sort((a: number, b: number): number => a - b);
      return options;
    }
    return this.basePartyOptions;
  }

  private fmt(dateStr: string): string {
    const parts: string[] = dateStr.split('-');
    return `${Number(parts[1])}月${Number(parts[2])}日`;
  }

  private dayCount(): number {
    return DateUtils.spanDays(this.startDate, this.endDate);
  }

  private static toIso(value: Date): string {
    const y: number = value.getFullYear();
    const m: string = `${value.getMonth() + 1}`.padStart(2, '0');
    const d: string = `${value.getDate()}`.padStart(2, '0');
    return `${y}-${m}-${d}`;
  }

  /**
   * 一次点按走完「出发 → 返程」两档官方日期弹窗。
   * 原来返程藏在同一行的长按手势里：底稿这格只有一个「选择出行日期」入口，
   * 长按既不在帧上也没有任何提示，用户改不了返程。
   * picker 起点是今天：不让用户把出发日选进过去。
   */
  private pickDate(): void {
    const lastDay: Date = new Date('2027-12-31');
    const today: Date = new Date(DateUtils.todayIso());
    this.getUIContext().showDatePickerDialog({
      start: today,
      end: lastDay,
      selected: new Date(this.startDate),
      onDateAccept: (value: Date): void => {
        const startIso: string = TripInputPage.toIso(value);
        this.startDate = startIso;
        let endSelected: string = this.endDate;
        if (Date.parse(endSelected) < Date.parse(startIso)) {
          endSelected = startIso;
        }
        this.endDate = endSelected;
        this.getUIContext().showDatePickerDialog({
          start: new Date(startIso),
          end: lastDay,
          selected: new Date(endSelected),
          onDateAccept: (v2: Date): void => {
            this.endDate = TripInputPage.toIso(v2);
          }
        });
      }
    });
  }

  private static styleOf(code: string, fallback: TravelStyle): TravelStyle {
    if (code === 'leisure') {
      return TravelStyle.LEISURE;
    }
    if (code === 'fast_pace') {
      return TravelStyle.FAST_PACE;
    }
    if (code === 'family') {
      return TravelStyle.FAMILY;
    }
    if (code === 'foodie') {
      return TravelStyle.FOODIE;
    }
    if (code === 'culture') {
      return TravelStyle.CULTURE;
    }
    return fallback;
  }

  private static transitOf(code: string, fallback: TransitPreference): TransitPreference {
    if (code === 'public') {
      return TransitPreference.PUBLIC;
    }
    if (code === 'taxi_main') {
      return TransitPreference.TAXI_MAIN;
    }
    if (code === 'charter') {
      return TransitPreference.CHARTER;
    }
    return fallback;
  }

  private static pacesOf(code: string, fallback: PaceOption[]): PaceOption[] {
    if (code === 'relaxed') {
      return [PaceOption.RELAXED];
    }
    if (code === 'standard') {
      return [PaceOption.STANDARD];
    }
    if (code === 'packed') {
      return [PaceOption.PACKED];
    }
    return fallback;
  }

  /** 草稿里的多选节奏折成一个码：与 LlmClient 的天段顺序一致，取第一段档位 */
  private static paceCodeOf(paces: PaceOption[]): string {
    if (paces.length === 0) {
      return 'standard';
    }
    if (paces.indexOf(PaceOption.RELAXED) >= 0) {
      return 'relaxed';
    }
    if (paces.indexOf(PaceOption.STANDARD) >= 0) {
      return 'standard';
    }
    return 'packed';
  }

  private styleLabel(style: TravelStyle): string {
    if (style === TravelStyle.FAST_PACE) {
      return '暴走';
    }
    if (style === TravelStyle.FAMILY) {
      return '亲子';
    }
    if (style === TravelStyle.FOODIE) {
      return '美食';
    }
    if (style === TravelStyle.CULTURE) {
      return '文化';
    }
    return '休闲';
  }

  private transitLabel(t: TransitPreference): string {
    if (t === TransitPreference.TAXI_MAIN) {
      return '打车为主';
    }
    if (t === TransitPreference.CHARTER) {
      return '包车';
    }
    return '公共交通';
  }

  private paceLabel(code: string): string {
    if (code === 'relaxed') {
      return '每天 3 站';
    }
    if (code === 'packed') {
      return '每天 6 站';
    }
    return '每天 4 站';
  }

  /**
   * 一句话成行程：本地解析（零联网、零 LLM），把能对上的字段写进表单与草稿，
   * 对不上的保持原值并在预览里逐条说明。原句不落盘、不发送。
   */
  private async recognize(): Promise<void> {
    if (this.recognizing) {
      return;
    }
    const text: string = this.sentence.trim();
    if (text.length === 0) {
      this.intentError = '先写一句，比如「下周五去上海玩三天，两个人」';
      return;
    }
    this.intentError = '';
    this.recognizing = true;
    // 键盘不收的话半模态会被输入法顶起，底部主键可能落到可见区之外
    this.getUIContext().getFocusController().clearFocus();
    const today: string = DateUtils.todayIso();
    const intent: TripIntent = TripIntentParser.parse(text, today);
    // 未内置城市不再一票否决：走 Map Kit 取数（Stage 2）；取不到再给失败出口
    let targetCity: string = intent.city;
    let viaMap: boolean = false;
    if (intent.unsupportedCity.length > 0) {
      if (!isMapCity(intent.unsupportedCity)) {
        this.recognizing = false;
        this.intentError =
          `「${intent.unsupportedCity}」还没有内置数据，目前支持 ${SUPPORTED_CITIES.join('/')}`;
        return;
      }
      targetCity = intent.unsupportedCity;
      viaMap = true;
    }
    if (targetCity.length === 0) {
      this.recognizing = false;
      this.intentError = '没认出目的地。可以写「去上海玩三天」，或直接用下面的字段选择';
      return;
    }
    const draft: PlanDraft = PlanDraft.get();
    const start: string = intent.startDate.length > 0 ? intent.startDate : today;
    const days: number = intent.dayCount > 0 ? intent.dayCount : 3;
    const end: string = DateUtils.addDays(start, days - 1);
    const people: number = intent.people > 0 ? intent.people : this.party;
    const budget: number = intent.budgetAmount > 0
      ? TripIntentParser.budgetPerPerson(intent.budgetAmount, intent.budgetIsPerPerson, people)
      : this.budget;
    const stayTier: string = intent.stayTier.length > 0 ? intent.stayTier : draft.stayTier;
    const pace: string = intent.pace.length > 0 ? intent.pace : TripInputPage.paceCodeOf(draft.paces);
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const spots: Spot[] = await PlanRepository.loadSpots(ctx, targetCity);
      const areas: Area[] = await PlanRepository.loadAreas(ctx, targetCity);
      if (!this.alive) {
        return;
      }
      if (spots.length === 0 || areas.length === 0) {
        this.recognizing = false;
        this.intentError = viaMap
          ? `地图服务没有返回「${targetCity}」的景点或住宿区，检查网络后重试`
          : `「${targetCity}」的数据还不完整，换座城市或用下面的字段选择`;
        return;
      }
      let picked: SelectedSpot[] = PlanAutoPick.pickSpots(spots, days, pace, intent.tags);
      let area: Area | null = PlanAutoPick.pickArea(areas, spots, picked, stayTier);
      if (days === 1) {
        // 单日名额要扣掉往返通勤：先用候选定住宿区，再按 10h 窗口收口并复核区域
        const before: Spot[] = PlanAutoPick.singleDayCandidates(spots, pace, intent.tags);
        const originArea: Area | null = area;
        picked = PlanAutoPick.pickSpotsForSingleDay(spots, pace, intent.tags, area);
        area = PlanAutoPick.pickArea(areas, spots, picked, stayTier);
        const keptIds: string[] = picked.map((s: SelectedSpot): string => s.spotId);
        const keptSpots: Spot[] = [];
        const dropped: string[] = [];
        for (const c of before) {
          if (keptIds.indexOf(c.id) >= 0) {
            keptSpots.push(c);
          } else {
            dropped.push(c.name);
          }
        }
        // 收口轨迹：重庆 1 天实测只剩 1 站，没有这行就判不出是「首站太远吃掉预算」还是「候选本来就少」
        Logger.info('Ui.TripInput', `单日收口 候选${before.length}→${keptSpots.length} ` +
          `留${keptSpots.map((s: Spot): string => s.name).join('/')} ` +
          `弃${dropped.join('/') || '无'} 停留+通勤` +
          `${PlanAutoPick.routeMinutesOf(keptSpots, originArea)}min/` +
          `预算${PlanAutoPick.SINGLE_DAY_SIGHT_BUDGET_MIN}min 起点${originArea !== null ? originArea.name : '无'}`);
      }
      intent.city = targetCity;
      if (viaMap) {
        intent.notes.push(`${targetCity}未内置，景点与住宿区来自地图服务；开放时间与预约以官方为准`);
      }
      this.applyIntent(intent, start, end, days, people, budget, stayTier, pace, picked, area);
      this.recognizing = false;
      Logger.info('Ui.TripInput',
        `一句话识别 ${targetCity} ${days}天 people=${people} spots=${picked.length} ` +
        `area=${area !== null ? area.id : 'none'} viaMap=${viaMap}`);
      // bindSheet 的内容不随父状态重赋值重绘：预览字段必须在开面板之前写好
      this.previewOpen = true;
    } catch (err) {
      if (!this.alive) {
        return;
      }
      this.recognizing = false;
      Logger.error('Ui.TripInput', `一句话识别失败: ${(err as Error).message}`);
      this.intentError = viaMap
        ? `地图服务没取到「${targetCity}」的数据，检查网络后重试`
        : '读城市数据时出错了，请稍后再试';
    }
  }

  private applyIntent(intent: TripIntent, start: string, end: string, days: number,
    people: number, budget: number, stayTier: string, pace: string,
    picked: SelectedSpot[], area: Area | null): void {
    const d: PlanDraft = PlanDraft.get();
    this.city = intent.city;
    this.startDate = start;
    this.endDate = end;
    this.party = people;
    this.budget = budget;
    const basic: TripBasicInput = {
      destination: intent.city, startDate: start, endDate: end, people: people, budget: budget
    };
    d.basic = basic;
    d.style = TripInputPage.styleOf(intent.style, d.style);
    d.stayTier = stayTier;
    d.transit = TripInputPage.transitOf(intent.transit, d.transit);
    d.paces = TripInputPage.pacesOf(intent.pace, d.paces);
    d.selectedSpots = picked;
    d.selectedArea = { areaId: area !== null ? area.id : '' };
    markDraftDirty(true);
    const notes: string[] = [];
    if (intent.startDate.length === 0) {
      notes.push('没写日期，从今天出发');
    }
    if (intent.dayCount === 0) {
      notes.push('没写玩几天，按 3 天');
    }
    if (intent.people === 0) {
      notes.push(`没写人数，按当前 ${people} 人`);
    }
    if (intent.budgetAmount === 0) {
      notes.push(`没写预算，保留 ${MoneyText.yuan(budget)}/人`);
    } else if (!intent.budgetIsPerPerson) {
      notes.push(`按总预算 ÷ ${people} 人 折算人均`);
    }
    for (const n of intent.notes) {
      notes.push(n);
    }
    if (area === null) {
      notes.push('片区库为空，直接生成会缺住宿区');
    }
    this.pvCity = intent.city;
    this.pvWhen = `${this.fmt(start)} – ${this.fmt(end)} · ${days}天${days - 1}晚`;
    this.pvPeople = `${people} 人`;
    this.pvBudget = `${MoneyText.yuan(budget)} / 人`;
    this.pvPref = `${this.styleLabel(d.style)} · ${tierLabel(stayTier)} · ` +
      `${this.transitLabel(d.transit)} · ${this.paceLabel(pace)}`;
    this.pvPick = PlanAutoPick.describe(picked, area, days, pace);
    if (intent.tags.length > 0) {
      // 标签只影响选点顺序，不写进偏好行的话用户看不出「历史」被采纳了
      const names: string[] = [];
      for (const t of intent.tags) {
        names.push(tagLabel(t));
      }
      this.pvPick = `${this.pvPick}，${names.join('/')}优先`;
    }
    this.pvNotes = notes.join('\n');
    this.pvCanGenerate = area !== null && picked.length > 0;
  }

  @Builder
  fieldLabel(label: string) {
    Text(label)
      .fontSize(TypeTokens.overline.size)
      .fontWeight(600)
      .fontColor(ColorTokens.muted)
  }

  @Builder
  chevron() {
    // DESIGN §8：整行可点的 chevron 是控制件，取 muted（5.46:1）；
    // faint 只许装饰/禁用，是家族要纠正的旧习惯
    SymbolGlyph($r('sys.symbol.chevron_right'))
      .fontSize(IconSizes.control)
      .fontColor([ColorTokens.muted])
  }

  @Builder
  partyChip(count: number) {
    // 选中态按契约 tint 配方（DESIGN §9）：primary-tint 底 + 1px primary 描边 + ink 字。
    // 不用官方 EMPHASIZED 实心蓝——那会与底部主按钮形成同屏双实心蓝（禁令 1），
    // 且选中文案压实底靠的是官方换色，不如契约配方可预期
    Button(count.toString())
      .width(LayoutTokens.minTouchTarget)
      .height(LayoutTokens.minTouchTarget)
      .fontSize(TypeTokens.small.size)
      .fontWeight(this.party === count ? 600 : 450)
      .fontColor(this.party === count ? ColorTokens.ink : ColorTokens.body)
      .type(ButtonType.Circle)
      .buttonStyle(ButtonStyleMode.NORMAL)
      .backgroundColor(this.party === count ? ColorTokens.primaryTint : ColorTokens.surfaceElevated)
      .border({
        width: this.party === count ? LayoutTokens.glassBorderWidth : 0,
        color: ColorTokens.primary
      })
      .accessibilityText(`${count}人`)
      .onClick(() => {
        this.party = count;
      })
  }

  /** 城市面板的“其他城市”：不再限制在 5 个内置城市里，数据由 Map Kit 兜底 */
  private useOtherCity(): void {
    const name: string = this.otherCity.trim();
    if (name.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '先输入城市名' });
      return;
    }
    this.city = name;
    this.otherCity = '';
    this.showCity = false;
  }

  @Builder
  citySheet() {
    Column({ space: SpaceTokens.sm }) {
      Text('其他城市')
        .fontSize(TypeTokens.overline.size)
        .fontWeight(600)
        .fontColor(ColorTokens.muted)
        .width('100%')
        .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })
      // 主操作固定在滚动区外：键盘压缩窗口时百分比高的 Scroll 可能不进可滚状态，
      // 放在里面的「使用」会点不到（tools/audit_scroll_actions.py 的同类缺陷）
      Row({ space: SpaceTokens.sm }) {
        TextInput({ text: this.otherCity, placeholder: '输入城市名，如西安' })
          .height(LayoutTokens.minTouchTarget)
          .fontSize(TypeTokens.small.size)
          .onChange((v: string): void => {
            this.otherCity = v;
          })
          .layoutWeight(1)
          .accessibilityText('输入其他城市')
        YoujingButton({
          variant: YoujingButtonVariant.SECONDARY,
          label: '使用',
          buttonWidth: 72,
          onAction: (): void => {
            this.useOtherCity();
          }
        })
      }
      .width('100%')
      // 往下让出系统半模态关闭 ✕ 的高度，否则「使用」按钮会被 ✕ 压住/切掉右缘
      .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, top: SpaceTokens.xl })
      Text('未内置城市会用地图服务检索；开放时间与预约以官方为准')
        .fontSize(TypeTokens.caption.size)
        .fontWeight(450)
        .fontColor(ColorTokens.muted)
        .width('100%')
        .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })

      Scroll() {
        Column() {
          Text('热门城市（地图服务）')
            .fontSize(TypeTokens.overline.size)
            .fontWeight(600)
            .fontColor(ColorTokens.muted)
            .width('100%')
            .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, top: SpaceTokens.sm,
              bottom: SpaceTokens.xs })
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(POPULAR_MAP_CITIES, (c: string) => {
              Button(c)
                .fontSize(TypeTokens.small.size)
                .fontWeight(this.city === c ? 600 : 450)
                .fontColor(this.city === c ? ColorTokens.ink : ColorTokens.body)
                .height(LayoutTokens.minTouchTarget)
                .padding({ left: SpaceTokens.md, right: SpaceTokens.md })
                .type(ButtonType.Capsule)
                .buttonStyle(ButtonStyleMode.NORMAL)
                .backgroundColor(this.city === c ? ColorTokens.primaryTint : ColorTokens.surfaceElevated)
                .border({
                  width: this.city === c ? LayoutTokens.glassBorderWidth : 0,
                  color: ColorTokens.primary
                })
                .margin({ right: SpaceTokens.sm, bottom: SpaceTokens.sm })
                .accessibilityText(`选择热门城市 ${c}`)
                .onClick((): void => {
                  this.city = c;
                  this.showCity = false;
                })
            }, (c: string): string => `hot-city-${c}`)
          }
          .width('100%')
          .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })

          Text('内置数据城市')
            .fontSize(TypeTokens.overline.size)
            .fontWeight(600)
            .fontColor(ColorTokens.muted)
            .width('100%')
            .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, top: SpaceTokens.sm,
              bottom: SpaceTokens.xs })

          ForEach(CITIES, (c: string) => {
            // 官方 Button 承载整行：原来是裸 Row + onClick，读屏进不去也没有按压态。
            // 外观仍由内层 Row 承载，Button 只做可点/可聚焦的壳。
            Button({ type: ButtonType.Normal, stateEffect: true }) {
              Row() {
                Text(c)
                  .fontSize(TypeTokens.body.size)
                  .fontWeight(c === this.city ? 600 : 400)
                  .fontColor(c === this.city ? ColorTokens.primary : ColorTokens.ink)
                  .layoutWeight(1)
                if (c === this.city) {
                  SymbolGlyph($r('sys.symbol.checkmark'))
                    .fontSize(IconSizes.control)
                    .fontColor([ColorTokens.primary])
                }
              }
              .width('100%')
              .height(LayoutTokens.minTouchTarget)
              .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })
            }
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .width('100%')
            .padding(0)
            .accessibilityText(c === this.city ? `选择目的地 ${c}，当前已选` : `选择目的地 ${c}`)
            .onClick(() => {
              this.city = c;
              this.showCity = false;
            })
          }, (c: string): string => `city-${c}`)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .padding({ top: SpaceTokens.md, bottom: SpaceTokens.md })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(ColorTokens.canvas)
  }

  @Builder
  intentRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(TypeTokens.caption.size)
        .fontWeight(450)
        .fontColor(ColorTokens.muted)
        .width(64)
      Text(value)
        .fontSize(TypeTokens.small.size)
        .fontWeight(500)
        .fontColor(ColorTokens.ink)
        .fontFeature("'tnum' on")
        .textAlign(TextAlign.End)
        .layoutWeight(1)
    }
    .width('100%')
    .constraintSize({ minHeight: LayoutTokens.minTouchTarget })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  intentSheet() {
    Column() {
      Column({ space: SpaceTokens.xs }) {
        Text('识别结果')
          .fontSize(TypeTokens.headline.size)
          .fontWeight(700)
          .fontColor(ColorTokens.ink)
        Text('只改句子提到的字段，其余沿用当前设置')
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ top: SpaceTokens.md, bottom: SpaceTokens.sm })

      Scroll() {
        Column({ space: SpaceTokens.xs }) {
          this.intentRow('目的地', this.pvCity)
          this.intentRow('日期', this.pvWhen)
          this.intentRow('人数', this.pvPeople)
          this.intentRow('预算', this.pvBudget)
          this.intentRow('偏好', this.pvPref)
          this.intentRow('预选', this.pvPick)
          if (this.pvNotes.length > 0) {
            Text(this.pvNotes)
              .fontSize(TypeTokens.caption.size)
              .fontWeight(450)
              .fontColor(ColorTokens.muted)
              .lineHeight(TypeTokens.caption.size * 1.5)
              .width('100%')
              .margin({ top: SpaceTokens.sm })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)

      Column({ space: SpaceTokens.sm }) {
        YoujingButton({
          variant: YoujingButtonVariant.PRIMARY,
          label: '直接生成行程',
          fullWidth: true,
          disabled: !this.pvCanGenerate,
          onAction: (): void => {
            this.previewOpen = false;
            this.pathStack.pushPath({ name: 'Generating' });
          }
        })
        YoujingButton({
          variant: YoujingButtonVariant.TEXT,
          label: '去调整',
          fullWidth: true,
          onAction: (): void => {
            this.previewOpen = false;
          }
        })
      }
      .width('100%')
      .padding({ top: SpaceTokens.md })
    }
    .width('100%')
    .height('100%')
    .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, bottom: SpaceTokens.lg })
    .backgroundColor(ColorTokens.canvas)
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    HdsNavDestination() {
      Column() {
        Scroll() {
          Column() {
            // §5.7 的重复只发生在第二行：帧声明的衬线大标题是「开启一次有迹可循的旅程」，
            // 而它下面那句「设定出行基础参数，AI 将基于…」与顶栏副标题一字不差，
            // 所以删掉重复的那一行、保留帧的衬线槽，再用步骤进度占住腾出的高度
            Column({ space: SpaceTokens.sm }) {
              Text('开启一次有迹可循的旅程')
                .fontSize(TypeTokens.title.size)
                .fontWeight(700)
                .fontFamily(TypeTokens.title.family)
                .fontColor(ColorTokens.ink)
              FlowSteps({ step: FLOW_STEP_TRIP_INPUT })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .margin({ top: SpaceTokens.lg, bottom: SpaceTokens.lg })

            // 一句话成行程：本地解析，识别结果先给预览，再由用户决定直接生成或去逐屏调整
            Column({ space: SpaceTokens.sm }) {
              Text('一句话成行程')
                .fontSize(TypeTokens.body.size)
                .fontWeight(600)
                .fontColor(ColorTokens.ink)
              Text('说清去哪、几天、几个人。识别在本机完成；未内置城市会联网查地图服务，不花模型额度')
                .fontSize(TypeTokens.caption.size)
                .fontWeight(450)
                .fontColor(ColorTokens.muted)
              TextInput({ placeholder: '例：下周五去上海玩三天，两个人', text: this.sentence })
                .fontSize(TypeTokens.body.size)
                .fontColor(ColorTokens.ink)
                .backgroundColor(ColorTokens.surfacePanel)
                .borderRadius(RadiusTokens.reason)
                .height(LayoutTokens.composeFieldHeight)
                .enterKeyType(EnterKeyType.Done)
                .accessibilityText('一句话描述行程')
                .onChange((v: string): void => {
                  this.sentence = v;
                  if (this.intentError.length > 0) {
                    this.intentError = '';
                  }
                })
                .onSubmit((): void => {
                  this.recognize();
                })
              if (this.intentError.length > 0) {
                Text(this.intentError)
                  .fontSize(TypeTokens.caption.size)
                  .fontWeight(450)
                  .fontColor(ColorTokens.danger)
                  .width('100%')
              }
              Row({ space: SpaceTokens.sm }) {
                // 实心主按钮留给底部「开始规划」，这里用次按钮，避免同屏双实心蓝
                YoujingButton({
                  variant: YoujingButtonVariant.SECONDARY,
                  label: this.recognizing ? '识别中…' : '识别',
                  buttonWidth: 120,
                  disabled: this.recognizing,
                  onAction: (): void => {
                    this.recognize();
                  }
                })
                YoujingButton({
                  variant: YoujingButtonVariant.TEXT,
                  label: '填入示例',
                  buttonWidth: 120,
                  onAction: (): void => {
                    this.sentence = SAMPLE_SENTENCE;
                    this.intentError = '';
                  }
                })
              }
              .width('100%')
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding(SpaceTokens.md)
            .borderRadius(RadiusTokens.card)
            .backgroundColor(ColorTokens.surfaceSubtle)
            .margin({ bottom: SpaceTokens.lg })

            Column({ space: SpaceTokens.md }) {
              // 目的地
              Button({ type: ButtonType.Normal, stateEffect: true }) {
                Row() {
                  Column() {
                    this.fieldLabel('目的地')
                    Text(this.city)
                      .fontSize(TypeTokens.headline.size)
                      .fontWeight(600)
                      .fontColor(ColorTokens.ink)
                      .margin({ top: SpaceTokens.xs })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  this.chevron()
                }
                .width('100%')
                .padding(SpaceTokens.md)
                .borderRadius(RadiusTokens.card)
                .backgroundColor(ColorTokens.surfaceSubtle)
              }
              .buttonStyle(ButtonStyleMode.TEXTUAL)
              .width('100%')
              .padding(0)
              .borderRadius(RadiusTokens.card)
              // 帧 7d2eafa8 这格声明的是 aria-label="选择目的地"，读屏要连当前值一起念
              .accessibilityText(`选择目的地，当前 ${this.city}`)
              .onClick(() => {
                this.showCity = true;
              })

              // 出行日期
              Button({ type: ButtonType.Normal, stateEffect: true }) {
                Row() {
                  Column() {
                    this.fieldLabel('出行日期')
                    Text(`${this.fmt(this.startDate)} – ${this.fmt(this.endDate)}`)
                      .fontSize(TypeTokens.headline.size)
                      .fontWeight(600)
                      .fontColor(ColorTokens.ink)
                      .fontFeature("'tnum' on")
                      .margin({ top: SpaceTokens.xs })
                    Text(`${this.dayCount()}天${this.dayCount() - 1}晚`)
                      .fontSize(TypeTokens.caption.size)
                      .fontWeight(450)
                      .fontColor(ColorTokens.muted)
                      .fontFeature("'tnum' on")
                      .margin({ top: SpaceTokens.xs })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  this.chevron()
                }
                .width('100%')
                .padding(SpaceTokens.md)
                .borderRadius(RadiusTokens.card)
                .backgroundColor(ColorTokens.surfaceSubtle)
              }
              .buttonStyle(ButtonStyleMode.TEXTUAL)
              .width('100%')
              .padding(0)
              .borderRadius(RadiusTokens.card)
              // 帧声明 aria-label="选择出行日期"；一次点按串两档弹窗（出发→返程）
              .accessibilityText(`选择出行日期，当前 ${this.dayCount()}天${this.dayCount() - 1}晚`)
              .onClick(() => {
                this.pickDate();
              })

              // 同行人数
              Row() {
                Column() {
                  this.fieldLabel('同行人数')
                  Text(`${this.party} 位成人`)
                    .fontSize(TypeTokens.headline.size)
                    .fontWeight(600)
                    .fontColor(ColorTokens.ink)
                    .fontFeature("'tnum' on")
                    .margin({ top: SpaceTokens.xs })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Row({ space: SpaceTokens.xs }) {
                  ForEach(this.partyOptions(), (count: number) => {
                    this.partyChip(count)
                  }, (count: number): string => `party-${count}`)
                }
              }
              .width('100%')
              .padding(SpaceTokens.md)
              .borderRadius(RadiusTokens.card)
              .backgroundColor(ColorTokens.surfaceSubtle)

              // 预算档位
              Column({ space: SpaceTokens.sm }) {
                Row() {
                  Column() {
                  this.fieldLabel('预算档位')
                  // DESIGN §4 数字格式：summary 一律「整数 + 单位」，不用千分位
                  Text(`${MoneyText.yuan(this.budget)} / 人`)
                      .fontSize(TypeTokens.headline.size)
                      .fontWeight(600)
                      .fontColor(ColorTokens.ink)
                      .fontFeature("'tnum' on")
                      .margin({ top: SpaceTokens.xs })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  // 这张卡的可控件只有下面那条 Slider。原来值行右侧还挂着一枚
                  // chevron（读起来是「点这里选择」）但没有任何动作，
                  // 两个互相竞争的控件挤在一张卡里
                }
                .width('100%')

                // 底稿是 55/45 的手绘轨道，实为可选区间 3,000–12,000/人（默认 8,000 恰落在 55%）
                Slider({
                  value: this.budget,
                  min: BudgetConfig.MIN,
                  max: BudgetConfig.MAX,
                  step: BudgetConfig.STEP,
                  style: SliderStyle.OutSet
                })
                  .width('100%')
                  .selectedColor(ColorTokens.primary)
                  .trackColor(ColorTokens.hairline)
                  // 把手此前取 surfaceElevated：深色档 #1E1E1E 压在底轨/卡面上几乎看不见，
                  // 整条就退化成了进度条（§5 实拍结论）。帧里只画了 4px 底轨、没给把手规则，
                  // 所以这是「帧未规定」而不是「帧规定不可见」——官方 Slider 没有可见把手就没法拖。
                  .blockColor(ColorTokens.primary)
                  .accessibilityText(`调整预算档位，当前 ${MoneyText.yuan(this.budget)} 每人`)
                  .onChange((v: number) => {
                    this.budget = Math.round(v);
                  })

                Row() {
                  Text('经济')
                    .fontSize(TypeTokens.caption.size)
                    .fontWeight(450)
                    .fontColor(ColorTokens.muted)
                  Text('舒适')
                    .fontSize(TypeTokens.caption.size)
                    .fontWeight(450)
                    .fontColor(ColorTokens.muted)
                }
                .width('100%')
                .justifyContent(FlexAlign.SpaceBetween)
              }
              .width('100%')
              .padding(SpaceTokens.md)
              .borderRadius(RadiusTokens.card)
              .backgroundColor(ColorTokens.surfaceSubtle)
            }
          }
          .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, bottom: LayoutTokens.bottomScrollReserve })
          // 表单不收窄到 720 的话，宽屏上一行「目的地」能拉到八百多 vp，
          // 输入框与滑杆的可用长度就失去意义
          .width(longFormMaxWidth(this.bp, LayoutTokens.contentMaxWidth))
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)

        Column() {
          YoujingButton({
            variant: YoujingButtonVariant.PRIMARY,
            label: '开始规划',
            fullWidth: true,
            trailingSymbol: $r('sys.symbol.arrow_right'),
            onAction: (): void => {
              const d: PlanDraft = PlanDraft.get();
              const basic: TripBasicInput = {
                destination: this.city, startDate: this.startDate,
                endDate: this.endDate, people: this.party, budget: this.budget
              };
              d.basic = basic;
              markDraftDirty(true);
              this.pathStack.pushPath({ name: 'PreferenceQA' });
            }
          })
        }
        // 钉底动作条要与上面被收窄的表单同宽：它和滚动区是兄弟节点，
        // 只给滚动区设上限的话，主按钮会照旧铺满整屏（md 实测 50..2160 = 675vp，
        // 而上面的字段卡是 218..1993）——同一屏两套左右边界，就是"排版交错"。
        .width(longFormMaxWidth(this.bp, LayoutTokens.contentMaxWidth))
        .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, top: SpaceTokens.md,
          bottom: LayoutTokens.floatingDockClearance })
        // 一张节点只能挂一张 bindSheet：城市选择在根节点，识别预览挂在这条动作条上
        .bindSheet($$this.previewOpen, this.intentSheet(), {
          height: '72%',
          backgroundColor: ColorTokens.canvas,
          showClose: true,
          systemMaterial: getSheetImmersiveMaterial()
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ColorTokens.canvas)
      .bindSheet($$this.showCity, this.citySheet(), {
        height: 420,
        backgroundColor: ColorTokens.canvas,
        showClose: true,
        // 与其他三处弹层同档：半模态走 ULTRA_THICK 系统材质（材质不可用时回退上面的实色底）
        systemMaterial: getSheetImmersiveMaterial()
      })
    }
    .titleBar(HdsChrome.bar({ mainTitle: '有径', subTitle: '设定出行基础参数' }))
    .titleMode(HdsNavDestinationTitleMode.MINI)
  }
}
