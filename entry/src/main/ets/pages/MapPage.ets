/**
 * dock「地图」落点页（底稿 dock 四项之一，39 帧里没有对应地图帧，v1 按现有设计语言出）。
 *
 * 与屏8 的分工：屏8 面板只看当天，这一页看全程——所以顶部给了「全程 / Day N」切换，
 * 底部给站点条。全程视图按天分段连线（跨天不连，见 MapStops.runs）。
 * 底图铺满、浮层透明穿透（hitTestBehavior Transparent），不遮地图手势。
 */

import { HOST_NAV, MAP_NAV, TAB_SHOWN_KEY, isTabShownTick, enterPlanningFlow, TAB_MAP } from '../common/constants/AppNav';
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
import { GlassTokens } from '../components/GlassTokens';
import { GlassBlurStyle, HDS_MATERIAL_TYPE_IMMERSIVE, HDS_MATERIAL_LEVEL_EXQUISITE,
  isImmersiveLightSenseSupported } from '../utils/immersiveMaterial';
import { HdsMiniBarButton } from '../components/HdsMiniBarButton';
import { HdsNavigation, HdsNavigationTitleMode, HdsNavDestination, HdsNavDestinationTitleMode, HideMode } from '@kit.UIDesignKit';
import { routerMap } from './AppRouter';
import type { HdsNavigationMenuItemOptions, HdsNavigationTitleBarOptions } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';
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
/**
 * 顶部 chip 定宽定高：玻璃珠由 HdsTabs 浮动栏渲染，宽高必须显式给档。
 * 120×56 那版是照 dock 槽位（64×54）等比放大做的，真机上比标题栏圆钮（44）还高、
 * 两枚就吃掉三分之二轨宽，整条像一排大按钮压在地图上（2026-11-09 用户判「尺寸太大」）。
 * 收到 76×38：只比圆钮矮一点，同屏能露三枚，76 宽也是 16fp 的「Day 10」留 14vp 边后的下限。
 */
const CHIP_BEAD_WIDTH: number = 76;
const CHIP_BEAD_HEIGHT: number = 38;
const DOCK_MASK_HEIGHT_VP: number = DOCK_MASK_FADE_VP + DOCK_MASK_PLATEAU_VP + DOCK_MASK_BELOW_VP;
/** 实心段起止 = 淡入段占比 / (淡入 + 实心) 占比 */
const MASK_SOLID_FROM: number = DOCK_MASK_FADE_VP / DOCK_MASK_HEIGHT_VP;
const MASK_SOLID_TO: number = (DOCK_MASK_FADE_VP + DOCK_MASK_PLATEAU_VP) / DOCK_MASK_HEIGHT_VP;

@Component
export struct MapPage {
  // 深浅档代 tick：翻档时 EntryAbility 自增，@StorageProp 变化带动本页 build 重跑，
  // 把新 tick 传进 HdsChrome.bar → 标题内容换新 ComponentContent 重挂载、按当前档重解色
  // （官方 HdsTitleBar 自绘内容不随配置切换重渲染，真机实证见 HdsChrome.themeTick）
  @StorageProp('chromeThemeTick') chromeThemeTick: number = 0;

  /**
   * 内层 `HdsNavigation` 的绑定。2026-11-11 二级页全屏化后这条栈不再收任何子页
   * （仅承载根页自己的 titleBar）；⚠ 绝不能绑 HOST_NAV——一个 NavPathStack 只能被
   * 一个 Navigation 持有，绑了会把 Index 外层宿主的绑定抢走，二级页就渲染不出来。
   */
  private pathStack: NavPathStack = MAP_NAV;
  /** push/pop 统一走宿主栈：二级页（OnTrip 等）全屏盖住 dock，宿主 Navigation 在 Index */
  private pushStack: NavPathStack = HOST_NAV;
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

  /**
   * 只有「未选中 + 设备支持 HDS 沉浸光感」才出玻璃珠。选中态保留实心底：
   * 玻璃珠是半透明的，当前档必须一眼能抓到。门禁与 dock 玻璃珠同一条
   *（Index.useHdsDock），低版本设备退回自绘磨砂，不会加载即崩。
   */
  private beadOn(idx: number): boolean {
    return idx !== this.daySel + 1 && isImmersiveLightSenseSupported();
  }
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
  }

  /**
   * 顶部条带随「宿主栈栈顶归谁」换色这件事，2026-11-11 二级页全屏化后收进了
   * `Index.aboutToAppear` 的 `HOST_NAV.setInterception`：本页的 push（OnTrip 等）
   * 现在落宿主栈，挂在 MAP_NAV 上的拦截永远等不到回调；且宿主栈跨页签共用，
   * 由 Index 持 currentTab 判定才不会把地图带色错涂到别的页签根上。
   */

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
        this.pushStack.pushPath({ name: 'OnTrip', param: this.tripId });
      }));
    }
    const sub: string = this.stops.length > 0 ? `${this.stops.length} 站` : '';
    // 地图格没有纵向滚动正文（满幅底图 + 横向 chip 轨），关特效避免静止态空糊；
    // 收窄也不适用：满幅底图按断点内缩反而是错的（见 INIT_REPORT §5ci 宽屏走查段）
    return HdsChrome.bar({ themeTick: this.chromeThemeTick, mainTitle: this.titleText, backSlot: false, subTitle: sub, menu: items, scrollable: false });
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
    // 未选中态 = dock 那颗玻璃珠的同款材质（HdsMiniBarButton 的 Row 包 HdsTabs +
    // barFloatingStyle.systemMaterialEffect IMMERSIVE+EXQUISITE，与右上角「全览」圆钮同族）。
    // 这是仓内唯一在内容区**覆盖层**能出真折射光感的通道：组件级 systemMaterial 在覆盖层
    // 不出图（2026-11-09 真机实证：chip 透明到只剩黑字浮在地图上）。顶部日期 chip 与
    // 底部站点卡都用（2026-11-11 站点卡跟进同款）；横滑 List 里的珠靠裁切罩不外溢。
    // 选中态走 chipSolid 中性深灰实心底（用户 2026-11-10 定：不要蓝，深色即可、不是黑色）：
    // 玻璃半透，当前档必须一眼能抓到。字用 onDark（白，两档同值），不再蹭品牌语义。
    // 文字层落在 V1 上下文的 Stack 里，不进 @ComponentV2 的内容槽——那个闭包读不到
    // 本页 @State daySel 的更新（Index.dockSelectionPill 同一条真机结论）。
    ListItem() {
      Stack({ alignContent: Alignment.Center }) {
        if (this.beadOn(idx)) {
          // 玻璃层：内容槽留空，只出材质；折射环与落影都由系统渲染，不再自绘。
          // ⚠️ 必须罩在 pill 形裁切容器里（76×38 + borderRadius(pill) + clip(true)）：
          // HdsTabs 的沉浸材质在**组件自身边界**内铺满渲染，胶囊珠只是画在底板上的 bar——
          // contentPadding=8 时组件 92×54，材质矩形底板每边露出珠外 8vp，在浅色地图上
          // 就是一块淡灰矩形，相邻底板叠压连成整条（2026-11-11 真机逐像素实测：板区
          // x=[珠左-24px, 珠右+24px]，选中 chip 旁正好是亮缺口）。padding=0 时底板=珠形
          // 看不见，但 bar 系统落影零余量被组件底边硬切——两种 padding 是同一枚硬币的
          // 两面，参数层拆不开（SDK 全参数核对过：gradientMask 是底部渐隐遮罩且已传
          // 全透明，barOpacity 只调整体，没有关底板的开关）。裁切罩把珠外的一切裁掉：
          // 材质在珠内原样保留（dock 同款真玻璃），珠外无板无影无硬边。
          // decorationOnly：珠是纯装饰，命中交给文字层/ListItem。
          Stack() {
            HdsMiniBarButton({
              maskColor: '#00ffffff',
              barWidth: CHIP_BEAD_WIDTH,
              barHeight: CHIP_BEAD_HEIGHT,
              contentPadding: SpaceTokens.xs,
              barBottomMargin: SpaceTokens.xs,
              decorationOnly: true,
              materialType: HDS_MATERIAL_TYPE_IMMERSIVE,
              materialLevel: HDS_MATERIAL_LEVEL_EXQUISITE
            }) {
              Column()
            }
          }
          .width(CHIP_BEAD_WIDTH)
          .height(CHIP_BEAD_HEIGHT)
          .borderRadius(RadiusTokens.pill)
          .clip(true)
        } else {
          // 选中态 / 低版本回退：原来的自绘面（实心深灰底或 GlassPanel 同款自绘玻璃）
          Row()
            .width(CHIP_BEAD_WIDTH)
            .height(CHIP_BEAD_HEIGHT)
            // HdsTabs 浮动栏固定胶囊形，选中态也走 pill，两态形状才统一
            .borderRadius(RadiusTokens.pill)
            .backgroundBlurStyle(idx === this.daySel + 1 ? BlurStyle.NONE : GlassBlurStyle.Card)
            .backgroundColor(idx === this.daySel + 1 ? ColorTokens.chipSolid : GlassTokens.PILL_FILL)
            .border({
              width: idx === this.daySel + 1 ? 0 : LayoutTokens.glassBorderWidth,
              color: idx === this.daySel + 1 ? Color.Transparent : GlassTokens.PILL_RIM
            })
            .shadow(ShadowTokens.pillFloat)
        }
        // 文字层：与玻璃同宽同高、居中叠上，尺寸不依赖 HdsTabs 内部布局
        Row() {
          Text(label)
            .fontSize(TypeTokens.body.size)
            .fontWeight(idx === this.daySel + 1 ? 600 : 450)
            .fontColor(idx === this.daySel + 1 ? ColorTokens.onDark : ColorTokens.ink)
            .fontFeature("'tnum' on")
            // 定高 38 的胶囊装不下换行；系统字号放大时也只准单行、超出省略
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .justifyContent(FlexAlign.Center)
        .width(CHIP_BEAD_WIDTH)
        .height(CHIP_BEAD_HEIGHT)
      }
      .width(CHIP_BEAD_WIDTH)
      .height(CHIP_BEAD_HEIGHT)
    }
    // 顶部 8vp 内缩（xs）：玻璃珠恢复 contentPadding=8 后，光效盒（珠 + 四周 8vp）顶边
    // 必须留在 List 视口内，否则上缘又被切一道（见 chipRow HdsMiniBarButton 注释）；
    // 轨道 margin 同时上移 4vp 抵消，chip 落位不变。静息内缩（首末项 16vp，与标题栏
    // x=50px 对齐）挂在这里而不是 List 的 padding：List 的裁切视口按「组件区域 − padding」
    // 算，padding 是来向侧一条隐形切线——2026-11-10 真机实证：滑动中卡片在
    // x=1086px（=1136−50px）被硬切，出场侧却能滑到 x=0。去掉 padding 后裁切线回到
    // 屏幕边缘，chip 左右滑动能穿到最边缘才消失。
    .padding({ top: SpaceTokens.xs })
    .margin({
      left: idx === 0 ? SpaceTokens.base : 0,
      right: idx === this.days.length ? SpaceTokens.base : 0
    })
    .onClick((): void => {
      this.applySel(idx === 0 ? ALL_DAYS : idx - 1);
    })
  }

  @Builder
  stopChip(stop: MapStop, idx: number) {
    // 2026-11-11 用户拍板：站点卡也换玻璃珠（顶部日期 chip 同款，此前一直自绘磨砂）。
    // 未选 = 珠 + pill 裁切罩——HdsTabs 材质矩形底板只在组件边界内渲染、参数层关不掉，
    // 罩必须与 bar 同形（pill），成因与真机逐像素实测见 chipRow 注释。选中 = chipSolid
    // 深灰实心（2026-11-10 口径：不要蓝），文字换 onDark/onDarkDegraded 保对比度。
    // HdsTabs 浮动栏固定胶囊形，两态形状统一走 pill（168×72 胶囊 = 上下圆头卡）；
    // 选中影沿用 pillFloat（同 chipRow），落在轨道 16vp 净空内。
    ListItem() {
      Stack({ alignContent: Alignment.Center }) {
        if (stop.index !== this.selectedStop && isImmersiveLightSenseSupported()) {
          // 玻璃层：内容槽留空只出材质；decorationOnly——多颗珠并排时 contentPadding
          // 放大的不可见容器会盖住邻珠吞点击，命中交给文字层/ListItem
          Stack() {
            HdsMiniBarButton({
              maskColor: '#00ffffff',
              barWidth: STOP_CARD_WIDTH,
              barHeight: STOP_CARD_HEIGHT,
              contentPadding: SpaceTokens.xs,
              barBottomMargin: SpaceTokens.xs,
              decorationOnly: true,
              materialType: HDS_MATERIAL_TYPE_IMMERSIVE,
              materialLevel: HDS_MATERIAL_LEVEL_EXQUISITE
            }) {
              Column()
            }
          }
          .width(STOP_CARD_WIDTH)
          .height(STOP_CARD_HEIGHT)
          .borderRadius(RadiusTokens.pill)
          .clip(true)
        } else {
          // 选中态 / 低版本回退：自绘面（实心深灰底或自绘玻璃）
          Row()
            .width(STOP_CARD_WIDTH)
            .height(STOP_CARD_HEIGHT)
            .borderRadius(RadiusTokens.pill)
            .backgroundBlurStyle(stop.index === this.selectedStop ? BlurStyle.NONE : GlassBlurStyle.Card)
            .backgroundColor(stop.index === this.selectedStop ? ColorTokens.chipSolid : GlassTokens.PILL_FILL)
            .border({
              width: stop.index === this.selectedStop ? 0 : LayoutTokens.glassBorderWidth,
              color: stop.index === this.selectedStop ? Color.Transparent : GlassTokens.PILL_RIM
            })
            .shadow(ShadowTokens.pillFloat)
        }
        // 文字层：与玻璃同宽同高、居中叠上，尺寸不依赖 HdsTabs 内部布局。
        // 横向内缩给 base(16) 而不是原 sm(12)：pill 圆头轮廓在 y=8（徽章顶）处已收进
        // x≈13.4，12 会让编号徽章戳出玻璃边；纵向节奏不动。
        Column({ space: SpaceTokens.xxs }) {
          Row({ space: SpaceTokens.xxs }) {
            // 编号沿用实心蓝底 + on_primary 数字：深色档 primary 裸字只有 4.03:1，
            // 这样浅 5.57 / 深 5.14 都过 AA（契约 §8）；chipSolid 底上蓝徽章依旧可辨
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
              .fontColor(stop.index === this.selectedStop ? ColorTokens.onDarkDegraded : ColorTokens.muted)
              .fontFeature("'tnum' on")
          }
          Text(stop.title)
            .fontSize(TypeTokens.small.size)
            .fontWeight(600)
            .fontColor(stop.index === this.selectedStop ? ColorTokens.onDark : ColorTokens.ink)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .width(STOP_CARD_WIDTH)
        .height(STOP_CARD_HEIGHT)
        .padding({
          left: SpaceTokens.base, right: SpaceTokens.base,
          top: SpaceTokens.xs, bottom: SpaceTokens.xs
        })
      }
      .width(STOP_CARD_WIDTH)
      .height(STOP_CARD_HEIGHT)
    }
    // 顶部 4vp 内缩（xxs）：List 改 alignListItem(Start) + 加高后，把卡片钉回原位——见轨道 height 注释。
    // 首末卡 16vp 内缩挂在项上：同 chipRow，List padding 会变成来向侧 16vp 的隐形切线
    .padding({ top: SpaceTokens.xxs })
    .margin({
      left: idx === 0 ? SpaceTokens.base : 0,
      right: idx === this.stops.length - 1 ? SpaceTokens.base : 0
    })
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
            // 按道路画动线：地图页与屏8 行程详情同开（RoadRouteStore 30min 缓存共享，同段不重复请求）；
            // 屏5 片区卡 route:false 本就不连线
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
            // Start + 项顶 8vp 内缩（见 chipRow padding）：chip 落位与净空修复前逐像素一致
            // （轨道 margin 同时上移 4vp 抵消）。改 Start 是为了把加高的空间全留给投影。
            .alignListItem(ListItemAlign.Start)
            .scrollBar(BarState.Off)
            .width('100%')
            // 轨道高 = 项顶 8 + 本体 38 + 底部净空 24（表达式 38 + xxs + segmentBarShadowRoom）：
            // 底部净空给选中 chip 的 pillFloat 自绘影（下探约 11vp）收尾；玻璃珠材质的落影
            // 由 HdsTabs 在自身光效盒（contentPadding=8）内渲染，不依赖这段净空——
            // 2026-11-11 真机：净空只修 List 时选中 chip 清了、玻璃珠的灰带还在，
            // 截断边界在 HdsMiniBarButton 内部（见 chipRow 注释）。
            // 28 是有据同款口径 segmentBarShadowRoom，「不可减——减了投影截断成硬边」。
            .height(CHIP_BEAD_HEIGHT + SpaceTokens.xxs + LayoutTokens.segmentBarShadowRoom)
            // **不给 List 左右 padding**（见 chipRow 注释）：padding 会变成来向侧 16vp 隐形切线，
            // 静息内缩由首末项 margin 承担；裁切线在屏幕边缘，chip 能穿到最边缘
            // 不要背景板：只留 chip 按钮浮在底图上（用户 2026-11-09 定）
            // 让开标题栏：内容区从窗口 0 起，不 margin 会落进 106..281 的栏带。
            // 上移 4vp（xxs）抵消项顶内缩 xxs→xs（玻璃珠光效盒需要 8vp 顶净空），
            // chip 落位与净空修复前逐像素一致
            .margin({ top: HdsChrome.contentTopInset(this.statusBarHeight) - SpaceTokens.xxs })
          }

          Blank()

          if (this.stops.length > 0) {
            Column() {
              // 官方 List 才能按序号把某一项滚进视野（scrollToIndex），卡片定宽不用 lanes
              List({ space: SpaceTokens.xs, scroller: this.stripScroller }) {
                ForEach(this.stops, (stop: MapStop, idx: number) => {
                  this.stopChip(stop, idx)
                }, (stop: MapStop): string => `mapstop-${stop.index}`)
              }
              .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
              .listDirection(Axis.Horizontal)
              // Start + 项顶 4vp 内缩（见 stopChip padding）：卡片落位与原 Center 版逐像素一致
              .alignListItem(ListItemAlign.Start)
              .scrollBar(BarState.Off)
              .width('100%')
              // 轨道高 = 卡 4vp + 本体 72 + 投影净空 16：选中态 pillFloat（radius 8 + offsetY 3）
              // 下探约 11vp，16 够收尾；未选玻璃珠的材质落影被裁切罩裁掉，不吃这段净空。
              // 高度维持 92 不动——卡片落位与珠化前逐像素一致（2026-11-11）。
              .height(STOP_CARD_HEIGHT + SpaceTokens.xxs + SpaceTokens.base)
              // **不给 List 左右 padding**（见 chipRow 注释）：padding 是来向侧 16vp 隐形切线，
              // 2026-11-10 真机实证滑动中卡片在 x=1086px 被硬切；内缩由首末项 margin 承担后，
              // 裁切线回到屏幕边缘，卡片能一路滑出屏幕，不会在屏幕内被提前裁断
            }
            .width('100%')
            // 不要背景板：只剩站点卡浮在底图上；dock 净空只对根页成立（宿主栈落点全屏无 dock）
            .margin({ bottom: this.rootMode ? LayoutTokens.floatingDockClearance : 0 })
          } else {
            // 内缩只给这一张卡，不放前景 Column（否则会把上面两个 List 的 clip 收窄）
            Column() {
              // 加载 / 引导空态 / 无坐标三态收成同一张浮起卡
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
              .borderRadius(RadiusTokens.dock)
              .backgroundColor(ColorTokens.surfaceElevated)
              .border({ width: LayoutTokens.hairlineWidth, color: ColorTokens.borderSubtle })
              .shadow(ShadowTokens.floating)
            }
            .width('100%')
            .padding({ left: SpaceTokens.base, right: SpaceTokens.base })
            // 同上：dock 净空只对根页成立（宿主栈落点全屏无 dock）
            .margin({ bottom: this.rootMode ? LayoutTokens.floatingDockClearance : 0 })
          }

        }
        .width('100%')
        .height('100%')
        // 这里**不能**给前景加左右 padding：那会把 List 的 clip 边界一起收窄，
        // 站点卡滑到屏幕内 50px 处就被裁掉，看着像「滑不到屏幕外」。
        // 内缩改由各 List 自己的 padding 承担，List 本体保持满屏宽。
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
