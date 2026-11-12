/**
 * 屏12 我的行程（帧 f037b5c4）+ 屏12b 空状态（按干净版 7991fe5b 抄，不抄 06190639 的 !important）。
 * 五格导航后它是「行程」格的根页：历史/最近行程的查看与编辑都从这里进，
 * 勋章与退出登录归「我的」格（`MinePage`），标题栏只留 ＋新建。
 * 卡片：place serif 21 / 日期 meta / 动线 5 节点（必去金）/ 三统计 / 状态行+进度。
 * 状态切换由数据驱动（trips 为空即 12b），生产接 RDB 后自动生效。
 * §7 必改已落：booking-badge padding 2→0、card-footer gap 6→4、dock padding 10→8。
 * 两区结构（2026-11-10 用户定）：「正在进行的行程」（未出发+旅行中）大卡片置顶，
 * 「历史行程」（已结束）手风琴默认收起置其下——大卡片 hero 圆角 28、地名 display serif，
 * 历史区沿用原卡片；多选/搜索时历史区强制展开，收着就勾不到也看不见。
 * 多选删除：顶栏「多选」进入选择态——卡片点击改勾选、顶栏换 全选/删除/退出，
 * 左滑删除在选择态停用（两套手势不打架）；删除仍走 showAlertDialog 二次确认。
 */

import { HOST_NAV, TRIPS_NAV, enterPlanningFlow, TAB_SHOWN_KEY, isTabShownTick, TAB_ITINERARY, ACTIVE_TRIP_KEY, activeTripId } from '../common/constants/AppNav';
import { BOTTOM_NAV_INSET_KEY } from '../utils/navMode';
import { ColorTokens } from '../design/ColorTokens';
import { MoneyText } from '../utils/MoneyText';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { ShadowTokens } from '../design/ShadowTokens';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';
import { Pressable } from '../components/Pressable';
import { TripDao, TripSummary } from '../data/TripDao';
import { PlanDraft } from '../data/PlanDraft';
import { DateUtils } from '../utils/DateUtils';
import { TripWindow } from '../utils/TripWindow';
import { AnniversaryTrip, anniversaryText, findAnniversary } from '../utils/TripReview';
import { common } from '@kit.AbilityKit';
import { HdsNavigation, HdsNavigationTitleMode, HdsNavDestination, HdsNavDestinationTitleMode, HideMode } from '@kit.UIDesignKit';
import type { HdsNavigationTitleBarOptions } from '@kit.UIDesignKit';
import { routerMap } from './AppRouter';
import { HdsChrome } from '../design/HdsChrome';
import { openItineraryLongTake } from '../utils/longTake/itineraryNav';
import { Logger } from '../common/logger/Logger';
import { KEY_CURRENT_BREAKPOINT } from '../utils/breakpointCenter';
import { listLanesForBreakpoint } from '../utils/responsive';
import { WidgetSync } from '../widget/TodayCard';
import { requestSystemBarRefresh } from '../utils/systemBar';

interface TripCardData {
  id: string;
  /** 排序与分区用的原始日期（ISO 串字典序=日期序） */
  startDate: string;
  endDate: string;
  place: string;
  dateMeta: string;
  spots: string;
  walk: string;
  bookingNum: string;
  bookingBadge: string;
  statusLine: string;
  progress: number;
  /** 进度条的读法标注（§5.14：没有标注时它看着像一条渲染残留的蓝线） */
  progressLabel: string;
  /** 'upcoming' 未出发 / 'onTrip' 旅行中 / 'past' 已结束——三态区分要素（§5.13） */
  phase: string;
  onTrip: boolean;
  /** 已结束且有活动打卡：落点改成回顾 */
  reviewable: boolean;
  muted: boolean;
}

@Component
export struct TripsPage {
  // 深浅档代 tick：翻档时 EntryAbility 自增，@StorageProp 变化带动本页 build 重跑，
  // 把新 tick 传进 HdsChrome.bar → 标题内容换新 ComponentContent 重挂载、按当前档重解色
  // （官方 HdsTitleBar 自绘内容不随配置切换重渲染，真机实证见 HdsChrome.themeTick）
  @StorageProp('chromeThemeTick') chromeThemeTick: number = 0;

  /** 断点（唯一来源 utils/breakpointCenter.ets）：宽屏下列表并成多栏，不再被整屏拉宽 */
  @StorageProp(KEY_CURRENT_BREAKPOINT) bp: string = 'sm';

  /**
   * 内层 `HdsNavigation` 的绑定。2026-11-11 二级页全屏化后这条栈不再收任何子页；
   * ⚠ 绝不能绑 HOST_NAV——会把 Index 外层宿主的绑定抢走，二级页就渲染不出来。
   */
  private pathStack: NavPathStack = TRIPS_NAV;
  /** push 统一走宿主栈：二级页（OnTrip/Review/Itinerary）全屏盖住 dock，宿主 Navigation 在 Index */
  private pushStack: NavPathStack = HOST_NAV;
  /** dock 切回这一页时重取列表：新建/删除行程后切回来不再看到旧那份 */
  @StorageProp(TAB_SHOWN_KEY) @Watch('onDockShown') dockTick: string = '';

  private onDockShown(): void {
    if (isTabShownTick(this.dockTick, TAB_ITINERARY)) {
      this.reload().catch((err: Error) => {
        Logger.warn('Ui.Trips', `切回刷新失败: ${err.message}`);
      });
    }
  }
  /** 顶栏磨砂两态：由**绝对**滚动偏移驱动（每帧增量会被松手回弹的负帧打灭，契约 §Translucency） */
  @State private barScrolled: boolean = false;
  private barScroller: Scroller = new Scroller();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  // 底部避让（手势/三键不同）：末卡净空要加上导航条避让量，否则三键档末卡被 dock 截断
  @StorageProp(BOTTOM_NAV_INSET_KEY) dockNavInset: number = 0;
  @State private trips: TripCardData[] = [];
  @State private loading: boolean = true;
  /** 周年横幅：今天月日落在某条跨年历史行程区间内才出现；无命中时两条都为空 */
  @State private anniversaryId: string = '';
  @State private anniversaryLine: string = '';
  /** 官方 Search 的关键词：目的地或日期串命中即保留 */
  @State private keyword: string = '';
  @State private refreshing: boolean = false;
  /** 多选删除模式：true 时卡片点击改为勾选，顶栏换成 全选/删除/退出（左滑删除停用） */
  @State private selecting: boolean = false;
  /** 已勾选行程 id：只整体换数组（push/splice 不触发 @State 渲染） */
  @State private selectedIds: string[] = [];
  /** 「历史行程」手风琴：默认收起；多选/搜索态强制展开（historyExpanded） */
  @State private historyOpen: boolean = false;

  /** 列表数据只从 RDB 取，刷新动作与首启共用一条路径（Refresh 需要 Promise 收尾） */
  private reload(): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.loading = true;
    return TripDao.listSummaries(ctx).then((rows: TripSummary[]) => {
      const list: TripCardData[] = [];
      const today: string = DateUtils.todayIso();
      const anniversaries: AnniversaryTrip[] = [];
      for (const r of rows) {
        const span: number = DateUtils.spanDays(r.startDate, r.endDate);
        const onTrip: boolean = TripWindow.isActiveOn(r.startDate, r.endDate, today);
        let progress: number = 100;
        let phase: string = 'past';
        let statusLine: string = '已结束';
        let progressLabel: string = '已完成';
        if (today < r.startDate) {
          progress = 0;
          phase = 'upcoming';
          // 大卡片的状态行要回答「什么时候出发」：今天出发已是旅行中，不会出现 0 天
          const countdown: number = DateUtils.spanDays(today, r.startDate) - 1;
          statusLine = countdown > 0 ? `未出发 · 还有 ${countdown} 天出发` : '未出发';
          progressLabel = '未出发 · 0%';
        } else if (onTrip) {
          progress = Math.min(100, Math.round((DateUtils.spanDays(r.startDate, today) / span) * 100));
          phase = 'onTrip';
          statusLine = `旅行中 · 第 ${DateUtils.spanDays(r.startDate, today)} 日`;
          progressLabel = `行程进度 ${progress}%`;
        } else {
          progressLabel = '已结束 · 100%';
        }
        const reviewable: boolean = phase === 'past' && r.checkinCount > 0;
        if (reviewable) {
          progressLabel = '已结束 · 可回顾';
        }
        const t: TripCardData = {
          id: r.id, startDate: r.startDate, endDate: r.endDate, place: r.destination,
          dateMeta: `${r.startDate} – ${r.endDate} · ${span} 天 · ${r.people} 人`,
          spots: `${r.spotCount}`, walk: `${r.legCount} 段`, bookingNum: `${r.bookingCount}`,
          bookingBadge: r.totalCost > 0 ? MoneyText.yuan(r.totalCost) : '',
          statusLine: statusLine, progress: progress, phase: phase, progressLabel: progressLabel,
          onTrip: onTrip, reviewable: reviewable, muted: false
        };
        list.push(t);
        const anniversary: AnniversaryTrip = {
          id: r.id, destination: r.destination, startDate: r.startDate, endDate: r.endDate
        };
        anniversaries.push(anniversary);
      }
      const hit: AnniversaryTrip | null = findAnniversary(anniversaries, today);
      this.anniversaryId = hit === null ? '' : hit.id;
      this.anniversaryLine = hit === null ? '' : anniversaryText(hit, today);
      if (this.selecting) {
        // 选择态下重载（切回/下拉刷新）：列表可能已变，先摘掉悬空的勾选 id
        const alive: Set<string> = new Set<string>(list.map((t: TripCardData): string => t.id));
        this.selectedIds = this.selectedIds.filter((id: string): boolean => alive.has(id));
      }
      this.trips = list;
      this.loading = false;
    }).catch((err: Error) => {
      this.loading = false;
      Logger.error('Ui.Trips', `行程列表加载失败: ${err.message}`);
      this.getUIContext().getPromptAction().showToast({ message: '行程列表加载失败', duration: 1500 });
    });
  }

  aboutToAppear(): void {
    this.reload().catch((err: Error) => {
      Logger.error('Ui.Trips', `行程列表加载失败: ${err.message}`);
    });
  }

  private matchesKeyword(t: TripCardData): boolean {
    const k: string = this.keyword.trim();
    return k.length === 0 || t.place.includes(k) || t.dateMeta.includes(k);
  }

  /** 「正在进行的行程」：未出发 + 旅行中（今天还在行程区间里的活行程），越早出发越靠前 */
  private visibleActive(): TripCardData[] {
    return this.trips
      .filter((t: TripCardData): boolean =>
        (t.phase === 'upcoming' || t.phase === 'onTrip') && this.matchesKeyword(t))
      .sort((a: TripCardData, b: TripCardData): number => a.startDate.localeCompare(b.startDate));
  }

  /** 「历史行程」：已结束，最近结束的在前 */
  private visibleHistory(): TripCardData[] {
    return this.trips
      .filter((t: TripCardData): boolean => t.phase === 'past' && this.matchesKeyword(t))
      .sort((a: TripCardData, b: TripCardData): number => b.endDate.localeCompare(a.endDate));
  }

  /** 搜索/全选作用域 = 两区并集 */
  private allVisible(): TripCardData[] {
    return this.visibleActive().concat(this.visibleHistory());
  }

  /** 历史区展开判定：手风琴默认收起；多选要勾历史、搜索要看见命中，两种状态强制展开 */
  private historyExpanded(): boolean {
    return this.historyOpen || this.selecting || this.keyword.trim().length > 0;
  }

  /** 卡片点击的统一去处（选择态除外）：在途→在途页、可回顾→回顾、其余→一镜到底详情 */
  private openTrip(t: TripCardData): void {
    if (this.selecting) {
      this.toggleSelected(t.id);
      return;
    }
    if (t.onTrip) {
      this.pushStack.pushPath({ name: 'OnTrip', param: t.id });
    } else if (t.reviewable) {
      this.pushStack.pushPath({ name: 'Review', param: t.id });
    } else {
      // 一镜到底：量卡片帧 + 截图后推详情；量不到帧也直推（点击绝不吞）
      openItineraryLongTake(this.getUIContext(), this.pushStack, t.id,
        'trip-card-' + t.id, RadiusTokens.card);
    }
  }

  /** 选择态的勾选圈：占位在最左，卡片点击语义从「打开」换成「勾选」 */
  @Builder
  selectCircle(t: TripCardData) {
    if (this.selecting) {
      SymbolGlyph(this.isSelected(t.id) ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
        .fontSize(IconSizes.control)
        .fontColor([this.isSelected(t.id) ? ColorTokens.primary : ColorTokens.icon])
        .margin({ right: SpaceTokens.sm })
    }
  }

  @Builder
  statRow(t: TripCardData) {
    Row() {
      this.statCol(t.spots, '景点', t.muted)
      this.statCol(t.walk, '通勤', t.muted)
      this.statCol(t.bookingNum, '需预约', t.muted)
    }
    .alignItems(VerticalAlign.Top)
    .width('100%')
    .margin({ top: SpaceTokens.sm })
  }

  @Builder
  progressBlock(t: TripCardData) {
    Column({ space: SpaceTokens.xxs }) {
      Row() {
        // 状态只说一次：此前「已结束」和「已结束 · 100%」上下各印一遍
        Text(t.progressLabel)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(t.phase === 'onTrip' ? ColorTokens.primary : ColorTokens.muted)
          .fontFeature("'tnum' on")
          .layoutWeight(1)
        // 金额此前贴在「需预约」的数字旁边，实拍读成了「5¥1540 需预约」；
        // 上一版把它做成第四格统计，钉宽屏断点复拍时四格在窄列里整个竖排、
        // ¥1540 拆成三行——四格太脆，改成末行右端一个带标签的稳定落点
        if (t.bookingBadge.length > 0) {
          Text(`总花费 ${t.bookingBadge}`)
            .fontSize(TypeTokens.caption.size)
            .fontWeight(600)
            .fontColor(ColorTokens.ink)
            .fontFeature("'tnum' on")
            .margin({ left: SpaceTokens.xs })
        }
      }
      .alignItems(VerticalAlign.Center)
      .width('100%')

      Progress({ value: t.progress, total: 100, type: ProgressType.Linear })
        // 只有「旅行中」用品牌蓝；未出发/已结束退到分隔色，
        // 否则一列表全是同一条蓝线，读起来就是渲染残留（§5.14）
        .color(t.phase === 'onTrip' ? ColorTokens.primary : ColorTokens.separator)
        // 未填的那一截同 §5.14：框架默认轨色比卡面亮，整条读起来就是卡里的一条分隔线
        .backgroundColor(ColorTokens.surfaceSunken)
        .width('100%')
        // 不给可及名时读屏念的是框架原话「35.000000」（屏4 的进度条真机实测过这条）
        .accessibilityText(`行程进度 ${Math.round(t.progress)}%`)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .margin({ top: SpaceTokens.sm })
  }

  /** 历史行程卡（也用于搜索命中的普通卡）：21 serif 地名 + 日期 + 三统计 + 进度 */
  @Builder
  tripCard(t: TripCardData) {
    // 整卡可点是这屏的主导航：按压反馈交给家族唯一的 Pressable
    // （opacity 0.92 + scale 0.97 / 140ms）；视觉仍由内层 Column 原样承担。
    Pressable({
      fillWidth: true,
      action: (): void => {
        this.openTrip(t);
      }
    }) {
    Column() {
      Row() {
        this.selectCircle(t)
        Text(t.place)
          .fontSize(TypeTokens.title.size)
          .fontWeight(700)
          .fontFamily(TypeTokens.title.family)
          .fontColor(ColorTokens.ink)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        this.phaseChip(t.phase)
      }
      .alignItems(VerticalAlign.Center)
      .width('100%')

      Text(t.dateMeta)
        .fontSize(TypeTokens.caption.size)
        .fontWeight(450)
        .fontColor(ColorTokens.muted)
        .fontFeature("'tnum' on")
        .margin({ top: SpaceTokens.xxs })

      this.statRow(t)
      this.progressBlock(t)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(SpaceTokens.base)
    .borderRadius(RadiusTokens.card)
    // 契约 components.card.backgroundColor = {colors.surface-elevated}。
    // 原来填 canvas：浅色档靠 cardAmbient 投影还分得开卡与底，深色档投影实测不可见
    // （2026-11-03 实拍：全屏 1767/1950 行读数都是 canvas 的 L=18，卡面档 L=30 零命中）
    // ⇒ 卡片在深色下完全没有边界。改回契约档。
    .backgroundColor(ColorTokens.surfaceElevated)
    .shadow(ShadowTokens.cardAmbient)
    .accessibilityText(this.selecting
      ? `${t.place} ${t.dateMeta}，${this.isSelected(t.id) ? '已选中' : '未选中'}，点按切换选中`
      : `${t.place} ${t.dateMeta}，${t.statusLine}，` +
      (t.reviewable ? '打开旅行回顾' : '打开行程'))
    .id('trip-card-' + t.id)
    }
  }

  /** 「正在进行」大卡片：display serif 地名 + 状态行（第 N 日/倒计时）+ 同款统计与进度；
   *  hero 圆角 28、内缩 lg 与历史卡（card 20/base）拉开一档体量 */
  @Builder
  activeCard(t: TripCardData) {
    Pressable({
      fillWidth: true,
      action: (): void => {
        this.openTrip(t);
      }
    }) {
    Column({ space: SpaceTokens.sm }) {
      Row() {
        this.selectCircle(t)
        Text(t.place)
          .fontSize(TypeTokens.display.size)
          .fontWeight(TypeTokens.display.weight)
          .fontFamily(TypeTokens.display.family)
          .lineHeight(TypeTokens.display.lineHeight)
          .fontColor(ColorTokens.ink)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        this.phaseChip(t.phase)
      }
      .alignItems(VerticalAlign.Center)
      .width('100%')

      // 状态行是这屏的叙事主句：旅行中报「第 N 日」、未出发报倒计时（reload 生成）
      Text(t.statusLine)
        .fontSize(TypeTokens.small.size)
        .fontWeight(600)
        .fontColor(t.phase === 'onTrip' ? ColorTokens.primary : ColorTokens.body)
        .fontFeature("'tnum' on")

      Text(t.dateMeta)
        .fontSize(TypeTokens.caption.size)
        .fontWeight(450)
        .fontColor(ColorTokens.muted)
        .fontFeature("'tnum' on")

      this.statRow(t)
      this.progressBlock(t)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(SpaceTokens.lg)
    .borderRadius(RadiusTokens.hero)
    .backgroundColor(ColorTokens.surfaceElevated)
    .shadow(ShadowTokens.cardAmbient)
    .accessibilityText(this.selecting
      ? `${t.place} ${t.dateMeta}，${this.isSelected(t.id) ? '已选中' : '未选中'}，点按切换选中`
      : `${t.place} ${t.dateMeta}，${t.statusLine}，` +
      (t.reviewable ? '打开旅行回顾' : '打开行程'))
    .id('trip-card-' + t.id)
    }
  }
  @Builder
  deleteAction(t: TripCardData) {
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
      .accessibilityText(`删除 ${t.place} 的行程`)
      .id('trip-del')
      .onClick((): void => {
        this.confirmDelete(t);
      })
    }
    .justifyContent(FlexAlign.End)
    .alignItems(VerticalAlign.Center)
    .width(84)
    .height('100%')
    .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm })
  }

  private confirmDelete(t: TripCardData): void {
    this.getUIContext().showAlertDialog({
      title: '删除这条行程',
      message: `${t.place} · ${t.dateMeta}\n只删本机记录，不可恢复；日历里已写入的事件不会自动删除。`,
      primaryButton: {
        value: '取消',
        action: (): void => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: ColorTokens.danger,
        action: (): void => {
          this.doDelete(t.id);
        }
      }
    });
  }

  private doDelete(id: string): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    TripDao.deleteTrip(ctx, id).then((): void => {
      // 行程上下文只服费用格，它认「最后打开的那条」。删掉的正是那条的话不清掉，
      // 费用格会拿着一个已不存在的 id 去 loadTrip。
      if (activeTripId() === id) {
        AppStorage.setOrCreate(ACTIVE_TRIP_KEY, '');
      }
      this.getUIContext().getPromptAction().showToast({ message: '已删除该行程' });
      this.reload().catch((err: Error): void => {
        Logger.error('Ui.Trips', `删除后重载失败: ${err.message}`);
      });
      WidgetSync.refreshAll(ctx).catch((err: Error): void => {
        Logger.warn('Ui.Trips', `卡片刷新失败: ${err.message}`);
      });
    }).catch((err: Error): void => {
      Logger.error('Ui.Trips', `删除行程失败: ${err.message}`);
      this.getUIContext().getPromptAction().showToast({ message: '删除失败，详见日志' });
    });
  }

  // —— 多选删除：进模式后点卡片即勾选，顶栏接管 全选/删除/退出 ——

  private isSelected(id: string): boolean {
    return this.selectedIds.includes(id);
  }

  private toggleSelected(id: string): void {
    if (this.isSelected(id)) {
      this.selectedIds = this.selectedIds.filter((x: string): boolean => x !== id);
    } else {
      this.selectedIds = this.selectedIds.concat(id);
    }
  }

  private isAllVisibleSelected(): boolean {
    const vis: TripCardData[] = this.allVisible();
    return vis.length > 0 && vis.every((t: TripCardData): boolean => this.isSelected(t.id));
  }

  /** 全选只圈搜索过滤后的可见项（两区并集）；取消也只摘可见项，被滤掉的勾选原样保留 */
  private toggleSelectAll(): void {
    const vis: TripCardData[] = this.allVisible();
    if (this.isAllVisibleSelected()) {
      this.selectedIds = this.selectedIds.filter((id: string): boolean =>
        !vis.some((t: TripCardData): boolean => t.id === id));
    } else {
      this.selectedIds = vis.map((t: TripCardData): string => t.id);
    }
  }

  private exitSelecting(): void {
    this.selecting = false;
    this.selectedIds = [];
  }

  private confirmDeleteSelected(): void {
    const n: number = this.selectedIds.length;
    if (n === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '先勾选要删除的行程', duration: 1500 });
      return;
    }
    this.getUIContext().showAlertDialog({
      title: `删除 ${n} 条行程`,
      message: '只删本机记录，不可恢复；日历里已写入的事件不会自动删除。',
      primaryButton: {
        value: '取消',
        action: (): void => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: ColorTokens.danger,
        action: (): void => {
          this.doDeleteSelected();
        }
      }
    });
  }

  private doDeleteSelected(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const ids: string[] = this.selectedIds.slice();
    if (ids.length === 0) {
      return;
    }
    // TripDao 一次只删一条：串行落库，避免并发写同一 RDB 句柄。
    // **一条失败不能吞掉整批的收尾**：原来 catch 里只弹一句「删除失败」，
    // 于是前面几条已经落库删掉的行程继续显示在列表上（点进去是空数据），
    // 选择态也不退出——用户看到的是一屏删不掉的幽灵卡。现在记下真正删成功的 id，
    // 收尾（清 activeTripId / 退选择态 / 重载 / 刷卡片）无论成败都跑一遍。
    const done: string[] = [];
    let chain: Promise<void> = Promise.resolve();
    for (const id of ids) {
      chain = chain.then((): Promise<void> => TripDao.deleteTrip(ctx, id).then((): void => {
        done.push(id);
      }));
    }
    chain.catch((err: Error): void => {
      Logger.error('Ui.Trips', `批量删除行程失败: ${err.message}`);
    }).then((): void => {
      // 费用格认「最后打开的那条」：只有它真的被删掉才清（与单删 doDelete 同一条规则）
      if (done.includes(activeTripId())) {
        AppStorage.setOrCreate(ACTIVE_TRIP_KEY, '');
      }
      this.exitSelecting();
      const failed: number = ids.length - done.length;
      this.getUIContext().getPromptAction().showToast({
        message: failed === 0 ? `已删除 ${done.length} 条行程`
          : `已删除 ${done.length} 条，${failed} 条没删掉，可重试`,
        duration: failed === 0 ? 2000 : 3000
      });
      this.reload().catch((err: Error): void => {
        Logger.error('Ui.Trips', `删除后重载失败: ${err.message}`);
      });
      WidgetSync.refreshAll(ctx).catch((err: Error): void => {
        Logger.warn('Ui.Trips', `卡片刷新失败: ${err.message}`);
      });
    });
  }

  /** 顶栏两态：浏览态＝新建+多选入口；选择态＝全选/删除/退出（随状态整条重建） */
  private titleBar(): HdsNavigationTitleBarOptions {
    if (this.selecting) {
      const n: number = this.selectedIds.length;
      const allSel: boolean = this.isAllVisibleSelected();
      return HdsChrome.bar({ themeTick: this.chromeThemeTick,
        mainTitle: n > 0 ? `已选 ${n} 条` : '选择行程',
        backSlot: false,
        scrolled: this.barScrolled,
        subTitle: this.trips.length > 0 ? `${this.trips.length} 条` : '',
        menu: [
          HdsChrome.item(allSel ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.checkmark'),
            allSel ? '取消全选' : '全选', (): void => {
            this.toggleSelectAll();
          }),
          HdsChrome.item($r('sys.symbol.trash'), '删除', (): void => {
            this.confirmDeleteSelected();
          }),
          HdsChrome.item($r('sys.symbol.xmark'), '退出多选', (): void => {
            this.exitSelecting();
          })
        ]
      });
    }
    return HdsChrome.bar({ themeTick: this.chromeThemeTick,
      mainTitle: '行程',
      backSlot: false,
      scrolled: this.barScrolled,
      subTitle: this.trips.length > 0 ? `${this.trips.length} 条` : '',
      menu: [
        HdsChrome.item($r('sys.symbol.plus'), '新建行程', (): void => {
          PlanDraft.fresh();
          enterPlanningFlow('TripInput');
        }),
        HdsChrome.item($r('sys.symbol.checkmark_circle'), '多选', (): void => {
          this.selecting = true;
        })
      ]
    });
  }

  @Builder
  phaseChip(phase: string) {
    // 三态各一档底色：一屏里过去/未出发/在途的卡长得一样，扫读就分不出主次（§5.13）
    Text(phase === 'onTrip' ? '旅行中' : (phase === 'upcoming' ? '未出发' : '已结束'))
      .fontSize(TypeTokens.overline.size)
      .fontWeight(600)
      .fontColor(phase === 'onTrip' ? ColorTokens.onPrimary :
        (phase === 'upcoming' ? ColorTokens.body : ColorTokens.muted))
      .height(20)
      .padding({ left: SpaceTokens.xs, right: SpaceTokens.xs })
      .borderRadius(RadiusTokens.pill)
      .backgroundColor(phase === 'onTrip' ? ColorTokens.primary :
        (phase === 'upcoming' ? ColorTokens.primaryTint : ColorTokens.surfaceSubtle))
  }

  @Builder
  statCol(value: string, label: string, muted: boolean) {
    Column({ space: SpaceTokens.xxs }) {
      Text(value)
        .fontSize(TypeTokens.headline.size)
        .fontWeight(600)
        .fontColor(muted ? ColorTokens.muted : ColorTokens.ink)
        .fontFeature("'tnum' on")
      Text(label)
        .fontSize(TypeTokens.overline.size)
        .fontWeight(450)
        .fontColor(ColorTokens.muted)
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  /** 根页模式：作为 tab 的内容区内联在 TabContent 里（有据路线 B），此时本页自带 HdsNavigation */
  rootMode: boolean = false;

  /** 行后周年：不做推送（通知权限与 AGC 承载层未就绪），只在 App 内露一条回顾入口 */
  @Builder
  anniversaryBanner() {
    Column() {
      Pressable({
        fillWidth: true,
        action: (): void => {
          this.pushStack.pushPath({ name: 'Review', param: this.anniversaryId });
        }
      }) {
        Row({ space: SpaceTokens.sm }) {
          SymbolGlyph($r('sys.symbol.medal'))
            .fontSize(IconSizes.control)
            .fontColor([ColorTokens.primary])
          Column({ space: SpaceTokens.xxs }) {
            Text(this.anniversaryLine)
              .fontSize(TypeTokens.small.size)
              .fontWeight(600)
              .fontColor(ColorTokens.ink)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text('点开看看那趟旅程的回顾')
              .fontSize(TypeTokens.caption.size)
              .fontWeight(450)
              .fontColor(ColorTokens.muted)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(IconSizes.control)
            .fontColor([ColorTokens.icon])
        }
        .width('100%')
        .padding(SpaceTokens.base)
        .borderRadius(RadiusTokens.card)
        .backgroundColor(ColorTokens.primaryTint)
        .alignItems(VerticalAlign.Center)
        .accessibilityText(`${this.anniversaryLine}，打开旅行回顾`)
      }
    }
    .width('100%')
    // 水平内缩已由宿主 List 的左右 padding 提供（2026-11-08 移进列表后去掉重复内缩）
    .padding({ top: SpaceTokens.xs })
  }

  /** 小节标题：区名 + 数量（不做成卡，节标题要轻） */
  @Builder
  sectionTitle(label: string, count: number) {
    Row({ space: SpaceTokens.xs }) {
      Text(label)
        .fontSize(TypeTokens.headline.size)
        .fontWeight(TypeTokens.headline.weight)
        .fontColor(ColorTokens.ink)
      Text(`${count} 条`)
        .fontSize(TypeTokens.caption.size)
        .fontWeight(450)
        .fontColor(ColorTokens.muted)
        .fontFeature("'tnum' on")
    }
    .alignItems(VerticalAlign.Center)
    .width('100%')
    .padding({ top: SpaceTokens.xs, bottom: SpaceTokens.xxs })
    .accessibilityText(`${label}，${count} 条`)
  }

  /** 进行中区空态：全空状态走上面的 12b 分支，这里只处理「有历史没进行中」的页面 */
  @Builder
  activeEmptyRow() {
    Text('暂无进行中的行程，规划好出发后会出现在这里')
      .fontSize(TypeTokens.small.size)
      .fontColor(ColorTokens.muted)
      .width('100%')
      .padding({ top: SpaceTokens.xs, bottom: SpaceTokens.xs })
  }

  /** 「历史行程」手风琴头：默认收起，整行可点展开/收起（多选与搜索态强制展开时箭头指向会跟着走） */
  @Builder
  historyHeader(count: number) {
    Pressable({
      fillWidth: true,
      action: (): void => {
        this.historyOpen = !this.historyOpen;
      }
    }) {
    Row({ space: SpaceTokens.xs }) {
      Text('历史行程')
        .fontSize(TypeTokens.headline.size)
        .fontWeight(TypeTokens.headline.weight)
        .fontColor(ColorTokens.ink)
      Text(`${count} 条`)
        .fontSize(TypeTokens.caption.size)
        .fontWeight(450)
        .fontColor(ColorTokens.muted)
        .fontFeature("'tnum' on")
      Blank()
      SymbolGlyph(this.historyExpanded() ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
        .fontSize(IconSizes.control)
        .fontColor([ColorTokens.icon])
    }
    .alignItems(VerticalAlign.Center)
    .width('100%')
    .padding({ top: SpaceTokens.base, bottom: SpaceTokens.base })
    .accessibilityText(`历史行程，${count} 条，${this.historyExpanded() ? '点按收起' : '点按展开'}`)
    .id('history-header')
    }
  }

  @Builder
  rootShell() {
      Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        // ⚠ 2026-11-08 对标有据：周年横幅与搜索框原先钉在这里（常驻头部），
        // 使列表视口被挤到它们之下、内容永远进不了标题栏那 175px。
        // 现在两者作为 List 的头两项，随列表一起滚走 —— 与有据 ProfilePage
        // 「资料卡是列表第 0 项」同一结构。

        if (this.loading) {
          Column() {
            LoadingProgress()
              .width(48)
              .height(48)
              .color(ColorTokens.primary)
            Text('正在加载行程…')
              .fontSize(TypeTokens.caption.size)
              .fontColor(ColorTokens.muted)
              .margin({ top: SpaceTokens.sm })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.trips.length === 0) {
          // 帧 7991fe5b 的空状态间距是逐段的（图标 16 / 标题 8 / 说明 24），
          // 不是一条均等 gap；说明限宽 240 才能落回稿件的标准双行折行。
          Column() {
            SymbolGlyph($r('sys.symbol.map'))
              .fontSize(IconSizes.display)
              .fontColor([ColorTokens.muted])
              .margin({ bottom: SpaceTokens.base })
            Text('还没有行程')
              .fontSize(TypeTokens.headline.size)
              .fontWeight(TypeTokens.headline.weight)
              .fontFamily(TypeTokens.title.family)
              .fontColor(ColorTokens.ink)
              .textAlign(TextAlign.Center)
              .margin({ bottom: SpaceTokens.xxs })
            // 屏12b 底稿原句，但**由我们选断行点**：整句交给排版引擎在 240vp 里折，
            // 实拍断成「能直 / 接走的行程」，把「直接」劈成两半
            // （与屏11/屏5 同族，见 INIT_REPORT §5o/§5y）。
            // 两行各自语义完整，字句仍与底稿一致。
            Text('选一座城市，四道题')
              .fontSize(TypeTokens.small.size)
              .fontColor(ColorTokens.body)
              .textAlign(TextAlign.Center)
            Text('就能拿到一份能直接走的行程')
              .fontSize(TypeTokens.small.size)
              .fontColor(ColorTokens.body)
              .textAlign(TextAlign.Center)
              .constraintSize({ maxWidth: 240 })
              .margin({ bottom: SpaceTokens.lg })
            YoujingButton({
              variant: YoujingButtonVariant.PRIMARY,
              label: '规划新行程',
              buttonWidth: 200,
              onAction: (): void => {
                PlanDraft.fresh();
                enterPlanningFlow('TripInput');
              }
            })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          // 官方 Refresh + List：下拉重读 RDB，列表项走 ListItem（原来是 Scroll+Column 手排）
          Refresh({ refreshing: $$this.refreshing }) {
            List({ space: SpaceTokens.sm, scroller: this.barScroller }) {
              // 头部两项：周年横幅 + 搜索框（原为常驻头部，见上方注释）。
              // 水平内缩由 List 自己的左右 padding 提供，这里不再重复加。
              if (!this.selecting && this.anniversaryId.length > 0) {
                ListItem() {
                  this.anniversaryBanner()
                }
              }
              if (this.trips.length > 0) {
                ListItem() {
                  // 官方 Search：目的地或日期关键词过滤（此前右上角放大镜是个没有动作的死控件）。
                  // 一条行程都没有时不挂搜索框——没有可搜的内容，摆一个输入框只会让人以为坏了
                  Search({ value: this.keyword, placeholder: '搜索目的地或日期' })
                    .onChange((v: string): void => {
                      this.keyword = v;
                    })
                    .margin({ top: SpaceTokens.xs })
                }
              }
              // —— 区一：正在进行的行程（未出发+旅行中），大卡片置顶 ——
              ListItem() {
                this.sectionTitle('正在进行的行程', this.visibleActive().length)
              }
              if (this.visibleActive().length === 0) {
                ListItem() {
                  this.activeEmptyRow()
                }
              }
              ForEach(this.visibleActive(), (t: TripCardData) => {
                ListItem() {
                  this.activeCard(t)
                }
                // 选择态不出滑删：勾选手势和左滑在同一张卡上会互相干扰
                .swipeAction(this.selecting
                  ? { edgeEffect: SwipeEdgeEffect.Spring }
                  : { end: this.deleteAction(t), edgeEffect: SwipeEdgeEffect.Spring })
              // key 只用稳定 id：状态/进度变化靠 @State 重渲染，不带进 key
              }, (t: TripCardData): string => `trip-${t.id}`)
              // —— 区二：历史行程，手风琴默认收起置其下 ——
              if (this.visibleHistory().length > 0) {
                ListItem() {
                  this.historyHeader(this.visibleHistory().length)
                }
              }
              if (this.historyExpanded() && this.visibleHistory().length > 0) {
                ForEach(this.visibleHistory(), (t: TripCardData) => {
                  ListItem() {
                    this.tripCard(t)
                  }
                  .swipeAction(this.selecting
                    ? { edgeEffect: SwipeEdgeEffect.Spring }
                    : { end: this.deleteAction(t), edgeEffect: SwipeEdgeEffect.Spring })
                }, (t: TripCardData): string => `trip-${t.id}`)
              }
              if (this.allVisible().length === 0) {
                ListItem() {
                  Text(`没有匹配「${this.keyword}」的行程`)
                    .fontSize(TypeTokens.small.size)
                    .fontColor(ColorTokens.muted)
                    .width('100%')
                    .textAlign(TextAlign.Center)
                    .padding({ top: SpaceTokens.lg, bottom: SpaceTokens.lg })
                }
              }
            }
            .lanes(listLanesForBreakpoint(this.bp))
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
            .cachedCount(4)
            .onDidScroll((): void => {
              this.syncBarScroll();
            })
            // 穿底：末卡要能滚到浮动 dock 下方（透过玻璃可见），不留大净空把卡拦在 dock 上。
            // 只留 base + 导航条避让，内容延伸到屏底、从 dock 下穿过
            .padding({ left: SpaceTokens.base, right: SpaceTokens.base,
              bottom: SpaceTokens.base + this.dockNavInset })
            // 穿底（2026-11-08 对标有据）：让位走 contentStartOffset，不挂 padding ——
            // padding 会把视口压到栏底之下，内容永远进不了标题栏那 175px。
            .contentStartOffset(HdsChrome.contentTopInset(this.statusBarHeight))
          }
          // Refresh / List 不写尺寸时按**父容器**的 100% 高解析，不是「剩下的」高。
          // 上面那条 Search 已经吃掉 48vp，所以整条列表被撑到屏幕外 150px（dump 的
          // origBounds 底是 2840 而窗口底 2690），于是 padding 从看不见的底量起，
          // 末卡永远有 48vp 压在 dock 玻璃下（2026-11-01 真机量，见 §5ci 续 79）。
          // 交给 layoutWeight 拿剩余空间，padding 那 112 才真的落在 dock 顶上。
          .layoutWeight(1)
          .onRefreshing((): void => {
            this.reload().then((): void => {
              this.refreshing = false;
            }).catch((err: Error): void => {
              Logger.error('Ui.Trips', `下拉刷新失败: ${err.message}`);
              this.refreshing = false;
            });
          })
        }
      }
      .width('100%')
      .height('100%')
      .layoutWeight(1)
      // 不涂 canvas：这层涂色会把标题栏区盖成纯白，穿底素材全被挡在下面。
      // 底色由壳层与 TopStrip 单点负责。
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
      if (!on) {
        // 偏移回到 0：HDS 在这一帧回写系统栏内容色，补设通道连发四发压住它（utils/systemBar.ets）
        requestSystemBarRefresh();
      }
    }
  }

  build() {
    if (this.rootMode) {
      HdsNavigation(this.pathStack) {
        this.rootShell()
      }
      // 不收标题栏（2026-11-08 对标有据）：有据根页标题栏常驻——只有 HomeTab 用
      // hideBottomBuilder 收分段那一行，ProfilePage 完全没有 dynamicHideTitleBar。
      // 整条收起后滚动时顶部没有栏体磨砂，穿底内容直接顶到状态栏下，
      // 与有据「栏体把内容糊住」的观感不是一回事。bindToScrollable 保留（驱动渐变模糊）。
      .bindToScrollable([this.barScroller])
      .clip(false)
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(true)
      // 一镜到底挂钩 2026-11-11 移到 Index 的外层 Navigation（Itinerary 改落宿主栈，
      // 转场回调必须挂在持有该栈的那层；这条内层的已等不到任何 push，摘除）。
      .titleBar(this.titleBar())
      .navDestination(routerMap)
      .mode(NavigationMode.Stack)
      .width('100%')
      .height('100%')
    } else {
      HdsNavDestination() {
        this.rootShell()
      }
    // 不收栏（2026-11-08）：NavDestination 内容区恒预留 56vp 栏位、收栏后不回收，收起只留一条 175px 白带
    .bindToScrollable([this.barScroller])
    .clip(false)
      // HDS 深色档这层默认纯黑，透明栏会把它露成一条比画布暗一档的带（成因与实测见 Docs/INIT_REPORT.md §5ci 续 80）
      .backgroundColor(ColorTokens.canvas)
      .titleBar(this.titleBar())
      .titleMode(HdsNavDestinationTitleMode.MINI)
    }
  }
}
