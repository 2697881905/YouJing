/**
 * 屏12 我的行程（帧 f037b5c4）+ 屏12b 空状态（按干净版 7991fe5b 抄，不抄 06190639 的 !important）。
 * 五格导航后它是「行程」格的根页：历史/最近行程的查看与编辑都从这里进，
 * 勋章与退出登录归「我的」格（`MinePage`），标题栏只留 ＋新建。
 * 卡片：place serif 21 / 日期 meta / 动线 5 节点（必去金）/ 三统计 / 状态行+进度。
 * 状态切换由数据驱动（trips 为空即 12b），生产接 RDB 后自动生效。
 * §7 必改已落：booking-badge padding 2→0、card-footer gap 6→4、dock padding 10→8。
 */

import { TRIPS_NAV, enterPlanningFlow, TAB_SHOWN_KEY, isTabShownTick, TAB_ITINERARY, ACTIVE_TRIP_KEY, activeTripId } from '../common/constants/AppNav';
import { ColorTokens } from '../design/ColorTokens';
import { MoneyText } from '../utils/MoneyText';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { ShadowTokens } from '../design/ShadowTokens';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';
import { TripDao, TripSummary } from '../data/TripDao';
import { PlanDraft } from '../data/PlanDraft';
import { DateUtils } from '../utils/DateUtils';
import { TripWindow } from '../utils/TripWindow';
import { AnniversaryTrip, anniversaryText, findAnniversary } from '../utils/TripReview';
import { common } from '@kit.AbilityKit';
import { HdsNavigation, HdsNavigationTitleMode, HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { routerMap } from './AppRouter';
import { HdsChrome } from '../design/HdsChrome';
import { Logger } from '../common/logger/Logger';
import { KEY_CURRENT_BREAKPOINT } from '../utils/breakpointCenter';
import { listLanesForBreakpoint } from '../utils/responsive';
import { WidgetSync } from '../widget/TodayCard';

interface TripCardData {
  id: string;
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
  /** 断点（唯一来源 utils/breakpointCenter.ets）：宽屏下列表并成多栏，不再被整屏拉宽 */
  @StorageProp(KEY_CURRENT_BREAKPOINT) bp: string = 'sm';

  /** 本页是 TRIPS_NAV 这条 tab 栈的宿主，push 必须落在自己的栈上 */
  private pathStack: NavPathStack = TRIPS_NAV;
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
  @State private trips: TripCardData[] = [];
  @State private loading: boolean = true;
  /** 周年横幅：今天月日落在某条跨年历史行程区间内才出现；无命中时两条都为空 */
  @State private anniversaryId: string = '';
  @State private anniversaryLine: string = '';
  /** 官方 Search 的关键词：目的地或日期串命中即保留 */
  @State private keyword: string = '';
  @State private refreshing: boolean = false;

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
          statusLine = '未出发';
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
          id: r.id, place: r.destination,
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

  private visibleTrips(): TripCardData[] {
    const k: string = this.keyword.trim();
    if (k.length === 0) {
      return this.trips;
    }
    return this.trips.filter((t: TripCardData): boolean => t.place.includes(k) || t.dateMeta.includes(k));
  }

  /** 官方行级动作：左滑出删除钮，删除前走系统对话框二次确认（TripDao.deleteTrip 此前无调用方） */
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

  @Builder
  tripCard(t: TripCardData) {
    // 整卡可点是这屏的主导航：官方 Button 承载（裸 Column 没有按压态、读屏也进不去）。
    // 视觉仍由内层 Column 原样承担，Button 只是可点/可聚焦的壳。
    Button({ type: ButtonType.Normal, stateEffect: true }) {
    Column() {
      Row() {
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

      Row() {
        this.statCol(t.spots, '景点', t.muted)
        this.statCol(t.walk, '通勤', t.muted)
        this.statCol(t.bookingNum, '需预约', t.muted)
      }
      .alignItems(VerticalAlign.Top)
      .width('100%')
      .margin({ top: SpaceTokens.sm })

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
          .width('100%')
          // 不给可及名时读屏念的是框架原话「35.000000」（屏4 的进度条真机实测过这条）
          .accessibilityText(`行程进度 ${Math.round(t.progress)}%`)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .margin({ top: SpaceTokens.sm })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(SpaceTokens.sm)
    .borderRadius(RadiusTokens.card)
    // 契约 components.card.backgroundColor = {colors.surface-elevated}。
    // 原来填 canvas：浅色档靠 cardAmbient 投影还分得开卡与底，深色档投影实测不可见
    // （2026-11-03 实拍：全屏 1767/1950 行读数都是 canvas 的 L=18，卡面档 L=30 零命中）
    // ⇒ 卡片在深色下完全没有边界。改回契约档。
    .backgroundColor(ColorTokens.surfaceElevated)
    .shadow(ShadowTokens.cardAmbient)
    }
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .width('100%')
    .padding(0)
    .borderRadius(RadiusTokens.card)
    .accessibilityText(`${t.place} ${t.dateMeta}，${t.statusLine}，` +
      (t.reviewable ? '打开旅行回顾' : '打开行程'))
    .onClick(() => {
      if (t.onTrip) {
        this.pathStack.pushPath({ name: 'OnTrip', param: t.id });
      } else if (t.reviewable) {
        this.pathStack.pushPath({ name: 'Review', param: t.id });
      } else {
        this.pathStack.pushPath({ name: 'Itinerary', param: t.id });
      }
    })
  }

  /** 根页模式：作为 tab 的内容区内联在 TabContent 里（有据路线 B），此时本页自带 HdsNavigation */
  rootMode: boolean = false;

  /** 行后周年：不做推送（通知权限与 AGC 承载层未就绪），只在 App 内露一条回顾入口 */
  @Builder
  anniversaryBanner() {
    Column() {
      Button({ type: ButtonType.Normal, stateEffect: true }) {
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
        .padding(SpaceTokens.sm)
        .borderRadius(RadiusTokens.card)
        .backgroundColor(ColorTokens.primaryTint)
        .alignItems(VerticalAlign.Center)
      }
      .buttonStyle(ButtonStyleMode.TEXTUAL)
      .width('100%')
      .padding(0)
      .borderRadius(RadiusTokens.card)
      .accessibilityText(`${this.anniversaryLine}，打开旅行回顾`)
      .onClick((): void => {
        this.pathStack.pushPath({ name: 'Review', param: this.anniversaryId });
      })
    }
    .width('100%')
    .padding({ left: SpaceTokens.base, right: SpaceTokens.base, top: SpaceTokens.xs })
  }

  @Builder
  rootShell() {
      Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        if (this.trips.length > 0 && this.anniversaryId.length > 0) {
          this.anniversaryBanner()
        }

        // 官方 Search：目的地或日期关键词过滤（此前右上角放大镜是个没有动作的死控件）。
        // 一条行程都没有时不挂搜索框——没有可搜的内容，摆一个输入框只会让人以为坏了
        if (this.trips.length > 0) {
          Search({ value: this.keyword, placeholder: '搜索目的地或日期' })
            .onChange((v: string): void => {
              this.keyword = v;
            })
            .margin({ left: SpaceTokens.base, right: SpaceTokens.base, top: SpaceTokens.xs })
        }

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
              .fontSize(TypeTokens.title.size)
              .fontWeight(700)
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
              ForEach(this.visibleTrips(), (t: TripCardData) => {
                ListItem() {
                  this.tripCard(t)
                }
                .swipeAction({ end: this.deleteAction(t), edgeEffect: SwipeEdgeEffect.Spring })
              // key 只用稳定 id：状态/进度变化靠 @State 重渲染，不带进 key
              }, (t: TripCardData): string => `trip-${t.id}`)
              if (this.visibleTrips().length === 0) {
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
            .edgeEffect(EdgeEffect.Spring)
            .cachedCount(4)
            .onDidScroll((): void => {
              this.syncBarScroll();
            })
            // 这一页的最后一张卡住在浮动 dock 底下，按实测净空让位。
            .padding({ left: SpaceTokens.base, right: SpaceTokens.base, bottom: LayoutTokens.floatingDockClearance })
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
      .backgroundColor(ColorTokens.canvas)
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
      .titleBar(HdsChrome.bar({
        mainTitle: '行程',
        scrolled: this.barScrolled,
        subTitle: this.trips.length > 0 ? `${this.trips.length} 条` : '',
        menu: [HdsChrome.item($r('sys.symbol.plus'), '新建行程', (): void => {
          PlanDraft.fresh();
          enterPlanningFlow('TripInput');
        })]
      }))
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
      .titleBar(HdsChrome.bar({
        mainTitle: '行程',
        scrolled: this.barScrolled,
        subTitle: this.trips.length > 0 ? `${this.trips.length} 条` : '',
        menu: [HdsChrome.item($r('sys.symbol.plus'), '新建行程', (): void => {
          PlanDraft.fresh();
          enterPlanningFlow('TripInput');
        })]
      }))
      .titleMode(HdsNavDestinationTitleMode.MINI)
    }
  }
}
