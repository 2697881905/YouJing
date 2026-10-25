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

import { APP_NAV } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { ImmersiveSegmentBar, SegmentedItem } from '../components/ImmersiveSegmentBar';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';
import { FloatingDock } from '../components/FloatingDock';
import { ExpenseDao } from '../data/ExpenseDao';
import { TripDao, TripSummary } from '../data/TripDao';
import { CategoryTotal, Expense, ExpenseCategory } from '../model/Expense';
import { Trip } from '../model/Trip';
import { DateUtils } from '../utils/DateUtils';
import { getSheetImmersiveMaterial } from '../utils/immersiveMaterial';
import { Logger } from '../common/logger/Logger';
import { common } from '@kit.AbilityKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';

interface CategorySpend {
  name: string;
  amount: number;
  pct: number;
  color: Resource;
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
  return `¥${amount}`;
}

@Component
export struct ExpensePage {
  private pathStack: NavPathStack = APP_NAV;
  @Prop tripId: string = '';
  @State private seg: number = 0;
  @State private budgetTotal: number = 0;
  /** 顶栏副标题：这页可能从「最近行程」兜底进来，必须写明看的是哪一趟 */
  @State private tripLabel: string = '';
  @State private spent: number = 0;
  @State private daysLeft: number = 0;
  @State private topCategory: string = '';
  @State private receipts: Receipt[] = [];
  @State private totals: CategoryTotal[] = [];
  @State private showRecord: boolean = false;
  @State private inputAmount: string = '';
  @State private inputName: string = '';
  @State private inputCategory: ExpenseCategory = ExpenseCategory.TICKET;
  private segments: SegmentedItem[] = [{ label: '预算' }, { label: '实际' }];
  private trip: Trip | null = null;

  aboutToAppear(): void {
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
          Logger.info('Ui.Expense', '本机还没有行程，费用页保持空态');
          return;
        }
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
        return Promise.resolve<CategoryTotal[]>([]);
      }
      this.trip = trip;
      this.tripLabel = `${trip.destination} · ${trip.startDate} – ${trip.endDate}`;
      this.budgetTotal = trip.budget * trip.people;
      const span: number = DateUtils.spanDays(trip.startDate, trip.endDate);
      const passed: number = DateUtils.spanDays(trip.startDate, DateUtils.todayIso());
      this.daysLeft = Math.max(0, span - passed);
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

  /** 预算视角按占预算总额、实际视角按占最大分类——同一批真值，两种读法（模型里没有分档预算） */
  private currentCats(): CategorySpend[] {
    let max: number = 0;
    for (const t of this.totals) {
      if (t.amount > max) {
        max = t.amount;
      }
    }
    const base: number = this.seg === 0 ? Math.max(1, this.budgetTotal) : Math.max(1, max);
    return this.totals.map((t: CategoryTotal): CategorySpend => {
      const c: CategorySpend = {
        name: labelOf(t.category),
        amount: t.amount,
        pct: Math.min(100, Math.max(1, Math.round((t.amount / base) * 100))),
        color: colorOf(t.category)
      };
      return c;
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
    Row({ space: SpaceTokens.sm }) {
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

      Text(yuan(cat.amount))
        .fontSize(TypeTokens.caption.size)
        .fontWeight(450)
        .fontColor(ColorTokens.body)
        .fontFeature("'tnum' on")
        .width(72)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })
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
      .margin({ right: SpaceTokens.sm })
      .onClick(() => {
        this.inputCategory = option.value;
      })
  }

  @Builder
  recordSheet() {
    // 键盘弹起会遮住表单一半高度：整块可滚，保存键才够得着
    Scroll() {
      Column() {
      Text('记一笔')
        .fontSize(TypeTokens.title.size)
        .fontWeight(700)
        .fontFamily(TypeTokens.title.family)
        .fontColor(ColorTokens.ink)
        .margin({ top: SpaceTokens.xl })
      Text('金额与名称只存本机行程')
        .fontSize(TypeTokens.small.size)
        .fontColor(ColorTokens.body)
        .margin({ top: SpaceTokens.xs, bottom: SpaceTokens.lg })

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
      TextInput({ placeholder: '名称，如 故宫门票', text: this.inputName })
        .fontSize(TypeTokens.body.size)
        .fontColor(ColorTokens.ink)
        .backgroundColor(ColorTokens.surfacePanel)
        .borderRadius(RadiusTokens.reason)
        .height(LayoutTokens.composeFieldHeight)
        .margin({ top: SpaceTokens.sm })
        .onChange((v: string) => {
          this.inputName = v;
        })

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(CATEGORY_LABELS, (option: CategoryOption) => {
          Column() {
            this.categoryChip(option)
          }
          .margin({ right: SpaceTokens.sm, bottom: SpaceTokens.sm })
        }, (option: CategoryOption): string => `rec-${option.value}-${this.inputCategory === option.value}`)
      }
      .width('100%')
      .margin({ top: SpaceTokens.md })

      YoujingButton({
        variant: YoujingButtonVariant.PRIMARY,
        label: '保存',
        fullWidth: true,
        onAction: (): void => {
          this.saveExpense();
        }
      })
        .margin({ top: SpaceTokens.lg })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, bottom: SpaceTokens.xl })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
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
      .padding({ top: SpaceTokens.lg, bottom: SpaceTokens.sm })
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
    .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })
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
    .padding({ left: SpaceTokens.md, right: SpaceTokens.md })
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

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
      Column() {

        List() {
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
          .margin({ bottom: SpaceTokens.lg })

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
                  .margin({ bottom: SpaceTokens.xs })
              }
              Text(this.seg === 0 ?
                `预算 ${yuan(this.budgetTotal)} · ${this.trip === null ? 0 : this.trip.people} 人 · ` +
                `${this.trip === null ? 0 : this.trip.days.length} 天` :
                `实际 ${yuan(this.spent)} · ${this.trip === null ? 0 : this.trip.people} 人 · ` +
                `${this.trip === null ? 0 : this.trip.days.length} 天`)
                .fontSize(TypeTokens.overline.size)
                .fontWeight(600)
                .fontColor(ColorTokens.muted)
                .fontFeature("'tnum' on")
              Row({ space: SpaceTokens.sm }) {
                Text(yuan(this.spent))
                  .fontSize(TypeTokens.display.size)
                  .fontWeight(700)
                  .fontColor(this.spent > this.budgetTotal ? ColorTokens.danger : ColorTokens.ink)
                  .fontFeature("'tnum' on")
                Text('已花')
                  .fontSize(TypeTokens.caption.size)
                  .fontWeight(450)
                  .fontColor(ColorTokens.muted)
                  .margin({ bottom: SpaceTokens.xs })
              }
              .alignItems(VerticalAlign.Bottom)
              .margin({ top: SpaceTokens.xs })

              Progress({ value: this.spentPct(), total: 100, type: ProgressType.Linear })
                .color(this.spent > this.budgetTotal ? ColorTokens.danger : ColorTokens.primary)
                .width('100%')
                .margin({ top: SpaceTokens.md })

              Text(this.spent > this.budgetTotal ?
                `超支 ${yuan(this.spent - this.budgetTotal)}${this.topCategory.length > 0 ? ` · 主要来自${this.topCategory}` : ''}` :
                `剩 ${yuan(Math.max(0, this.budgetTotal - this.spent))} · 还剩 ${this.daysLeft} 天`)
                .fontSize(TypeTokens.caption.size)
                .fontWeight(450)
                .fontColor(this.spent > this.budgetTotal ? ColorTokens.danger : ColorTokens.body)
                .fontFeature("'tnum' on")
                .margin({ top: SpaceTokens.sm })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding(SpaceTokens.lg)
            .borderRadius(RadiusTokens.hero)
            .backgroundColor(ColorTokens.surfaceElevated)
          }

          ListItemGroup({ header: this.sectionHeader('分类支出') }) {
            if (this.totals.length === 0) {
              ListItem() {
                Text('还没有记账，下面记一笔后这里会出现分类')
                  .fontSize(TypeTokens.caption.size)
                  .fontColor(ColorTokens.muted)
                  .width('100%')
                  .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })
              }
            }
            ForEach(this.currentCats(), (cat: CategorySpend) => {
              ListItem() {
                this.categoryRow(cat)
              }
            }, (cat: CategorySpend): string => `cat-${this.seg}-${cat.name}-${cat.amount}-${cat.pct}`)
          }
          .divider({ strokeWidth: LayoutTokens.hairlineWidth, color: ColorTokens.separator })
          .padding({ left: SpaceTokens.md, right: SpaceTokens.md })
          .backgroundColor(ColorTokens.canvas)
          .borderRadius(RadiusTokens.card)
          .clip(true)
          .margin({ top: SpaceTokens.sm })

          ListItemGroup({ header: this.sectionHeader('最近记账') }) {
            if (this.receipts.length === 0) {
              ListItem() {
                Text('今天还没有记录')
                  .fontSize(TypeTokens.caption.size)
                  .fontColor(ColorTokens.muted)
                  .width('100%')
                  .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })
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
          .padding({ left: SpaceTokens.md, right: SpaceTokens.md })
          .backgroundColor(ColorTokens.canvas)
          .borderRadius(RadiusTokens.card)
          .clip(true)
          .margin({ top: SpaceTokens.sm })

          ListItem() {
            // 记一笔：官方胶囊 Button（原来是 44 高 + 1px 描边的自绘 Pill）
            Button() {
              Row({ space: SpaceTokens.xs }) {
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
          }
          .margin({ top: SpaceTokens.xl })
        }
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .cachedCount(6)
        .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg, bottom: LayoutTokens.bottomScrollReserve })
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ColorTokens.canvas)
      .bindSheet($$this.showRecord, this.recordSheet(), {
        height: '85%',
        backgroundColor: ColorTokens.canvas,
        showClose: true,
        systemMaterial: getSheetImmersiveMaterial()
      })
      FloatingDock({ activeIndex: 2, tripId: this.tripId })
    }
    .width('100%')
    .height('100%')
    }
    .titleBar(HdsChrome.bar({ mainTitle: '费用' }))
    .titleMode(HdsNavDestinationTitleMode.MINI)
  }
}
