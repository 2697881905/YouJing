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
import { Logger } from '../common/logger/Logger';
import { common } from '@kit.AbilityKit';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { ShadowTokens } from '../design/ShadowTokens';
import { HdsNavigation, HdsNavigationTitleMode, HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { routerMap } from './AppRouter';
import type { HdsNavigationMenuItemOptions, HdsNavigationTitleBarOptions } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';

const ALL_DAYS: number = -1;
/**
 * 全览留白（px，真机 1136×2690 上量的）：底图满屏，浮层不满屏。
 * 上界 = 分段栏底 487 + 图钉头 ~110；下界 = 站点条顶 2101（2690-2101=589）。
 */
const FIT_TOP_PX: number = 600;
const FIT_BOTTOM_PX: number = 600;

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
  @StorageProp('isDarkMode') isDark: boolean = false;
  @State private days: TripDay[] = [];
  /** -1 = 全程 */
  @State private daySel: number = ALL_DAYS;
  @State private stops: MapStop[] = [];
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

  /**
   * 首帧取数必须挂在这里，不能只靠 onShown：
   * onShown 是 HdsNavDestination 的属性，而本页作为 dock「地图」tab 的根页时走的是
   * rootMode 分支（自带内嵌 HdsNavigation），那条属性根本不参与渲染——
   * 真机实拍就是整块空白、标题只剩「地图」（titleText 没被行程名覆盖）。
   * onShown 保留给「从编辑页/屏8 返回要吃到回写数据」这一路。
   */
  aboutToAppear(): void {
    this.resolveAndReload();
  }

  /**
   * 根页（dock「地图」格）挑哪条行程：**只看今天落在日期区间内的那条**。
   *
   * 原来这里读 `activeTripId()`（"最后打开的那条"）：点开一条历史行程去编辑，
   * 切回地图就跟着变成那条历史行程了 —— 而这一格的职责是"看我现在走到哪"。
   * `ACTIVE_TRIP_KEY` 现在只服费用页（记账跟着刚看的那条走才对）。
   * push 形态（带 tripId 参数）不受影响，照旧显示传进来的那条。
   */
  private resolveAndReload(): void {
    if (!this.rootMode || this.tripId.length > 0) {
      this.reload();
      return;
    }
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    TripDao.listSummaries(ctx).then((rows: TripSummary[]): void => {
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
      // 没有在途行程：给一张空底图 + 一条能点的出路，不悄悄拿历史行程顶上
      this.onTripShown = false;
      this.noOnTrip = true;
      this.loaded = true;
      Logger.info('Ui.MapPage', '本机没有在途行程，地图页出引导空态');
    }).catch((err: Error): void => {
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
    return HdsChrome.bar({ mainTitle: this.titleText, subTitle: sub, menu: items });
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
      const nights: number = trip.days.length - 1;
      this.titleText = `${trip.destination} · ${trip.days.length}天${nights}晚`;
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
    this.signature = MapStops.signature(next);
    this.fitAll();
  }

  private fitAll(): void {
    this.seq += 1;
    this.request = `fit:${this.seq}`;
  }

  private chips(): string[] {
    const out: string[] = ['全程'];
    for (const d of this.days) {
      out.push(`Day ${d.dayIndex}`);
    }
    return out;
  }

  private focusStop(index: number): void {
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
    // 选中档走 EMPHASIZED 实底：真机上 NORMAL 胶囊表面压在瓦片上与瓦片同色、
    // 显式 backgroundColor 也被样式吃掉（ItineraryPage「全图」钮同一实测口径）。
    // 高度 44 最小命中区，字重随选中切换
    Button(label)
      .fontSize(TypeTokens.caption.size)
      .fontWeight(idx === this.daySel + 1 ? 600 : 450)
      .height(LayoutTokens.minTouchTarget)
      .type(ButtonType.Capsule)
      .buttonStyle(idx === this.daySel + 1 ? ButtonStyleMode.EMPHASIZED : ButtonStyleMode.NORMAL)
      .margin({ right: SpaceTokens.sm })
      .onClick((): void => {
        this.applySel(idx === 0 ? ALL_DAYS : idx - 1);
      })
  }

  @Builder
  stopChip(stop: MapStop) {
    Button() {
      Column() {
        Row({ space: SpaceTokens.xs }) {
          // 编号原来是裸的品牌蓝 11fp 小字：深色档 `primary #0A84FF` 对 `surface_panel`
          // 只有 4.03:1，AA 小字门槛 4.5 过不去（浅色档同一对 4.85 是过的）。
          // 改成实心蓝底 + on_primary 数字——浅色 5.57 / 深色 5.14 都过，
          // 也正好和地图气泡上的编号说同一种话（契约 §8 深色语义色标签即用 on_primary）
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
            .fontSize(TypeTokens.overline.size)
            .fontWeight(450)
            .fontColor(ColorTokens.muted)
            .fontFeature("'tnum' on")
        }
        Text(stop.title)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(500)
          .fontColor(ColorTokens.ink)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
    }
    .width(132)
    .height(56)
    .padding({ left: SpaceTokens.md, right: SpaceTokens.md })
    .type(ButtonType.Normal)
    .borderRadius(RadiusTokens.capsule)
    .buttonStyle(ButtonStyleMode.NORMAL)
    // 卡片间距由 List 的 space 给（原先是 Scroll+Row 时代的 margin），
    // 两边都留会变成 16vp 的间隔
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
            onStopClick: (index: number): void => {
              this.focusStop(index);
            }
          })
            .width('100%')
            .height('100%')
        }

        Column() {
          if (this.days.length > 0) {
            Scroll() {
              Row() {
                ForEach(this.chips(), (label: string, idx: number) => {
                  this.chipRow(label, idx)
                }, (label: string): string => `mapchip-${label}`)
              }
              .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
          }

          Blank()

          if (this.stops.length > 0) {
            Column() {
              // 站点条从 Scroll+Row 换成官方 List：只有 List 能按序号把某一项滚进视野
              // （scrollToIndex），Scroll 得靠手算卡片宽度累加定位，一改样式就错位。
              // 卡片定宽，故用 alignListItem 而不是 lanes（分栏会把 132 宽的卡压成半宽）。
              List({ space: SpaceTokens.sm, scroller: this.stripScroller }) {
                ForEach(this.stops, (stop: MapStop) => {
                  ListItem() {
                    this.stopChip(stop)
                  }
                }, (stop: MapStop): string => `mapstop-${stop.index}`)
              }
              .listDirection(Axis.Horizontal)
              .alignListItem(ListItemAlign.Center)
              .scrollBar(BarState.Off)
              .width('100%')
              .height(64)
              .padding({ left: SpaceTokens.md, right: SpaceTokens.md })
            }
            .width('100%')
            .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })
            // 站点条钉在底部 Stack 上，原来直接坐进 dock 里（实拍「:30-」「和园」被压在
            // dock 背后只露半截）；让它整条浮在 dock 之上
            .margin({ bottom: LayoutTokens.floatingDockClearance })
            .borderRadius({ topLeft: RadiusTokens.hero, topRight: RadiusTokens.hero })
            // 站点条不是契约四处玻璃面之一（顶栏/分段/dock/吸顶日标题，禁令 9）：
            // 原挂 THIN 材质属第五处玻璃。改实色 surface-elevated + hairline 描边，
            // 与深色零阴影口径一致；hitTestBehavior Transparent 让手势穿到地图不变
            .backgroundColor(ColorTokens.surfaceElevated)
            .border({ width: LayoutTokens.hairlineWidth, color: ColorTokens.borderSubtle })
            .shadow(this.isDark ? { radius: 0 } : ShadowTokens.floating)
          } else if (this.loaded) {
            if (this.rootMode && this.noOnTrip) {
              // 「今天没有在途行程」是状态不是错误，说清并给一条出路；
              // 裸 Text 挂 onClick 会被第 8 把尺 R4 判成自绘按钮，这里用官方 Button
              Button({ type: ButtonType.Normal, stateEffect: true }) {
                Text('今天没有在途行程 · 去规划一趟')
                  .fontSize(TypeTokens.caption.size)
                  .fontWeight(600)
                  .fontColor(ColorTokens.primary)
              }
              .height(36)
              .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })
              .backgroundColor(ColorTokens.surfaceElevated)
              .borderRadius(RadiusTokens.pill)
              // 和上面站点条分支同一格净空：这个 Stack 是 alignContent Bottom，
              // 不给净空整颗药丸就坐在 dock 背后（站点条分支 :343 一直有）
              .margin({ bottom: LayoutTokens.floatingDockClearance })
              .onClick((): void => {
                enterPlanningFlow('TripInput');
              })
            } else {
              Text(this.tripId.length === 0 ? '先从「行程」页签选一条行程' : '这条行程里没有可显示的坐标')
                .fontSize(TypeTokens.caption.size)
                .fontColor(ColorTokens.muted)
                .height(36)
                .padding({ left: SpaceTokens.lg, right: SpaceTokens.lg })
                .borderRadius(RadiusTokens.pill)
                .backgroundColor(ColorTokens.surfaceElevated)
                .margin({ bottom: LayoutTokens.floatingDockClearance })
            }
          }

        }
        .width('100%')
        .height('100%')
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
      .titleBar(this.titleBarOptions())
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .onShown((): void => {
        this.reload();
      })
    }
  }
}
