/**
 * 屏11 费用 · 预算对账（帧 1ab099b1）+ 屏11b 超支数据态（帧 70642048）。
 * 同路由双数据态：segment 预算/实际 切换即两帧（稿件分帧只是分别取证）。
 * §7 必改已落：dock padding 10→8、hero-figure margin 6→4、record-btn gap 6→4、segmented padding 2→0。
 * 金额 hero：32/700 走 sans（数字永不 serif，禁令 8）。
 *
 * 数据口径（阶段 10 接真值）：
 * - 预算总额 = trip.budget（屏2 是「每人预算」）× trip.people，与底稿 8,000×2=16,000 一致；
 * - 实际与分类条全部来自 expense 表；模型里没有「分类预算」，故预算视角的百分比按
 *   各分类占预算总额、实际视角按占最大分类，不编造分档预算。
 */

import { ACTIVE_TRIP_KEY, EXPENSE_NAV, TAB_SHOWN_KEY, isTabShownTick, activeTripId, enterPlanningFlow, TAB_EXPENSE } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { MoneyText } from '../utils/MoneyText';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { ImmersiveSegmentBar, SegmentedItem } from '../components/ImmersiveSegmentBar';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';
import { ExpenseDao } from '../data/ExpenseDao';
import { TripDao, TripSummary } from '../data/TripDao';
import { CategoryBudget, CategoryTotal, Expense, ExpenseCategory } from '../model/Expense';
import { Trip } from '../model/Trip';
import { DateUtils } from '../utils/DateUtils';
import { getSheetImmersiveMaterial } from '../utils/immersiveMaterial';
import { Logger } from '../common/logger/Logger';
import { PlanDraft } from '../data/PlanDraft';
import { common } from '@kit.AbilityKit';
import { HdsNavigation, HdsNavigationTitleMode, HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { routerMap } from './AppRouter';
import { HdsChrome } from '../design/HdsChrome';

interface CategorySpend {
  name: string;
  amount: number;
  pct: number;
  color: Resource;
  /** 该类的预算上限（0 = 未设）。设了就以它为画条基线，超了整行转 danger */
  budget: number;
  over: boolean;
}

interface Receipt {
  /** 库里的自增主键：左滑删除要靠它定位，之前只展示不带 id */
  id: number;
  time: string;
  name: string;
  amount: string;
}

interface CategoryOption {
  value: ExpenseCategory;
  label: string;
}

const CATEGORY_LABELS: CategoryOption[] = [
  { value: ExpenseCategory.HOTEL, label: '住宿' },
  { value: ExpenseCategory.TRANSPORT, label: '交通' },
  { value: ExpenseCategory.FOOD, label: '餐饮' },
  { value: ExpenseCategory.TICKET, label: '门票' },
  { value: ExpenseCategory.SHOP, label: '购物' },
  { value: ExpenseCategory.OTHER, label: '其他' }
];

function labelOf(category: ExpenseCategory): string {
  for (const c of CATEGORY_LABELS) {
    if (c.value === category) {
      return c.label;
    }
  }
  return '其他';
}

function colorOf(category: ExpenseCategory): Resource {
  if (category === ExpenseCategory.HOTEL) {
    return ColorTokens.accentMention;
  }
  if (category === ExpenseCategory.TRANSPORT) {
    return ColorTokens.icon;
  }
  if (category === ExpenseCategory.FOOD) {
    return ColorTokens.bookmark;
  }
  if (category === ExpenseCategory.TICKET) {
    return ColorTokens.primary;
  }
  return ColorTokens.like;
}

function clockText(millis: number): string {
  const d: Date = new Date(millis);
  const h: string = `${d.getHours()}`;
  const m: string = `${d.getMinutes()}`;
  return `${h.length < 2 ? `0${h}` : h}:${m.length < 2 ? `0${m}` : m}`;
}

function yuan(amount: number): string {
  // DESIGN §4 数字格式：整数 + 单位，不用千分位
  return MoneyText.yuan(amount);
}

@Component
export struct ExpensePage {
  /** 断点（唯一来源 utils/breakpointCenter.ets）：宽屏下列表并成多栏，不再被整屏拉宽 */

  /** 本页是 EXPENSE_NAV 这条 tab 栈的宿主，push 必须落在自己的栈上 */
  private pathStack: NavPathStack = EXPENSE_NAV;
  /** dock 切回这一页时重取账目（广播见 AppNav.TAB_SHOWN_KEY，主链复审 P1） */
  @StorageProp(TAB_SHOWN_KEY) @Watch('onDockShown') dockTick: string = '';

  private onDockShown(): void {
    if (!isTabShownTick(this.dockTick, TAB_EXPENSE)) {
      return;
    }
    // 根页的行程上下文跟着「最后打开的那条」走（见 AppNav.activeTripId）
    const active: string = activeTripId();
    if (this.rootMode && active.length > 0 && active !== this.tripId) {
      this.tripId = active;
    }
    this.reload();
  }
  @Prop tripId: string = '';
  /**
   * 本机一条行程都没有。原来这种状态只 `Logger.info` 后保持空态，
   * 页面照样写着「还没有记账，下面记一笔后这里会出现分类」+ 一颗「记一笔」按钮——
   * 而 `saveExpense()`(:230) 在 `trip === null` 时直接 return，点了没有任何反馈。
   */
  @State private noTrip: boolean = false;
  @State private seg: number = 0;
  @State private budgetTotal: number = 0;
  /** AI 规划的整程预估（overview.totalCost，为 0 时按各天 dailyCost 累加） */
  @State private plannedTotal: number = 0;
  /** 顶栏副标题：这页可能从「最近行程」兜底进来，必须写明看的是哪一趟 */
  @State private tripLabel: string = '';
  @State private spent: number = 0;
  @State private daysLeft: number = 0;
  @State private topCategory: string = '';
  @State private receipts: Receipt[] = [];
  @State private totals: CategoryTotal[] = [];
  @State private showRecord: boolean = false;
  @State private showBudget: boolean = false;
  /** 六档分类预算的编辑草稿，顺序与 CATEGORY_LABELS 一致（空串 = 不设上限） */
  @State private budgetInputs: string[] = ['', '', '', '', '', ''];
  @State private categoryBudgets: CategoryBudget[] = [];
  @State private inputAmount: string = '';
  @State private inputName: string = '';
  @State private inputCategory: ExpenseCategory = ExpenseCategory.TICKET;
  /** 顶栏磨砂两态：由**绝对**滚动偏移驱动（每帧增量会被松手回弹的负帧打灭，契约 §Translucency） */
  @State private barScrolled: boolean = false;
  private barScroller: Scroller = new Scroller();
  private segments: SegmentedItem[] = [{ label: '预算' }, { label: '实际' }];
  private trip: Trip | null = null;
  /** 已经因「上下文行程不存在」退回过一次无上下文分支；防异步自循环 */
  private contextRetried: boolean = false;

  aboutToAppear(): void {
    // 冷启后第一次进「费用」tab：本页是新建的，@StorageProp 的初值不会触发 onDockShown，
    // 只走 reload 的空 tripId 分支就会退到 rows[0]（最近一条）——用户刚打开的是行程 B，
    // 看到账单却成了 A。这里先认「最后打开的那条」，没有才退最近一条。
    if (this.rootMode && this.tripId.length === 0) {
      const active: string = activeTripId();
      if (active.length > 0) {
        this.tripId = active;
      }
    }
    this.reload();
  }

  private ctx(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  private reload(): void {
    if (this.tripId.length === 0) {
      // 从 dock 的「费用」tab 进来时没有行程上下文：退到最近一条行程，
      // 而不是给出一页 ¥0 的死数据
      TripDao.listSummaries(this.ctx()).then((rows: TripSummary[]): void => {
        if (rows.length === 0) {
          Logger.info('Ui.Expense', '本机还没有行程，费用页给规划入口而不是死空态');
          this.noTrip = true;
          return;
        }
        this.noTrip = false;
        this.tripId = rows[0].id;
        this.reload();
      }).catch((err: Error) => {
        Logger.warn('Ui.Expense', `取最近行程失败: ${err.message}`);
      });
      return;
    }
    const context: common.Context = this.ctx();
    TripDao.loadTrip(context, this.tripId).then((trip: Trip | null): Promise<CategoryTotal[]> => {
      if (trip === null) {
        // 上下文里的行程已不在本机（桌面卡片带旧 id 深链进来，或删除后 ACTIVE_TRIP_KEY 没跟上）：
        // 丢掉这个 id 退回「无上下文」分支，它会自己找最近一条或给规划入口。
        // 只退一次——无上下文分支挑的是 listSummaries 第一条，那条要也取不到就是数据本身坏了，
        // 再退一次就是异步自循环。
        AppStorage.setOrCreate(ACTIVE_TRIP_KEY, '');
        this.tripId = '';
        if (!this.contextRetried) {
          this.contextRetried = true;
          this.reload();
        } else {
          this.noTrip = true;
        }
        return Promise.resolve<CategoryTotal[]>([]);
      }
      this.contextRetried = false;
      this.trip = trip;
      AppStorage.setOrCreate(ACTIVE_TRIP_KEY, trip.id);
      this.tripLabel = `${trip.destination} · ${trip.startDate} – ${trip.endDate}`;
      this.budgetTotal = trip.budget * trip.people;
      this.categoryBudgets = trip.categoryBudgets === undefined ? [] : trip.categoryBudgets;
      let sumDays: number = 0;
      for (const d of trip.days) {
        sumDays += d.dailyCost;
      }
      this.plannedTotal = trip.overview.totalCost > 0 ? trip.overview.totalCost : sumDays;
      const span: number = DateUtils.spanDays(trip.startDate, trip.endDate);
      const started: number = DateUtils.spanDays(trip.startDate, DateUtils.todayIso());
      // spanDays 两头都含：Day1 时 started 已经是 1，直接 span - started 会把「今天」
      // 当成已过掉（3 天行程首日写「还剩 2 天」、末日写「还剩 0 天」，与同卡「3 天」自相矛盾）
      this.daysLeft = Math.max(0, span - started + 1);
      return ExpenseDao.sumByCategory(context, trip.id);
    }).then((totals: CategoryTotal[]): Promise<Expense[]> => {
      this.applyTotals(totals);
      return ExpenseDao.listByTrip(context, this.tripId, 12);
    }).then((list: Expense[]): void => {
      this.receipts = list.map((e: Expense): Receipt => {
        const r: Receipt = { id: e.id, time: clockText(e.createdAt), name: e.name, amount: yuan(e.amount) };
        return r;
      });
    }).catch((err: Error) => {
      Logger.error('Ui.Expense', `费用加载失败: ${err.message}`);
    });
  }

  private applyTotals(totals: CategoryTotal[]): void {
    let sum: number = 0;
    for (const t of totals) {
      sum += t.amount;
    }
    this.spent = sum;
    this.topCategory = totals.length > 0 ? labelOf(totals[0].category) : '';
    this.totals = totals;
  }

  private budgetOf(category: ExpenseCategory): number {
    for (const b of this.categoryBudgets) {
      if (b.category === category) {
        return b.amount;
      }
    }
    return 0;
  }

  /**
   * 预算视角：这一类**设了上限就按自己的上限画条**（超了转 danger），没设才退回"占行程总预算"；
   * 实际视角仍按占最大分类。同一批真值、三种读法。
   */
  private currentCats(): CategorySpend[] {
    let max: number = 0;
    for (const t of this.totals) {
      if (t.amount > max) {
        max = t.amount;
      }
    }
    return this.totals.map((t: CategoryTotal): CategorySpend => {
      const budget: number = this.seg === 0 ? this.budgetOf(t.category) : 0;
      const over: boolean = budget > 0 && t.amount > budget;
      const base: number = budget > 0 ? budget :
        (this.seg === 0 ? Math.max(1, this.budgetTotal) : Math.max(1, max));
      const c: CategorySpend = {
        name: labelOf(t.category),
        amount: t.amount,
        pct: Math.min(100, Math.max(1, Math.round((t.amount / base) * 100))),
        color: over ? ColorTokens.danger : colorOf(t.category),
        budget: budget,
        over: over
      };
      return c;
    });
  }

  /** 草稿回填必须在 show 之前：bindSheet 的内容不随事后的状态变化重绘 */
  private openBudgetSheet(): void {
    const next: string[] = [];
    for (let i = 0; i < CATEGORY_LABELS.length; i++) {
      const b: number = this.budgetOf(CATEGORY_LABELS[i].value);
      next.push(b > 0 ? `${b}` : '');
    }
    this.budgetInputs = next;
    this.showBudget = true;
  }

  private budgetDraftSum(): number {
    let sum: number = 0;
    for (let i = 0; i < this.budgetInputs.length; i++) {
      const v: number = Number(this.budgetInputs[i]);
      if (!Number.isNaN(v) && v > 0) {
        sum += Math.round(v);
      }
    }
    return sum;
  }

  private setBudgetInput(idx: number, value: string): void {
    const next: string[] = this.budgetInputs.slice();
    next[idx] = value;
    this.budgetInputs = next;
  }

  /** 保存分类预算：留空 = 该类不设上限；填了必须是正整数，错了就地说明是哪一类 */
  private saveBudgets(): void {
    const trip: Trip | null = this.trip;
    if (trip === null) {
      return;
    }
    const list: CategoryBudget[] = [];
    for (let i = 0; i < CATEGORY_LABELS.length; i++) {
      const raw: string = this.budgetInputs[i].trim();
      if (raw.length === 0) {
        continue;
      }
      const v: number = Number(raw);
      if (Number.isNaN(v) || v <= 0) {
        this.getUIContext().getPromptAction().showToast({
          message: `${CATEGORY_LABELS[i].label}的预算要填正整数`, duration: 1800
        });
        return;
      }
      const row: CategoryBudget = { category: CATEGORY_LABELS[i].value, amount: Math.round(v) };
      list.push(row);
    }
    TripDao.saveCategoryBudgets(this.ctx(), trip.id, list).then((): void => {
      this.categoryBudgets = list;
      trip.categoryBudgets = list;
      this.showBudget = false;
      this.reload();
      this.getUIContext().getPromptAction().showToast({ message: '已保存分类预算', duration: 1500 });
    }).catch((err: Error): void => {
      Logger.error('Ui.Expense', `分类预算保存失败: ${err.message}`);
      this.getUIContext().getPromptAction().showToast({ message: '保存失败', duration: 1800 });
    });
  }

  /** 记一笔：金额必填且为正整数，名称缺省用分类名 */
  private saveExpense(): void {
    const trip: Trip | null = this.trip;
    const amount: number = Number(this.inputAmount);
    if (trip === null || this.inputAmount.length === 0 || Number.isNaN(amount) || amount <= 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请填写正确的金额', duration: 1800 });
      return;
    }
    const name: string = this.inputName.trim().length > 0 ? this.inputName.trim() : labelOf(this.inputCategory);
    const expense: Expense = {
      id: 0, tripId: trip.id, dayIndex: Math.min(trip.days.length, Math.max(1,
        DateUtils.spanDays(trip.startDate, DateUtils.todayIso()))),
      category: this.inputCategory, name: name, amount: Math.round(amount), createdAt: Date.now()
    };
    ExpenseDao.add(this.ctx(), expense).then((): Promise<CategoryTotal[]> => {
      return ExpenseDao.sumByCategory(this.ctx(), trip.id);
    }).then((totals: CategoryTotal[]): void => {
      this.applyTotals(totals);
      this.inputAmount = '';
      this.inputName = '';
      this.showRecord = false;
      this.reload();
      this.getUIContext().getPromptAction().showToast({ message: `已记 ${yuan(expense.amount)}`, duration: 1500 });
    }).catch((err: Error) => {
      Logger.error('Ui.Expense', `记账失败: ${err.message}`);
      this.getUIContext().getPromptAction().showToast({ message: '记账失败', duration: 1800 });
    });
  }

  @Builder
  categoryRow(cat: CategorySpend) {
    Row({ space: SpaceTokens.xs }) {
      Circle()
        .width(8)
        .height(8)
        .fill(cat.color)
      Text(cat.name)
        .fontSize(TypeTokens.small.size)
        .fontColor(ColorTokens.ink)
        .width(40)
      Progress({ value: cat.pct, total: 100, type: ProgressType.Linear })
        .color(cat.color)
        .layoutWeight(1)
        .accessibilityText(cat.budget > 0
          ? `${cat.name} 已花 ${cat.amount} 元，上限 ${cat.budget} 元`
          : `${cat.name} 占预算 ${Math.round(cat.pct)}%`)

      Column() {
        Text(yuan(cat.amount))
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(cat.over ? ColorTokens.danger : ColorTokens.body)
          .fontFeature("'tnum' on")
        if (cat.budget > 0) {
          Text(cat.over ? `超 ${yuan(cat.amount - cat.budget)}` : `上限 ${yuan(cat.budget)}`)
            .fontSize(TypeTokens.overline.size)
            .fontColor(cat.over ? ColorTokens.danger : ColorTokens.muted)
            .fontFeature("'tnum' on")
            .margin({ top: SpaceTokens.xxs })
        }
      }
      .alignItems(HorizontalAlign.End)
      .width(84)
    }
    .width('100%')
    .padding({ top: SpaceTokens.xs, bottom: SpaceTokens.xs })
  }

  @Builder
  categoryChip(option: CategoryOption) {
    // 选中态按契约 tint 配方（DESIGN §9）：tint 底 + 1px primary 描边 + ink 字。
    // 原走 EMPHASIZED 实心蓝，与本 sheet 里的「保存」主按钮形成同屏双实心（禁令 1）
    Button(option.label)
      .fontSize(TypeTokens.small.size)
      .fontWeight(this.inputCategory === option.value ? 600 : 450)
      .fontColor(this.inputCategory === option.value ? ColorTokens.ink : ColorTokens.body)
      .height(LayoutTokens.minTouchTarget)
      .type(ButtonType.Capsule)
      .buttonStyle(ButtonStyleMode.NORMAL)
      .backgroundColor(this.inputCategory === option.value
        ? ColorTokens.primaryTint : ColorTokens.surfaceElevated)
      .border({
        width: this.inputCategory === option.value ? LayoutTokens.glassBorderWidth : 0,
        color: ColorTokens.primary
      })
      // 六枚等宽排一行（父 Row 只有 331vp，见 recordSheet 的注释）：
      // 默认内边距会把两字标签撑到 60vp，六枚就换行了；等宽 46.7vp 刚好排满。
      .layoutWeight(1)
      .padding({ left: 0, right: 0 })
      .onClick(() => {
        this.inputCategory = option.value;
      })
  }

  @Builder
  recordSheet() {
    // 主键不再放进滚动区，滚动区也不再吃百分比高度。
    // 实测：键盘弹起后 bindSheet 不按压缩后的窗口重量高，`.height('100%')` 于是
    // 按键盘弹起前解析 → Scroll 以为装得下、不进可滚状态，「保存」被裁在可见区外
    // （改 constraintSize.maxHeight 能让它进可滚，但注入的上滑推不动它，且没键盘时
    // 反而要滑一下才看到主键——所以这里不靠"能滑到"，改成主键根本不进滚动区）。
    // 上限 300 不是随手定的：sheet 高 85% 时内容顶在 y≈493(px)，滚动区每高 1vp，
    // 「保存」就往下挪 1vp；300 是让它停在键盘顶（526vp）之上的最大值。
    // 高度也不能换成 SheetSize.FIT_CONTENT（试过，真机反证）：fit 之后面板顶落到
    // y≈1296(px)，键盘一来系统只把面板上移「刚好露出聚焦的输入框」那么多，
    // 名称/分类/保存整块压在键盘底下（dump 里「保存」已不在树里，键盘顶 1643）。
    // 代价是视口里只剩 46vp 给分类：六档胶囊排两行时第二行（默认选中的「门票」
    // 就在这里）整行落在视口外——打开面板看到三枚都没选中、保存下去却记成门票
    // （真机 dump 实证）。所以六档改成一行等宽胶囊，选择始终在屏上。
    Column() {
      Scroll() {
        Column() {
      Text('记一笔')
        .fontSize(TypeTokens.title.size)
        .fontWeight(700)
        .fontFamily(TypeTokens.title.family)
        .fontColor(ColorTokens.ink)
        .margin({ top: SpaceTokens.lg })
      Text('金额与名称只存本机行程')
        .fontSize(TypeTokens.small.size)
        .fontColor(ColorTokens.body)
        .margin({ top: SpaceTokens.xxs, bottom: SpaceTokens.base })

      TextInput({ placeholder: '金额（元）', text: this.inputAmount })
        .type(InputType.Number)
        .fontSize(TypeTokens.body.size)
        .fontColor(ColorTokens.ink)
        .backgroundColor(ColorTokens.surfacePanel)
        .borderRadius(RadiusTokens.reason)
        .height(LayoutTokens.composeFieldHeight)
        .onChange((v: string) => {
          this.inputAmount = v;
        })
        // 键盘上的「完成」也能提交：宽屏（折叠展开）数字键盘弹起后，
        // 工作表底部的「保存」会被压到可见区之外且滑不出来（§5ci 续 13/14 实测），
        // 记账因此在 md 档断链。给两个输入框都挂 enterKey + onSubmit，
        // 让用户在键盘上就能收尾；按钮仍是主通路，这条是并列的第二条。
        .enterKeyType(EnterKeyType.Done)
        .onSubmit((): void => {
          this.saveExpense();
        })
      TextInput({ placeholder: '名称，如 故宫门票', text: this.inputName })
        .fontSize(TypeTokens.body.size)
        .fontColor(ColorTokens.ink)
        .backgroundColor(ColorTokens.surfacePanel)
        .borderRadius(RadiusTokens.reason)
        .height(LayoutTokens.composeFieldHeight)
        .margin({ top: SpaceTokens.xs })
        .onChange((v: string) => {
          this.inputName = v;
        })
        .enterKeyType(EnterKeyType.Done)
        .onSubmit((): void => {
          this.saveExpense();
        })

      // 一行六枚、等宽：wrap 成两行时第二行落进 300vp 视口之外（含默认选中项）
      Row({ space: SpaceTokens.xxs }) {
        ForEach(CATEGORY_LABELS, (option: CategoryOption) => {
          this.categoryChip(option)
        }, (option: CategoryOption): string => `rec-${option.value}-${this.inputCategory === option.value}`)
      }
      .width('100%')
      .margin({ top: SpaceTokens.sm })

        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: SpaceTokens.base, right: SpaceTokens.base })
      }
      .width('100%')
      // 定高上限（不是 '100%'）：滚动视口整体落在键盘之上的可见区内，
      // 主键紧跟其后，于是「保存」的位置与 sheet 是否重量高无关。
      .constraintSize({ maxHeight: 300 })
      .scrollBar(BarState.Off)
      .align(Alignment.Top)

      YoujingButton({
        variant: YoujingButtonVariant.PRIMARY,
        label: '保存',
        fullWidth: true,
        onAction: (): void => {
          this.saveExpense();
        }
      })
        .margin({ top: SpaceTokens.xs, bottom: SpaceTokens.sm })
    }
    .width('100%')
    .padding({ left: SpaceTokens.base, right: SpaceTokens.base, bottom: SpaceTokens.lg })
    .backgroundColor(ColorTokens.canvas)
  }

  @Builder
  budgetField(option: CategoryOption, idx: number) {
    Row({ space: SpaceTokens.xs }) {
      Text(option.label)
        .fontSize(TypeTokens.body.size)
        .fontColor(ColorTokens.ink)
        .width(44)
      TextInput({ placeholder: '不设上限', text: this.budgetInputs[idx] })
        .type(InputType.Number)
        .fontSize(TypeTokens.body.size)
        .fontColor(ColorTokens.ink)
        .backgroundColor(ColorTokens.surfacePanel)
        .borderRadius(RadiusTokens.reason)
        .height(LayoutTokens.composeFieldHeight)
        .layoutWeight(1)
        // 最后一档给「完成」并直接落库：六档字段都要点数字键盘，键盘弹起时
        // 「保存」可能落在键盘之下（真机实测点不到），键盘上的收尾键是并列的第二条通路
        .enterKeyType(idx === CATEGORY_LABELS.length - 1 ? EnterKeyType.Done : EnterKeyType.Next)
        .onSubmit((): void => {
          this.saveBudgets();
        })
        .onChange((v: string): void => {
          this.setBudgetInput(idx, v);
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .margin({ top: SpaceTokens.xs })
  }

  @Builder
  budgetSheet() {
    // 与 recordSheet 同一条铁律：主键在滚动区之外、滚动区吃定高上限，
    // 否则键盘一弹起「保存」就又会被压出可见区（§5ci 续 13/15 那个 P0 的形状）
    Column() {
      Scroll() {
        Column() {
          Text('分类预算')
            .fontSize(TypeTokens.title.size)
            .fontWeight(700)
            .fontFamily(TypeTokens.title.family)
            .fontColor(ColorTokens.ink)
            .margin({ top: SpaceTokens.lg })
          Text(`合计 ${yuan(this.budgetDraftSum())} · 行程总预算 ${yuan(this.budgetTotal)}`)
            .fontSize(TypeTokens.small.size)
            .fontColor(this.budgetDraftSum() > this.budgetTotal && this.budgetTotal > 0
              ? ColorTokens.danger : ColorTokens.body)
            .fontFeature("'tnum' on")
            .margin({ top: SpaceTokens.xxs, bottom: SpaceTokens.sm })

          ForEach(CATEGORY_LABELS, (option: CategoryOption, idx: number) => {
            this.budgetField(option, idx)
          }, (option: CategoryOption): string => `bud-${option.value}`)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: SpaceTokens.base, right: SpaceTokens.base })
      }
      .width('100%')
      // 上限 200 而不是 320：真机实测键盘弹起后键盘顶在 y≈1700/2690，
      // 320 的滚动区会把「保存」推到键盘底下（第一次脚本点保存没生效就是这个原因）。
      // 六档字段本来就靠滚动逐个到达，主键必须留在键盘之上。
      .constraintSize({ maxHeight: 200 })
      .scrollBar(BarState.Off)
      .align(Alignment.Top)

      YoujingButton({
        variant: YoujingButtonVariant.PRIMARY,
        label: '保存',
        fullWidth: true,
        onAction: (): void => {
          this.saveBudgets();
        }
      })
        .margin({ top: SpaceTokens.xs, bottom: SpaceTokens.sm })
    }
    .width('100%')
    .padding({ left: SpaceTokens.base, right: SpaceTokens.base, bottom: SpaceTokens.lg })
    .backgroundColor(ColorTokens.canvas)
  }

  /** 预算消耗百分比：超支时封顶 100，颜色另说，进度条本身不画负值 */
  private spentPct(): number {
    if (this.budgetTotal <= 0) {
      return 0;
    }
    return Math.max(0, Math.min(100, Math.round((this.spent / this.budgetTotal) * 100)));
  }

  @Builder
  sectionHeader(title: string) {
    Text(title)
      .fontSize(TypeTokens.overline.size)
      .fontWeight(600)
      .fontColor(ColorTokens.muted)
      .width('100%')
      .padding({ top: SpaceTokens.base, bottom: SpaceTokens.xs })
  }

  /** 分类支出这一组的头：左边标题、右边进「分类预算」工作表 */
  /**
   * 条形画的是占比，但分母随分段与「是否设过分类预算」变三种（见 currentCats）。
   * 行内不重复标分母，改由分组头说清当前这一档的分母是什么：
   * 预算档且没给任何分类预算 ⇒ 占行程总预算；预算档且设了 ⇒ 各自的预算（超了转 danger，
   * 分组头不再硬说"占行程预算"）；实际档 ⇒ 占最大分类。
   */
  private categoryHeaderTitle(): string {
    if (this.seg !== 0) {
      return '分类支出 · 占最大分类';
    }
    for (const b of this.categoryBudgets) {
      if (b.amount > 0) {
        return '分类支出';
      }
    }
    return '分类支出 · 占行程预算';
  }

  @Builder
  categoryHeader() {
    Row() {
      Text(this.categoryHeaderTitle())
        .fontSize(TypeTokens.overline.size)
        .fontWeight(600)
        .fontColor(ColorTokens.muted)
        .layoutWeight(1)
      Button('分类预算')
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .fontColor(ColorTokens.primary)
        .fontSize(TypeTokens.overline.size)
        .height(LayoutTokens.minTouchTarget)
        .padding({ left: SpaceTokens.xs, right: SpaceTokens.xxs })
        .accessibilityText('设置各分类预算上限')
        .enabled(!this.noTrip)
        .onClick((): void => {
          this.openBudgetSheet();
        })
    }
    .width('100%')
    .padding({ top: SpaceTokens.xs, bottom: SpaceTokens.xxs })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  receiptRow(r: Receipt) {
    Row() {
      Text(r.time)
        .fontSize(TypeTokens.caption.size)
        .fontWeight(450)
        .fontColor(ColorTokens.muted)
        .fontFeature("'tnum' on")
        .width(LayoutTokens.itineraryTimeGutter)
      Text(r.name)
        .fontSize(TypeTokens.small.size)
        .fontColor(ColorTokens.ink)
        .layoutWeight(1)
      Text(r.amount)
        .fontSize(TypeTokens.small.size)
        .fontWeight(600)
        .fontColor(ColorTokens.ink)
        .fontFeature("'tnum' on")
    }
    .width('100%')
    .padding({ top: SpaceTokens.xs, bottom: SpaceTokens.xs })
  }

  /** 官方行级动作：误记一笔可以左滑删掉（ExpenseDao.delete 此前无调用方） */
  @Builder
  receiptDelete(r: Receipt) {
    Row() {
      Button() {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(IconSizes.control)
          .fontColor([ColorTokens.onPrimary])
      }
      .width(56)
      .height(56)
      .type(ButtonType.Circle)
      .backgroundColor(ColorTokens.danger)
      .accessibilityText(`删除 ${r.name}`)
      .id('rec-del')
      .onClick((): void => {
        this.confirmDeleteReceipt(r);
      })
    }
    .justifyContent(FlexAlign.End)
    .alignItems(VerticalAlign.Center)
    .width(84)
    .height('100%')
    .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm })
  }

  private confirmDeleteReceipt(r: Receipt): void {
    this.getUIContext().showAlertDialog({
      title: '删除这笔记账',
      message: `${r.time} ${r.name} ${r.amount}\n只删本机记录，不可恢复。`,
      primaryButton: {
        value: '取消',
        action: (): void => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: ColorTokens.danger,
        action: (): void => {
          this.doDeleteReceipt(r.id);
        }
      }
    });
  }

  private doDeleteReceipt(id: number): void {
    ExpenseDao.delete(this.ctx(), id).then((): void => {
      this.getUIContext().getPromptAction().showToast({ message: '已删除该笔记账' });
      this.reload();
    }).catch((err: Error): void => {
      Logger.error('Ui.Expense', `删除记账失败: ${err.message}`);
      this.getUIContext().getPromptAction().showToast({ message: '删除失败，详见日志' });
    });
  }

  /** 根页模式：作为 tab 的内容区内联在 TabContent 里（有据路线 B），此时本页自带 HdsNavigation */
  rootMode: boolean = false;

  @Builder
  rootShell() {
      Stack({ alignContent: Alignment.Bottom }) {
      Column() {

        // 分段栏是 itemWidth:164 的定宽控件（2×164=328vp 恰好是 sm 的通栏宽），
        // 到了 md 内容通栏之后它会贴左、右边空出一条。让 ListItem 居中对齐：
        // 通栏的子级本身占满，居中不改变它们，只有这枚定宽栏会被摆到中间。
        List({ scroller: this.barScroller }) {
          ListItem() {
            ImmersiveSegmentBar({
              items: this.segments,
              selectedIndex: $seg,
              itemWidth: 164,
              buttonVerticalPadding: 2.15,
              // 契约四处玻璃面之一：分段控件轨道走系统材质（handoff §5/§9）。
              // 本页轨道下有 surfaceElevated 实色背板而非滚动内容，lightContent 保持 false
              overrideTrackMaterial: true,
              a11yLabel: '支出维度切换'
            })
          }
          .margin({ bottom: SpaceTokens.base })

          ListItem() {
            // hero 面板：永不带影（决议 4）
            Column() {
              // 从 dock「费用」进来时没有行程上下文，页会退到最近一条行程——
              // 必须把这趟是谁写进正文，否则用户以为看的是刚才那趟
              if (this.tripLabel.length > 0) {
                Text(this.tripLabel)
                  .fontSize(TypeTokens.small.size)
                  .fontWeight(600)
                  .fontColor(ColorTokens.ink)
                  .fontFeature("'tnum' on")
                  .margin({ bottom: SpaceTokens.xxs })
              }
              Text(this.seg === 0 ?
                // 两个数量的是不同的东西：预算=人均×人数（用户给的），
                // 后者=AI 各天 dailyCost 合计（真机核过 total_cost 540+540+460=1540）。
                // 叫"规划预估"会让人以为整程只花这些，按口径直说
                `预算 ${yuan(this.budgetTotal)} · 各天预估合计 ${yuan(this.plannedTotal)} · ` +
                `${this.trip === null ? 0 : this.trip.people} 人 · ` +
                `${this.trip === null ? 0 : this.trip.days.length} 天` :
                `实际 ${yuan(this.spent)} · ${this.trip === null ? 0 : this.trip.people} 人 · ` +
                `${this.trip === null ? 0 : this.trip.days.length} 天`)
                .fontSize(TypeTokens.overline.size)
                .fontWeight(600)
                .fontColor(ColorTokens.muted)
                .fontFeature("'tnum' on")
              Row({ space: SpaceTokens.xs }) {
                Text(yuan(this.spent))
                  .fontSize(TypeTokens.display.size)
                  .fontWeight(700)
                  .fontColor(this.spent > this.budgetTotal ? ColorTokens.danger : ColorTokens.ink)
                  .fontFeature("'tnum' on")
                Text('已花')
                  .fontSize(TypeTokens.caption.size)
                  .fontWeight(450)
                  .fontColor(ColorTokens.muted)
                  .margin({ bottom: SpaceTokens.xxs })
              }
              .alignItems(VerticalAlign.Bottom)
              .margin({ top: SpaceTokens.xxs })

              // 进度条原来单独一条、无读数：已花 0 时它就是一个灰底空轨，
              // 实拍读起来是「hero 卡里的一条分隔线」（§5.14 同一类）。
              // 给它一个同排的百分数读数，轨色也压到 surface-sunken 与卡面分开
              Row({ space: SpaceTokens.xs }) {
                Progress({ value: this.spentPct(), total: 100, type: ProgressType.Linear })
                  .color(this.spent > this.budgetTotal ? ColorTokens.danger : ColorTokens.primary)
                  .backgroundColor(ColorTokens.surfaceSunken)
                  .layoutWeight(1)
                  .accessibilityText(`预算已用 ${Math.round(this.spentPct())}%`)
                Text(`已用 ${Math.round(this.spentPct())}%`)
                  .fontSize(TypeTokens.caption.size)
                  .fontWeight(450)
                  .fontColor(ColorTokens.muted)
                  .fontFeature("'tnum' on")
              }
              .alignItems(VerticalAlign.Center)
              .width('100%')
              .margin({ top: SpaceTokens.sm })

              Text(this.spent > this.budgetTotal ?
                `超支 ${yuan(this.spent - this.budgetTotal)}${this.topCategory.length > 0 ? ` · 主要来自${this.topCategory}` : ''}` :
                `剩 ${yuan(Math.max(0, this.budgetTotal - this.spent))} · 还剩 ${this.daysLeft} 天`)
                .fontSize(TypeTokens.caption.size)
                .fontWeight(450)
                .fontColor(this.spent > this.budgetTotal ? ColorTokens.danger : ColorTokens.body)
                .fontFeature("'tnum' on")
                .margin({ top: SpaceTokens.xs })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding(SpaceTokens.base)
            .borderRadius(RadiusTokens.hero)
            .backgroundColor(ColorTokens.surfaceElevated)
          }

          ListItemGroup({ header: this.categoryHeader() }) {
            if (this.totals.length === 0) {
              ListItem() {
                Text(this.noTrip ? '还没有行程，先规划一条才能记账' : '还没有记账，下面记一笔后这里会出现分类')
                  .fontSize(TypeTokens.caption.size)
                  .fontColor(ColorTokens.muted)
                  .width('100%')
                  .padding({ top: SpaceTokens.xs, bottom: SpaceTokens.xs })
              }
            }
            ForEach(this.currentCats(), (cat: CategorySpend) => {
              ListItem() {
                this.categoryRow(cat)
              }
            }, (cat: CategorySpend): string => `cat-${this.seg}-${cat.name}-${cat.amount}-${cat.pct}`)
          }
          .divider({ strokeWidth: LayoutTokens.hairlineWidth, color: ColorTokens.separator })
          .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm })
          .backgroundColor(ColorTokens.canvas)
          .borderRadius(RadiusTokens.card)
          .clip(true)
          .margin({ top: SpaceTokens.xs })

          ListItemGroup({ header: this.sectionHeader('最近记账') }) {
            if (this.receipts.length === 0) {
              ListItem() {
                Text('今天还没有记录')
                  .fontSize(TypeTokens.caption.size)
                  .fontColor(ColorTokens.muted)
                  .width('100%')
                  .padding({ top: SpaceTokens.xs, bottom: SpaceTokens.xs })
              }
            }
            ForEach(this.receipts, (r: Receipt) => {
              ListItem() {
                this.receiptRow(r)
              }
              .swipeAction({ end: this.receiptDelete(r), edgeEffect: SwipeEdgeEffect.Spring })
            }, (r: Receipt): string => `rc-${r.id}-${r.time}-${r.name}-${r.amount}`)
          }
          .divider({ strokeWidth: LayoutTokens.hairlineWidth, color: ColorTokens.separator })
          .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm })
          .backgroundColor(ColorTokens.canvas)
          .borderRadius(RadiusTokens.card)
          .clip(true)
          .margin({ top: SpaceTokens.xs })

          ListItem() {
            // 没有行程时这颗按钮是"点了没反应"的死控件（记账要有行程上下文才能落库），
            // 所以整颗换成主链入口：切回「行程」页签并把屏2 推上去
            if (this.noTrip) {
              Button('开始规划新行程')
                .width('100%')
                .height(LayoutTokens.minTouchTarget)
                .type(ButtonType.Capsule)
                .fontColor(ColorTokens.onPrimary)
                .fontSize(TypeTokens.body.size)
                .fontWeight(600)
                .buttonStyle(ButtonStyleMode.EMPHASIZED)
                .onClick((): void => {
                  PlanDraft.fresh();
                  enterPlanningFlow('TripInput');
                })
            } else {
            // 记一笔：官方胶囊 Button（原来是 44 高 + 1px 描边的自绘 Pill）
            Button() {
              Row({ space: SpaceTokens.xxs }) {
                SymbolGlyph($r('sys.symbol.plus'))
                  .fontSize(IconSizes.control)
                  .fontColor([ColorTokens.ink])
                Text('记一笔')
                  .fontSize(TypeTokens.body.size)
                  .fontWeight(600)
                  .fontColor(ColorTokens.ink)
              }
            }
            .width('100%')
            .height(LayoutTokens.minTouchTarget)
            .type(ButtonType.Capsule)
            .buttonStyle(ButtonStyleMode.NORMAL)
            .onClick(() => {
              this.showRecord = true;
            })
            // 一个节点只能挂一张 bindSheet：两张都挂在根 Column 上时后者覆盖前者，
            // 「记一笔」因此整颗按钮点了没反应（分类预算的 sheet 抢了绑定）。
            // 记一笔自己的面板挂回按钮本体。
            .bindSheet($$this.showRecord, this.recordSheet(), {
              height: '85%',
              backgroundColor: ColorTokens.canvas,
              showClose: true,
              systemMaterial: getSheetImmersiveMaterial()
            })
            }
          }
          .margin({ top: SpaceTokens.lg })
        }
        // 这一屏不并栏：List 里装的是「总览 + 预算/实际切换 + 分类条形 + 最近记账 + 钉底记一笔」，
        // 是一份报告而不是卡片墙。md 实测 lanes(2) 把官方分段栏压成 50..1075（左半屏）、
        // 「记一笔」主钮压成 50..1105 = 337.6vp 靠左半边——同一屏两套左右边界，
        // 分段栏也不该被切成半宽。卡片类的屏12/屏4/屏5 才用 lanes，这里保持单栏。
        // 分段栏是 itemWidth:164 的定宽控件（2×164=328vp 恰好 sm 通栏），
        // md 下内容通栏后它会贴左、右边空出一条；让 ListItem 居中，
        // 通栏子级本身占满不受影响，只有这枚定宽栏被摆到中间。
        .alignListItem(ListItemAlign.Center)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .cachedCount(6)
        // 「+ 记一笔」是这条 List 的最后一行，而 dock 是浮在内容上的：
        // 通用 94 比 dock 实占的 112 少 18vp，滚到底按钮下沿仍藏在 dock 底下
        .padding({ left: SpaceTokens.base, right: SpaceTokens.base, bottom: LayoutTokens.floatingDockClearance })
        .layoutWeight(1)
        .onDidScroll((): void => {
          this.syncBarScroll();
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ColorTokens.canvas)
      // 试过 SheetSize.FIT_CONTENT 来救"键盘弹起后保存键不可达"（§5ci 续 14），
      // 复拍与 '85%' 毫无差别：保存键仍不在树里、三次上滑仍调不出来。
      // 没有证据的视觉改动不留在代码里，退回原值；那条 P0 仍未修。
      .bindSheet($$this.showBudget, this.budgetSheet(), {
        height: '55%',
        backgroundColor: ColorTokens.canvas,
        showClose: true,
        systemMaterial: getSheetImmersiveMaterial()
      })
    }
    .width('100%')
    .height('100%')
  }

  /** 绝对滚动偏移 → 顶栏磨砂开关（>0 即开，静止归零） */
  private syncBarScroll(): void {
    const y: number = this.barScroller.currentOffset().yOffset;
    const on: boolean = y > 0;
    if (on !== this.barScrolled) {
      this.barScrolled = on;
    }
  }

  build() {
    if (this.rootMode) {
      HdsNavigation(this.pathStack) {
        this.rootShell()
      }
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(true)
      .titleBar(HdsChrome.bar({ mainTitle: '费用', scrolled: this.barScrolled }))
      .navDestination(routerMap)
      .mode(NavigationMode.Stack)
      .width('100%')
      .height('100%')
    } else {
      HdsNavDestination() {
        this.rootShell()
      }
      // HDS 深色档这层默认纯黑，透明栏会把它露成一条比画布暗一档的带（成因与实测见 Docs/INIT_REPORT.md §5ci 续 80）
      .backgroundColor(ColorTokens.canvas)
      .titleBar(HdsChrome.bar({ mainTitle: '费用', scrolled: this.barScrolled }))
      .titleMode(HdsNavDestinationTitleMode.MINI)
    }
  }
}
