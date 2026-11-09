/**
 * dock「地图」落点页（底稿 dock 四项之一，39 帧里没有对应地图帧，v1 按现有设计语言出）。
 *
 * 与屏8 的分工：屏8 面板只看当天，这一页看全程——所以顶部给了「全程 / Day N」切换，
 * 底部给站点条。全程视图按天分段连线（跨天不连，见 MapStops.runs）。
 * 底图铺满、浮层透明穿透（hitTestBehavior Transparent），不遮地图手势。
 */

import { MAP_NAV, TAB_SHOWN_KEY, isTabShownTick, enterPlanningFlow, TAB_MAP } from '../common/constants/AppNav';
import { TripDao, TripSummary } from '../data/TripDao';
import { Trip, TripDay } from '../model/Trip';
import { MapStop, MapStops } from '../utils/MapStops';
import { TripWindow } from '../utils/TripWindow';
import { DateUtils } from '../utils/DateUtils';
import { TripMapView } from '../components/TripMapView';
import { Pressable } from '../components/Pressable';
import { Logger } from '../common/logger/Logger';
import { PlanDraft } from '../data/PlanDraft';
import { common } from '@kit.AbilityKit';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { ShadowTokens } from '../design/ShadowTokens';
import { HdsNavigation, HdsNavigationTitleMode, HdsNavDestination, HdsNavDestinationTitleMode, HideMode } from '@kit.UIDesignKit';
import { routerMap } from './AppRouter';
import type { HdsNavigationMenuItemOptions, HdsNavigationTitleBarOptions } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';
import { TopStrip, STRIP_CANVAS, STRIP_MAP } from '../utils/TopStrip';
import { TripSpan } from '../utils/TripSpan';

const ALL_DAYS: number = -1;
/**
 * 全览留白（px，真机 1136×2690 上量的）：底图满屏，浮层不满屏。
 * 上界 = 分段栏底 487 + 图钉头 ~110；下界 = 站点条顶 2101（2690-2101=589）。
 */
const FIT_TOP_PX: number = 600;
const FIT_BOTTOM_PX: number = 600;
/**
 * dock 底下那条遮罩的三段几何（自下而上）：压在 dock 本体下的 56vp 是实心，
 * 往上 92vp 从透明淡进实心（契约 §1055 给四处玻璃面配的那条 fade），
 * 往下只淡出 21vp 就收手 —— 地图 SDK 自己的「花瓣地图」归属水印顶边实测在
 * y≈826vp（dock 底 804.8 之下 21.2vp），再多压就把水印从 4.84:1 压到 1.23:1，
 * 那是归属声明，不能盖。整块高 169vp、底边离屏底 35vp（= 56 − 21）。
 */
const DOCK_MASK_FADE_VP: number = LayoutTokens.barGradientMaskHeight;
const DOCK_MASK_PLATEAU_VP: number = LayoutTokens.floatingDockBarHeight;
/** 21vp 是按地图 SDK 归属水印顶边实测的，token 里没有对应档，保留具名常量 */
const DOCK_MASK_BELOW_VP: number = 21;
/** 站点卡定宽定高：横向 List 需要确定项宽，168vp 够 14fp 标题单行 */
const STOP_CARD_WIDTH: number = 168;
const STOP_CARD_HEIGHT: number = 72;
const DOCK_MASK_HEIGHT_VP: number = DOCK_MASK_FADE_VP + DOCK_MASK_PLATEAU_VP + DOCK_MASK_BELOW_VP;
/** 实心段起止 = 淡入段占比 / (淡入 + 实心) 占比 */
const MASK_SOLID_FROM: number = DOCK_MASK_FADE_VP / DOCK_MASK_HEIGHT_VP;
const MASK_SOLID_TO: number = (DOCK_MASK_FADE_VP + DOCK_MASK_PLATEAU_VP) / DOCK_MASK_HEIGHT_VP;

@Component
export struct MapPage {
  /** 本页是 MAP_NAV 这条 tab 栈的宿主，push 必须落在自己的栈上 */
  private pathStack: NavPathStack = MAP_NAV;
  /** dock 切回这一页时重取底图数据（广播见 AppNav.TAB_SHOWN_KEY，主链复审 P1） */
  @StorageProp(TAB_SHOWN_KEY) @Watch('onDockShown') dockTick: string = '';

  private onDockShown(): void {
    if (!isTabShownTick(this.dockTick, TAB_MAP)) {
      return;
    }
    // 切回这一格时重新判一次在途行程：可能刚出发、也可能刚结束
    this.tripId = '';
    this.noOnTrip = false;
    this.resolveAndReload();
  }
  @Prop tripId: string = '';
  @State private days: TripDay[] = [];
  /** -1 = 全程 */
  @State private daySel: number = ALL_DAYS;
  @State private stops: MapStop[] = [];
  /** 0 = 无选中；点地图气泡与点站点卡共用这一个状态（双向高亮） */
  @State private selectedStop: number = 0;
  @State private signature: string = '';
  @State private request: string = '';
  @State private titleText: string = '地图';
  @State private loaded: boolean = false;
  /** 根页模式下的判定结果：本机没有在途行程（与"还没加载完"不是一回事，不能共用 loaded） */
  @State private noOnTrip: boolean = false;
  /** 当前展示的就是这趟在途行程 —— 决定标题栏要不要给「旅行中」入口 */
  @State private onTripShown: boolean = false;
  private seq: number = 0;
  /** 站点条滚动器：点地图气泡时把对应站点卡带回视野（切片1 A） */
  private stripScroller: Scroller = new Scroller();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  /**
   * 首帧取数必须挂在这里，不能只靠 onShown：
   * onShown 是 HdsNavDestination 的属性，而本页作为 dock「地图」tab 的根页时走的是
   * rootMode 分支（自带内嵌 HdsNavigation），那条属性根本不参与渲染——
   * 真机实拍就是整块空白、标题只剩「地图」（titleText 没被行程名覆盖）。
   * onShown 保留给「从编辑页/屏8 返回要吃到回写数据」这一路。
   */
  aboutToAppear(): void {
    this.resolveAndReload();
    if (this.rootMode) {
      this.bindStripToStackTop();
    }
  }

  /**
   * 顶部那条带的"蓝灰"只在**地图自己盖在栈顶**时成立。
   *
   * 壳层原来只按页签决定带色（`pages/Index.syncTopStrip`），所以从地图格按栏上的
   * 「旅行中」压进屏15 之后，带子还留在底图蓝灰 56，而屏15 的栏带是画布 18 ——
   * y=106 处撞出一道 Δ38 的缝（2026-11-01 真机实测，见 §5ci 续 80）。
   * 栈顶归谁这件事只有本页的导航栈知道，所以收在这一处：栈空回蓝灰，有页就交还画布。
   */
  private bindStripToStackTop(): void {
    this.pathStack.setInterception({
      willShow: (from: NavDestinationContext | NavBar, to: NavDestinationContext | NavBar,
        op: NavigationOperation, isAnimated: boolean): void => {
        // `to === 'navBar'` 就是"这一跳要回到根视图"（NavBar 是字面量类型 'navBar'）
        const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
        TopStrip.apply(ctx, to === 'navBar' ? STRIP_MAP : STRIP_CANVAS);
      }
    });
  }

  /**
   * 根页（dock「地图」格）挑哪条行程：**只看今天落在日期区间内的那条**。
   *
   * 原来这里读 `activeTripId()`（"最后打开的那条"）：点开一条历史行程去编辑，
   * 切回地图就跟着变成那条历史行程了 —— 而这一格的职责是"看我现在走到哪"。
   * `ACTIVE_TRIP_KEY` 现在只服费用页（记账跟着刚看的那条走才对）。
   * push 形态（带 tripId 参数）不受影响，照旧显示传进来的那条。
   */
  private resolveSeq: number = 0;

  private resolveAndReload(): void {
    if (!this.rootMode || this.tripId.length > 0) {
      this.reload();
      return;
    }
    const mySeq: number = ++this.resolveSeq;
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    TripDao.listSummaries(ctx).then((rows: TripSummary[]): void => {
      if (mySeq !== this.resolveSeq) {
        return;
      }
      const today: string = DateUtils.todayIso();
      for (const r of rows) {
        if (TripWindow.isActiveOn(r.startDate, r.endDate, today)) {
          this.noOnTrip = false;
          this.onTripShown = true;
          this.tripId = r.id;
          this.reload();
          return;
        }
      }
      // 没有在途行程：退到**最近一条**（哪怕已结束），出图 + 站点条，而不是给一张空底图。
      // 2026-11-08 用户报「地图页无图」：原先这里直接置空态，而地图 tab 是唯一入口
      // （route=Map 深链也走这条 rootMode 判断），于是只要有历史行程、当前又不在旅途中，
      // 这一格就永远是一整片白。`reload()` 本来就有「退到最近一条」的兜底，这里不该绕过它。
      if (rows.length > 0) {
        this.onTripShown = false;
        this.noOnTrip = true;
        this.tripId = rows[0].id;
        this.reload();
        return;
      }
      this.onTripShown = false;
      this.noOnTrip = true;
      this.loaded = true;
      Logger.info('Ui.MapPage', '本机没有任何行程，地图页出引导空态');
    }).catch((err: Error): void => {
      if (mySeq !== this.resolveSeq) {
        return;
      }
      this.noOnTrip = true;
      this.loaded = true;
      Logger.warn('Ui.MapPage', `取在途行程失败: ${err.message}`);
    });
  }

  /** 编辑页/屏8 返回后要吃到回写的库数据，统一挂 onShown（首帧也会触发） */
  /** 官方标题栏：行程名 + 副标题步数，「全览」走 content.menu 圆钮 */
  private titleBarOptions(): HdsNavigationTitleBarOptions {
    const items: Array<HdsNavigationMenuItemOptions> = [HdsChrome.item(
      $r('sys.symbol.arrow_2_circlepath'), '全览', (): void => {
        this.fitAll();
      })];
    if (this.onTripShown && this.tripId.length > 0) {
      // 到站检测、打卡、欠站、天气建议都在屏15，地图只做空间呈现——
      // 但既然这一格承诺"看进行中的行程"，就得有一条路走到那屏，不能只给看
      items.push(HdsChrome.item($r('sys.symbol.map_badge_local'), '旅行中', (): void => {
        this.pathStack.pushPath({ name: 'OnTrip', param: this.tripId });
      }));
    }
    const sub: string = this.stops.length > 0 ? `${this.stops.length} 站` : '';
    // 地图格没有纵向滚动正文（满幅底图 + 横向 chip 轨），关特效避免静止态空糊；
    // 收窄也不适用：满幅底图按断点内缩反而是错的（见 INIT_REPORT §5ci 宽屏走查段）
    return HdsChrome.bar({ mainTitle: this.titleText, backSlot: false, subTitle: sub, menu: items, scrollable: false });
  }

  private reload(): void {
    if (this.tripId.length === 0) {
      // 作为 dock「地图」tab 的根页时不走 push 参数，tripId 会是空（rootMode 的必然结果）：
      // 退到本机最近一条行程，而不是给一张空底图。与 ExpensePage 同一兜底口径。
      const ctx0: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      TripDao.listSummaries(ctx0)
        .then((rows: TripSummary[]): void => {
          if (rows.length === 0) {
            this.loaded = true;
            Logger.info('Ui.MapPage', '本机还没有行程，地图页保持空态');
            return;
          }
          this.tripId = rows[0].id;
          this.reload();
        })
        .catch((err: Error): void => {
          this.loaded = true;
          Logger.warn('Ui.MapPage', `取最近行程失败: ${err.message}`);
        });
      return;
    }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    TripDao.loadTrip(ctx, this.tripId).then((trip: Trip | null) => {
      this.loaded = true;
      if (trip === null) {
        return;
      }
      this.days = trip.days;
      this.titleText = `${trip.destination} · ${TripSpan.text(trip.days.length)}`;
      // 在途行程默认停在"今天那一天"而不是全程：用户开地图要的是我现在在哪一段，
      // 全程视图 19 个落点缩在一起反而看不清
      let sel: number = this.daySel;
      if (this.rootMode && this.onTripShown) {
        const today: string = DateUtils.todayIso();
        for (let i = 0; i < trip.days.length; i++) {
          if (trip.days[i].date === today) {
            sel = i;
            break;
          }
        }
      }
      this.applySel(sel);
    }).catch((err: Error) => {
      this.loaded = true;
      Logger.error('Ui.MapPage', `加载行程失败: ${err.message}`);
    });
  }

  private applySel(sel: number): void {
    this.daySel = sel;
    const next: MapStop[] = sel === ALL_DAYS ? MapStops.fromDays(this.days) :
      (this.days.length > 0 ? MapStops.fromDay(this.days[Math.min(sel, this.days.length - 1)]) : []);
    this.stops = next;
    this.selectedStop = 0;
    // 出行方式也进重绘键：坐标不变、transport.mode 改了也要重新算路
    this.signature = MapStops.signature(next) + '|' +
      next.map((s: MapStop): string => s.mode ?? '').join(',');
    this.fitAll();
  }

  private fitAll(): void {
    this.seq += 1;
    this.request = `fit:${this.seq}`;
  }

  private chips(): string[] {
    return MapStops.dayLabels(this.days);
  }

  private focusStop(index: number): void {
    // 气泡与卡片共用这一处：高亮、飞镜头、把卡滚进视野一次做完
    this.selectedStop = index;
    this.seq += 1;
    this.request = `focus:${index}:${this.seq}`;
    // 站点条跟随：点地图气泡时，对应的站点卡可能滚在屏幕外，只飞镜头用户会以为没反应
    const pos: number = this.stops.findIndex((s: MapStop): boolean => s.index === index);
    if (pos >= 0) {
      this.stripScroller.scrollToIndex(pos, true, ScrollAlign.CENTER);
    }
  }

  @Builder
  chipRow(label: string, idx: number) {
    // 契约 `option-chip`：surface-elevated 白面 + ink 16fp + 20vp 方角、未选中无描边。
    // 选中改有据 `brandSolid` 实心底 + onBrand 字（深色档 #0050A0 上白字 7.91:1），
    // 比 tint + 细描边醒目得多；两者都挂 pillFloat 托起影，浮在瓦片上才有边界。
    ListItem() {
      Row() {
        Text(label)
          .fontSize(TypeTokens.body.size)
          .fontWeight(idx === this.daySel + 1 ? 600 : 450)
          .fontColor(idx === this.daySel + 1 ? ColorTokens.onBrand : ColorTokens.ink)
          .fontFeature("'tnum' on")
      }
      .justifyContent(FlexAlign.Center)
      .height(LayoutTokens.minTouchTarget + SpaceTokens.sm)
      .padding({ left: SpaceTokens.base, right: SpaceTokens.base })
      .borderRadius(RadiusTokens.card)
      .backgroundColor(idx === this.daySel + 1 ? ColorTokens.brandSolid : ColorTokens.surfaceElevated)
      .shadow(ShadowTokens.pillFloat)
    }
    .onClick((): void => {
      this.applySel(idx === 0 ? ALL_DAYS : idx - 1);
    })
  }

  @Builder
  stopChip(stop: MapStop) {
    // 卡片定宽 168×72、圆角 20vp、标题提到 14fp：原来 132×56 / 12fp 在真机上
    // 三张卡挤成一条小字带。选中态与地图气泡双向联动，走 tint 底 + ink 字 + 蓝描边。
    ListItem() {
      Column({ space: SpaceTokens.xxs }) {
        Row({ space: SpaceTokens.xxs }) {
          // 编号沿用实心蓝底 + on_primary 数字：深色档 primary 裸字只有 4.03:1，
          // 这样浅 5.57 / 深 5.14 都过 AA（契约 §8）
          Text(`${stop.index}`)
            .fontSize(TypeTokens.overline.size)
            .fontWeight(600)
            .fontColor(ColorTokens.onPrimary)
            .fontFeature("'tnum' on")
            .width(18)
            .height(18)
            .textAlign(TextAlign.Center)
            .borderRadius(RadiusTokens.pill)
            .backgroundColor(ColorTokens.primary)
          Text(stop.subtitle)
            .fontSize(TypeTokens.caption.size)
            .fontWeight(450)
            .fontColor(ColorTokens.muted)
            .fontFeature("'tnum' on")
        }
        Text(stop.title)
          .fontSize(TypeTokens.small.size)
          .fontWeight(600)
          .fontColor(ColorTokens.ink)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .width(STOP_CARD_WIDTH)
      .height(STOP_CARD_HEIGHT)
      .padding({
        left: SpaceTokens.sm, right: SpaceTokens.sm,
        top: SpaceTokens.xs, bottom: SpaceTokens.xs
      })
      .borderRadius(RadiusTokens.card)
      // 白面 + cardAmbient 环境影托起；选中仍 tint + 蓝描边，卡面大不做实心底
      .backgroundColor(stop.index === this.selectedStop ? ColorTokens.primaryTint : ColorTokens.surfaceElevated)
      .border({
        width: stop.index === this.selectedStop ? LayoutTokens.hairlineWidth * 2 : LayoutTokens.hairlineWidth,
        color: stop.index === this.selectedStop ? ColorTokens.primary : ColorTokens.borderSubtle
      })
      .shadow(ShadowTokens.cardAmbient)
    }
    .onClick((): void => {
      this.focusStop(stop.index);
    })
  }

  /** 根页模式：作为 tab 的内容区内联在 TabContent 里（有据路线 B），此时本页自带 HdsNavigation */
  rootMode: boolean = false;

  @Builder
  rootShell() {
      Stack({ alignContent: Alignment.Bottom }) {
        if (this.stops.length > 0) {
          TripMapView({
            stops: this.stops,
            signature: this.signature,
            request: this.request,
            fitTopPx: FIT_TOP_PX,
            fitBottomPx: FIT_BOTTOM_PX,
            // 只有地图页按道路画动线；屏8 小面板、屏5 片区卡仍是直线
            roadRoute: true,
            onStopClick: (index: number): void => {
              this.focusStop(index);
            }
          })
            .width('100%')
            .height('100%')
          // dock 是半透明材质，透的就是这一带的底图 —— 深色档实测底 lum 0.056
          // （画布那侧 0.016），dock 上的页签文字因此从其余四格的 4.39~4.75:1
          // 掉到 3.05:1。契约 §1055 给四处玻璃面都配了这条 fade 遮罩，但它的 alpha
          // 是**按画布调的**（40%），同一节自己写了"背景不再是画布时要重推"——这里就是
          // 那种情况：40% 实测只把选中蓝推到 2.90，80% 到 4.03，90% 到 4.10（平台期），
          // 未选中那几档则从 4.24~4.77 抬到 6.29~6.74 全过。深色取 90% 画布。
          // 浅色不需要：地图格浅档实测 6.00~8.41 本来就全过，故 base 档给全透明，
          // 分档由资源系统承担，代码里不写 if (isDark)。
          Column()
            .width('100%')
            .height(DOCK_MASK_HEIGHT_VP)
            .margin({ bottom: DOCK_MASK_PLATEAU_VP - DOCK_MASK_BELOW_VP })
            .padding({ top: HdsChrome.contentTopInset(this.statusBarHeight) })
            .linearGradient({
              angle: 180,
              colors: [[Color.Transparent, 0],
                [$r('app.color.map_dock_scrim'), MASK_SOLID_FROM],
                [$r('app.color.map_dock_scrim'), MASK_SOLID_TO],
                [Color.Transparent, 1]]
            })
            .hitTestBehavior(HitTestMode.None)
        }

        Column() {
          if (this.days.length > 0) {
            // 与站点条统一走官方 List：原 Scroll+Row 把两枚 chip 居中、右侧留一大片空白
            // （真机 dump：全程 [355,281]、Day 1 [555,281]，轨道宽 1136）。
            // 不套背景板：chip 20vp 方角自带白面/实心底，靠 pillFloat 投影浮起。
            List({ space: SpaceTokens.xxs }) {
              ForEach(this.chips(), (label: string, idx: number) => {
                this.chipRow(label, idx)
              }, (label: string): string => `mapchip-${label}`)
            }
            .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
            .listDirection(Axis.Horizontal)
            .alignListItem(ListItemAlign.Center)
            .scrollBar(BarState.Off)
            .width('100%')
            .height(LayoutTokens.minTouchTarget + SpaceTokens.sm)
            // 不要背景板：只留 chip 按钮浮在底图上（用户 2026-11-09 定）
            // 让开标题栏：内容区从窗口 0 起，不 margin 会落进 106..281 的栏带
            .margin({ top: HdsChrome.contentTopInset(this.statusBarHeight) })
          }

          Blank()

          if (this.stops.length > 0) {
            Column() {
              // 官方 List 才能按序号把某一项滚进视野（scrollToIndex），卡片定宽不用 lanes
              List({ space: SpaceTokens.xs, scroller: this.stripScroller }) {
                ForEach(this.stops, (stop: MapStop) => {
                  this.stopChip(stop)
                }, (stop: MapStop): string => `mapstop-${stop.index}`)
              }
              .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
              .listDirection(Axis.Horizontal)
              .alignListItem(ListItemAlign.Center)
              .scrollBar(BarState.Off)
              .width('100%')
              .height(STOP_CARD_HEIGHT + SpaceTokens.xs)
              .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm })
            }
            .width('100%')
            // 不要背景板：只剩站点卡浮在底图上；dock 净空照旧让位
            .margin({ bottom: LayoutTokens.floatingDockClearance })
          } else {
            // 加载 / 引导空态 / 无坐标三态收成同一张浮起卡：圆角、底色、dock 让位只写一次
            Column() {
              if (!this.loaded) {
                LoadingProgress()
                  .width(36)
                  .height(36)
                  .color(ColorTokens.primary)
              } else if (this.rootMode && this.noOnTrip) {
                Pressable({
                  visualHeight: 36,
                  action: (): void => {
                    PlanDraft.fresh();
                    enterPlanningFlow('TripInput');
                  }
                }) {
                  Text('今天没有在途行程 · 去规划一趟')
                    .fontSize(TypeTokens.small.size)
                    .fontWeight(600)
                    .fontColor(ColorTokens.primary)
                    .height(36)
                    .padding({ left: SpaceTokens.base, right: SpaceTokens.base })
                }
              } else {
                Text(this.tripId.length === 0 ? '先从「行程」页签选一条行程' : '这条行程里没有可显示的坐标')
                  .fontSize(TypeTokens.small.size)
                  .fontColor(ColorTokens.muted)
              }
            }
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .width('100%')
            .constraintSize({ minHeight: LayoutTokens.minTouchTarget + SpaceTokens.sm })
            .padding({ left: SpaceTokens.base, right: SpaceTokens.base,
              top: SpaceTokens.xs, bottom: SpaceTokens.xs })
            .margin({ bottom: LayoutTokens.floatingDockClearance })
            .borderRadius(RadiusTokens.dock)
            .backgroundColor(ColorTokens.surfaceElevated)
            .border({ width: LayoutTokens.hairlineWidth, color: ColorTokens.borderSubtle })
            .shadow(ShadowTokens.floating)
          }

        }
        .width('100%')
        .height('100%')
        // 所有浮层统一左右内缩：用 padding 不用 margin（width('100%') + 横向 margin 会整体右移溢出）
        .padding({ left: SpaceTokens.base, right: SpaceTokens.base })
        .hitTestBehavior(HitTestMode.Transparent)
      }
      .width('100%')
      .height('100%')
      // 有站点时这一层要铺底图基色：栏本身是透明的，露出来的就是这层的底色。
      // 留画布会在顶边切出第二条色差（真机实测：带子 56、栏区 18、底图 62~75）。
      .backgroundColor(this.stops.length > 0 ? $r('app.color.map_strip_base') : ColorTokens.canvas)
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
      .bindToScrollable([this.stripScroller])
      .clip(false)
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(true)
      .titleBar(this.titleBarOptions())
      .navDestination(routerMap)
      .mode(NavigationMode.Stack)
      .width('100%')
      .height('100%')
    } else {
      HdsNavDestination() {
        this.rootShell()
      }
    // 不收栏（2026-11-08）：NavDestination 内容区恒预留 56vp 栏位、收栏后不回收，收起只留一条 175px 白带
    .bindToScrollable([this.stripScroller])
    .clip(false)
      // HDS 深色档这层默认纯黑，透明栏会把它露成一条比画布暗一档的带（成因与实测见 Docs/INIT_REPORT.md §5ci 续 80）
      .backgroundColor(ColorTokens.canvas)
      .titleBar(this.titleBarOptions())
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .onShown((): void => {
        this.reload();
      })
    }
  }
}
