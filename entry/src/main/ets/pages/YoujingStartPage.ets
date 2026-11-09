/**
 * 屏1 首启与静默登录（帧 77ed8d08）——五格导航后它是「规划」格的根页。
 * 2026-11-03 主功能页化（对齐「有据」家族契约 v2）：
 * - 标题栏交还官方 HdsChrome，本页不再自绘品牌块（字牌 + 英文 overline + 标语是首启门面的残留，
 *   不是工作台形态）。2026-11-05 起这条 `HdsNavigation(APP_NAV)` 由**本页自己**挂（以前挂在
 *   Index 壳层里，滚动状态只能经 AppStorage 递一层，是五格里唯一的异形）。
 * - 内容按「出发页」重排（2026-11-08 重构）：页题**提出问题**（display serif，第二行品牌蓝，
 *   整页唯一高饱和文字）→ 主入口卡（整页唯一的重心：写清「点下去会发生什么」）
 *   → 「上次的痕迹」草稿/最近一趟**二选一**行卡 → 示例入口压成一行，
 *   点开半模态看全貌。示例数据不再占版面——它只是三级内容，不能与用户的行程同级同重。
 * - 示例半模态照 ExpensePage「记一笔」同款 bindSheet：systemMaterial 唯一材质载体，
 *   sheet 内容不包 ImmersiveSurface、不涂实色底（双表面禁则）；「还开着」标志只由
 *   onDisappear 清，并登记 OVERLAY_GUARD_PLAN_TAB 让壳层返回先关它（§6 弹栈边界）。
 * - 内容 Scroll 化：固定 Column 在大字号/小屏上会把预览卡裁掉，主功能页一律可滚，
 *   底部预留 floatingDockClearance，末行不再藏进 dock。
 *
 * 状态栏 mock 为设备 chrome，不实现。这一屏不读行程数据（历史行程归「行程」格）。
 */

import { APP_NAV, enterPlanningFlow, markDraftDirty, DRAFT_DIRTY_KEY, isDraftDirty, TAB_SHOWN_KEY, isTabShownTick, TAB_PLAN } from '../common/constants/AppNav';
import { routerMap } from './AppRouter';
import { HdsChrome } from '../design/HdsChrome';
import { HdsNavigation, HdsNavigationTitleMode, HideMode } from '@kit.UIDesignKit';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { GlassBlurStyle, getSheetImmersiveMaterial, isSystemMaterialActive } from '../utils/immersiveMaterial';
import { registerOverlayBackGuard, unregisterOverlayBackGuard, OVERLAY_GUARD_PLAN_TAB } from '../utils/overlayBackGuard';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';
import { AccountStore } from '../data/AccountStore';
import { DeviceActivator } from '../data/DeviceActivator';
import { PlanDraft } from '../data/PlanDraft';
import { requestSystemBarRefresh } from '../utils/systemBar';
import { AccountKind, AccountState } from '../model/Account';
import { TripBasicInput } from '../model/PlanParams';
import { TripDao, TripSummary } from '../data/TripDao';
import { TripWindow } from '../utils/TripWindow';
import { WidgetSync } from '../widget/TodayCard';
import { Logger } from '../common/logger/Logger';
import { common } from '@kit.AbilityKit';
import { DateUtils } from '../utils/DateUtils';
import { KEY_WINDOW_WIDTH_VP, BP_MD_MIN_VP } from '../utils/breakpointCenter';
import { symmetricInsetForCap } from '../utils/responsive';

interface PreviewStop {
  time: string;
  name: string;
  meta: string;
  dotColor: Resource;
}

interface PreviewLeg {
  text: string;
}

// 预览动线行高：契约 itinerary-row-min-height，行内 spine 线取定值避免百分比循环
const ROW_HEIGHT: number = LayoutTokens.itineraryRowMinHeight;

@Component
export struct YoujingStartPage {
  // 深浅档代 tick：翻档时 EntryAbility 自增，@StorageProp 变化带动本页 build 重跑，
  // 把新 tick 传进 HdsChrome.bar → 标题内容换新 ComponentContent 重挂载、按当前档重解色
  // （官方 HdsTitleBar 自绘内容不随配置切换重渲染，真机实证见 HdsChrome.themeTick）
  @StorageProp('chromeThemeTick') chromeThemeTick: number = 0;

  private pathStack: NavPathStack = APP_NAV;
  /** 窗口实测宽（vp），由断点中心一处测量；0 = 尚未测到，按不收窄处理 */
  @StorageProp(KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 0;

  /** 主 CTA 的进行中状态：游客路径要等账号往返，没有反馈会被当成"按了没反应" */
  @State private starting: boolean = false;
  /** 有可续的规划？由写草稿的一方广播（`DRAFT_DIRTY_KEY`），不是这一屏自己轮询 */
  @StorageProp(DRAFT_DIRTY_KEY) @Watch('onDraftTick') draftTick: string = '0:0';
  @State private draftDirty: boolean = false;

  private onDraftTick(): void {
    this.draftDirty = isDraftDirty(this.draftTick);
  }

  private barScroller: Scroller = new Scroller();
  // 穿底让位（含状态栏）：本页是纯 Scroll 根，留白放进滚动容器随内容滚走
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  /** 顶栏磨砂两态。必须 @State：栏体现在就挂在本页的 HdsNavigation 上，值变了要触发它重建 */
  @State private barScrolled: boolean = false;

  // ——— 2026-11-08 重构：这一页当「出发页」做 ———
  /** 示例行程半模态开关。示例从半屏大卡压成一行入口，不再占版面 */
  @State private showSample: boolean = false;
  /** 弹层「还挂在场面上」的标志：只能由 onDisappear（关闭动画结束）清，
   *  不能看 showSample——返回路径上系统先关弹层、绑定值已置 false，事件才冒泡到壳层，
   *  守卫读绑定状态会答"没开"（ExpensePage recordOpen 同一条时序坑） */
  private sampleOpen: boolean = false;
  /** 最近一趟（没有草稿时的「上次痕迹」）。三个都要 @State：
   *  ③ 行的 else-if 条件读的是 recentId——非状态字段不触发分支重估，
   *  异步回填后行永远不出现（真机踩过：日志显示就绪、树里没有节点） */
  @State private recentLabel: string = '';
  @State private recentMeta: string = '';
  @State private recentId: string = '';
  /** dock 切回这一页时重取最近一趟：从这里规划完新行程再回来，行必须出现 */
  @StorageProp(TAB_SHOWN_KEY) @Watch('onDockShown') dockTick: string = '';

  private onDockShown(): void {
    if (isTabShownTick(this.dockTick, TAB_PLAN)) {
      this.loadRecent();
    }
  }

  /**
   * 绝对滚动偏移 → 顶栏磨砂两态。用**绝对偏移**而不是每帧增量：松手回弹的负增量
   * 会在静止时把磨砂打灭（有据 2026-10-24 根因，契约 §Translucency）。
   */
  private syncBarScroll(): void {
    const on: boolean = this.barScroller.currentOffset().yOffset > 0;
    if (on !== this.barScrolled) {
      this.barScrolled = on;
      if (!on) {
        // 偏移回到 0：HDS 在这一帧回写系统栏属性，补设通道连发四发压住它
        requestSystemBarRefresh();
      }
    }
  }

  aboutToAppear(): void {
    this.draftDirty = isDraftDirty(this.draftTick);
    this.loadRecent();
    // 示例半模态不在 Navigation 栈里：登记守卫，让 Index 的返回拦截先关它而不是"回地图格"
    registerOverlayBackGuard(OVERLAY_GUARD_PLAN_TAB,
      (): boolean => this.sampleOpen,
      (): void => {
        this.showSample = false;
      });
  }

  aboutToDisappear(): void {
    unregisterOverlayBackGuard(OVERLAY_GUARD_PLAN_TAB);
  }

  /**
   * 最近一趟：没有草稿时用它填「上次的痕迹」那一个位置。
   * 与草稿**互斥**（草稿优先）—— 入口页只需要一个「上次」，并排放两块只会分散注意力。
   * 选哪一趟（2026-11-09 用户裁定）：**优先「进行中」的那趟**——入口页的「上次」要接得上
   * 现在；没有在途才退最近更新的。与地图格 resolveAndReload 同一口径（TripWindow.isActive）。
   */
  private loadRecent(): void {
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    TripDao.listSummaries(ctx).then((rows: TripSummary[]): void => {
      Logger.info('Ui.Start', `最近行程查询完成 rows=${rows.length}`);
      if (rows.length === 0) {
        return;
      }
      let picked: TripSummary = rows[0];
      for (const row of rows) {
        if (TripWindow.isActive(row.startDate, row.endDate)) {
          picked = row;
          break;
        }
      }
      const days: number = YoujingStartPage.daysOf(picked.startDate, picked.endDate);
      const active: boolean = TripWindow.isActive(picked.startDate, picked.endDate);
      this.recentId = picked.id;
      this.recentLabel = `${picked.destination} · ${days}天${days > 1 ? `${days - 1}晚` : ''}`;
      this.recentMeta = `${active ? '进行中' : '已结束'} · ${picked.spotCount} 站`;
      Logger.info('Ui.Start', `最近行程就绪 id=${picked.id} 在途=${active} label=${this.recentLabel} meta=${this.recentMeta}`);
    }).catch((err: Error): void => {
      Logger.warn('Ui.Start', `取最近行程失败: ${err.message}`);
    });
  }

  /** 含首尾的天数（2026-11-04 → 11-06 记 3 天） */
  private static daysOf(startDate: string, endDate: string): number {
    const a: number = new Date(startDate).getTime();
    const b: number = new Date(endDate).getTime();
    if (Number.isNaN(a) || Number.isNaN(b) || b < a) {
      return 1;
    }
    return Math.round((b - a) / 86400000) + 1;
  }

  /**
   * 进主链。游客分区才需要静默登录 + 归户。
   *
   * 原来无条件跑 `AccountStore.login()`：`Index` 的登录闸门已经保证走到这里时
   * 分区状态是确定的，真账号用户点主 CTA 还要再等一次账号接口往返——
   * 真机实测 8 秒（00:05:19 按下 → 00:05:27「静默登录成功」）期间**界面零反馈**，
   * 用户只会认为"按了没反应"再按一次；日志里还有该往返报
   * `Incorrect context parameter type` 后静默退回游客分区的记录。
   * 所以：已登录直接进，游客才登录并归户，并且给按钮一个进行中的状态。
   */
  private async enterApp(): Promise<void> {
    // 从首启页进规划 = 明确的新建意图，先丢掉上一段的草稿
    PlanDraft.fresh();
    markDraftDirty(false);
    if (this.starting) {
      return;
    }
    this.starting = true;
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      if (AccountStore.isGuest()) {
        const state: AccountState = await AccountStore.login(ctx);
        if (state.kind === AccountKind.HUAWEI) {
          await TripDao.adoptGuestData(ctx, state.uid);
          // 归户后 BFF 还持着游客票据：用新身份的 idToken 重新激活（失败不挡进场）
          await DeviceActivator.reactivate(ctx).catch((): boolean => false);
          // 归户会换掉卡片可读的分区键，立刻回灌一次，别让桌面空等 30 分钟
          WidgetSync.refreshAll(ctx).catch((err: Error) => {
            Logger.warn('Ui.Start', `卡片刷新失败: ${err.message}`);
          });
        }
      }
    } catch (err) {
      // 登录/归户失败不阻断进主链：按本机游客分区继续（EntryAbility.bootstrap 同一口径）。
      // 原来这里裸 await，一处 rejection 就让用户静默卡在首启页
      Logger.error('Ui.Start', `登录或归户失败，按游客分区继续: ${(err as Error).message}`);
    }
    this.starting = false;
    this.pathStack.pushPath({ name: 'TripInput' });
  }

  /** 草稿卡首行：目的地 · 日期（日期无效时只报目的地，不编一个日期出来） */
  private draftHeadline(): string {
    const b: TripBasicInput = PlanDraft.get().basic;
    if (DateUtils.isValidIsoDate(b.startDate) && DateUtils.isValidIsoDate(b.endDate)) {
      return `${b.destination} · ${this.fmt(b.startDate)}–${this.fmt(b.endDate)}`;
    }
    return b.destination;
  }

  /** 草稿卡次行：人数是草稿里确定已填的一项 */
  private draftMeta(): string {
    const b: TripBasicInput = PlanDraft.get().basic;
    return `${b.people} 位同行`;
  }

  /** 与屏2 同一口径的日期短格式：2026-06-10 → 6月10日 */
  private fmt(dateStr: string): string {
    const parts: string[] = dateStr.split('-');
    return `${Number(parts[1])}月${Number(parts[2])}日`;
  }

  private stops: PreviewStop[] = [
    { time: '09:30', name: '清水寺', meta: '东山区 · 停留 1小时30分钟', dotColor: ColorTokens.primary },
    { time: '10:45', name: '二年坂', meta: '古街漫步 · 停留 45分钟', dotColor: ColorTokens.primary },
    { time: '12:10', name: '一番街 午餐', meta: '京料理定食 · 停留 1小时', dotColor: ColorTokens.bookmark }
  ];
  private legs: PreviewLeg[] = [
    { text: '步行 12分钟 · 750m' },
    { text: '步行 18分钟 · 1.2km' }
  ];

  @Builder
  spineNode(dotColor: Resource) {
    Stack({ alignContent: Alignment.Center }) {
      Circle()
        .width(22)
        .height(22)
        .fill(ColorTokens.canvas)
        .stroke(ColorTokens.ink)
        .strokeWidth(2)
      Circle()
        .width(LayoutTokens.itineraryNodeDot)
        .height(LayoutTokens.itineraryNodeDot)
        .fill(dotColor)
    }
    .width(LayoutTokens.itineraryNodeSize)
    .height(LayoutTokens.itineraryNodeSize)
  }

  @Builder
  timelineRow(stop: PreviewStop, index: number) {
    Row() {
      Text(stop.time)
        .width(LayoutTokens.itineraryTimeGutter)
        .fontSize(TypeTokens.time.size)
        .fontWeight(600)
        .fontColor(ColorTokens.ink)
        .textAlign(TextAlign.End)
        .fontFeature("'tnum' on")
        .padding({ right: SpaceTokens.sm, top: SpaceTokens.xxs })
      Stack({ alignContent: Alignment.Top }) {
        Column()
          .width(LayoutTokens.routeLineWidth)
          .height(index === this.stops.length - 1 ? SpaceTokens.sm : ROW_HEIGHT)
          .backgroundColor(ColorTokens.surfaceSunken)
        this.spineNode(stop.dotColor)
      }
      .width(LayoutTokens.itineraryNodeSize)
      .height(ROW_HEIGHT)
      Column() {
        Text(stop.name)
          .fontSize(TypeTokens.headline.size)
          .fontWeight(600)
          .fontColor(ColorTokens.ink)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(stop.meta)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
          .fontFeature("'tnum' on")
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .padding({ left: SpaceTokens.xs })
    }
    .alignItems(VerticalAlign.Top)
    .width('100%')
    .height(ROW_HEIGHT)
  }

  /**
   * 交通腿与屏8 同构：透明、无填充、无圆角，主轴段是 2px dashed
   * （solid pill 是 stitch 预检第 3 条点名的已知破坏，预览卡曾是最后一个没改的）。
   */
  @Builder
  transitLeg(leg: PreviewLeg) {
    Row() {
      Column().width(LayoutTokens.itineraryTimeGutter)
      Column()
        .width(LayoutTokens.routeLineWidth)
        .height(LayoutTokens.transitLegHeight)
        .border({ width: { left: LayoutTokens.routeLineWidth }, color: ColorTokens.separator, style: BorderStyle.Dashed })
      Row({ space: SpaceTokens.xs }) {
        SymbolGlyph($r('sys.symbol.figure_walk'))
          .fontSize(IconSizes.control)
          .fontColor([ColorTokens.icon])
        Text(leg.text)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
          .fontFeature("'tnum' on")
      }
      .alignItems(VerticalAlign.Center)
      .padding({ left: SpaceTokens.xs })
    }
    .width('100%')
    .height(LayoutTokens.transitLegHeight)
    .alignItems(VerticalAlign.Center)
    .margin({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })
  }

  /**
   * 示例半模态内容：spine 几何与屏8 同源（52 时间槽 / 24 节点 / 76 行 / 44 交通腿）。
   * 不包 ImmersiveSurface、不涂卡底——sheet 的 systemMaterial 是材质唯一载体，
   * 再叠一层自绘面 = 双表面（配方照有据 DetailPostContent:287-296）。
   * 交通腿仍是透明无填充 + 2px dashed（solid pill 是 stitch 预检点名的已知破坏）。
   */
  @Builder
  sampleSheet() {
    Column() {
      Row() {
        Text('Day 1 · 京都 东山步道')
          .fontSize(TypeTokens.title.size)
          .fontWeight(700)
          .fontFamily(TypeTokens.title.family)
          .fontColor(ColorTokens.ink)
          .layoutWeight(1)
        // mock 示例按屏4「京都（示例数据）」同一口径如实标注，不谎报为正式内置库
        Text('示例数据')
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
      }
      .alignItems(VerticalAlign.Center)
      .width('100%')
      .padding({ bottom: SpaceTokens.xs })
      .border({ width: { bottom: LayoutTokens.hairlineWidth }, color: ColorTokens.separator })

      Column() {
        ForEach(this.stops, (stop: PreviewStop, index: number) => {
          this.timelineRow(stop, index)
          if (index < this.legs.length) {
            this.transitLeg(this.legs[index])
          }
        }, (stop: PreviewStop, index: number): string => `start-preview-${index}-${stop.time}`)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ top: SpaceTokens.xs })

      // 承诺块 = 契约 reason-block：surfacePanel + 2px primary 左条
      Column() {
        Text('结构化路线承诺')
          .fontSize(TypeTokens.overline.size)
          .fontWeight(600)
          .fontColor(ColorTokens.muted)
        Text('基于本地精选数据库与步行动线计算，每个站点均明确耗时与预约状态。')
          .fontSize(TypeTokens.small.size)
          .fontColor(ColorTokens.ink)
          .lineHeight(TypeTokens.small.lineHeight)
          .margin({ top: SpaceTokens.xxs })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(SpaceTokens.sm)
      .borderRadius(RadiusTokens.reason)
      .backgroundColor(ColorTokens.surfacePanel)
      .border({ width: { left: 2 }, color: ColorTokens.primary })
      .margin({ top: SpaceTokens.sm })
    }
    .padding(SpaceTokens.base)
    .width('100%')
  }

  /**
   * 五格同构（有据形态）：格内自带 `HdsNavigation` + `titleBar`，向导链的深链目的页
   * 也从这一层解析（`.navDestination(routerMap)`）。
   * 外层 `Index` 的 `Navigation(HOST_NAV)` 只是宿主，不持有本页的栈——
   * 一个 NavPathStack 只能被一个 Navigation 持有，抢绑的后果是向导链盖住 dock。
   */
  build() {
    HdsNavigation(this.pathStack) {
      this.scrollBody()
    }
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    .titleBar(HdsChrome.bar({ themeTick: this.chromeThemeTick, mainTitle: '规划', backSlot: false, scrolled: this.barScrolled }))
    // 不收标题栏（2026-11-08 对标有据）：有据根页标题栏常驻——只有 HomeTab 用
    // hideBottomBuilder 收分段那一行，ProfilePage 完全没有 dynamicHideTitleBar。
    // 整条收起后滚动时顶部没有栏体磨砂，穿底内容直接顶到状态栏下，
    // 与有据「栏体把内容糊住」的观感不是一回事。bindToScrollable 保留（驱动渐变模糊）。
    .bindToScrollable([this.barScroller])
    .clip(false)
    .navDestination(routerMap)
    .mode(NavigationMode.Stack)
    .width('100%')
    .height('100%')
    // HDS 深色档这层默认纯黑，透明栏会把它露成一条比画布暗一档的带（§5ci 续 80）
    .backgroundColor($r('app.color.canvas'))
  }

  @Builder
  scrollBody() {
    Scroll(this.barScroller) {
      Column() {
        // ① 页题（2026-11-08 重构）：这一页是「出发页」，页题要**提出问题**而不是报栏目名。
        //    第二行落品牌蓝——整页唯一的高饱和文字，把视线钉在「去哪儿」上。
        Text() {
          Span('下一趟，\n')
            .fontColor(ColorTokens.ink)
          Span('去哪儿？')
            .fontColor(ColorTokens.primary)
        }
        .fontSize(TypeTokens.display.size)
        .fontWeight(TypeTokens.display.weight)
        .fontFamily(TypeTokens.display.family)
        .lineHeight(TypeTokens.display.lineHeight)
        .width('100%')
        .margin({ top: SpaceTokens.sm })

        Text('说个城市和天数，剩下的交给路线。')
          .fontSize(TypeTokens.small.size)
          .fontColor(ColorTokens.body)
          .width('100%')
          .margin({ top: SpaceTokens.xs })

        // ② 主入口卡：整页唯一的重心。卡里写清「点下去会发生什么」，
        //    而不是只丢一颗按钮 —— 入口页要降低的是「开始」这件事的心理门槛。
        Column({ space: SpaceTokens.xxs }) {
          Text('开始一趟新行程')
            .fontSize(TypeTokens.headline.size)
            .fontWeight(TypeTokens.headline.weight)
            .fontColor(ColorTokens.ink)
            .width('100%')
          Text('目的地、天数、人数，三步拿到能直接走的动线')
            .fontSize(TypeTokens.small.size)
            .fontColor(ColorTokens.muted)
            .lineHeight(TypeTokens.small.lineHeight)
            .width('100%')
          YoujingButton({
            variant: YoujingButtonVariant.PRIMARY,
            label: this.starting ? '正在准备…' : '开始规划',
            fullWidth: true,
            trailingSymbol: $r('sys.symbol.arrow_right'),
            disabled: this.starting,
            onAction: (): void => {
              this.enterApp();
            }
          })
            .margin({ top: SpaceTokens.sm })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding(SpaceTokens.md)
        .borderRadius(RadiusTokens.hero)
        .backgroundColor(ColorTokens.surfaceElevated)
        .margin({ top: SpaceTokens.lg })

        // ③ 上次的痕迹：草稿优先，其次最近一趟，**二选一**。
        //    入口页只需要一个「上次」—— 并排放两块只会把注意力从主入口上分走。
        //    点草稿不 fresh()：屏2~屏5 都从 PlanDraft 起值，重进就是接着上次的进度走。
        if (this.draftDirty) {
          Row() {
            SymbolGlyph($r('sys.symbol.square_and_pencil'))
              .fontSize(IconSizes.control)
              .fontColor([ColorTokens.primary])
              .margin({ right: SpaceTokens.sm })
            Column({ space: SpaceTokens.xxs }) {
              Text('未完成的规划')
                .fontSize(TypeTokens.overline.size)
                .fontWeight(600)
                .fontColor(ColorTokens.muted)
              Text(this.draftHeadline())
                .fontSize(TypeTokens.headline.size)
                .fontWeight(600)
                .fontColor(ColorTokens.ink)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.draftMeta())
                .fontSize(TypeTokens.caption.size)
                .fontWeight(450)
                .fontColor(ColorTokens.muted)
                .fontFeature("'tnum' on")
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            // chevron 是「这行能点开」的 affordance：取 muted（faint 2.67:1 不过 3:1）
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(IconSizes.control)
              .fontColor([ColorTokens.muted])
          }
          .alignItems(VerticalAlign.Center)
          .width('100%')
          .padding(SpaceTokens.base)
          .borderRadius(RadiusTokens.card)
          .backgroundColor(ColorTokens.surfaceElevated)
          .margin({ top: SpaceTokens.sm })
          .accessibilityText('继续未完成的规划')
          .onClick((): void => {
            enterPlanningFlow('TripInput');
          })
        } else if (this.recentId.length > 0) {
          Row() {
            SymbolGlyph($r('sys.symbol.map'))
              .fontSize(IconSizes.control)
              .fontColor([ColorTokens.muted])
              .margin({ right: SpaceTokens.sm })
            Column({ space: SpaceTokens.xxs }) {
              Text('最近一趟')
                .fontSize(TypeTokens.overline.size)
                .fontWeight(600)
                .fontColor(ColorTokens.muted)
              Text(this.recentLabel)
                .fontSize(TypeTokens.headline.size)
                .fontWeight(600)
                .fontColor(ColorTokens.ink)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.recentMeta)
                .fontSize(TypeTokens.caption.size)
                .fontWeight(450)
                .fontColor(ColorTokens.muted)
                .fontFeature("'tnum' on")
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(IconSizes.control)
              .fontColor([ColorTokens.muted])
          }
          .alignItems(VerticalAlign.Center)
          .width('100%')
          .padding(SpaceTokens.base)
          .borderRadius(RadiusTokens.card)
          .backgroundColor(ColorTokens.surfaceElevated)
          .margin({ top: SpaceTokens.sm })
          .accessibilityText('打开最近一趟行程')
          .onClick((): void => {
            this.pathStack.pushPath({ name: 'Itinerary', param: this.recentId });
          })
        }

        // ④ 示例入口（2026-11-08 重构）：示例从半屏大卡压成一行。它是「给你看产出」的
        //    三级内容，不能与用户自己的行程卡同级同重——版面只留一行，全貌进半模态。
        Row() {
          SymbolGlyph($r('sys.symbol.map'))
            .fontSize(IconSizes.control)
            .fontColor([ColorTokens.muted])
            .margin({ right: SpaceTokens.sm })
          Text('看看一份行程长什么样')
            .fontSize(TypeTokens.small.size)
            .fontColor(ColorTokens.body)
            .layoutWeight(1)
          Text('示例')
            .fontSize(TypeTokens.caption.size)
            .fontWeight(450)
            .fontColor(ColorTokens.muted)
            .margin({ right: SpaceTokens.xs })
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(IconSizes.control)
            .fontColor([ColorTokens.muted])
        }
        .alignItems(VerticalAlign.Center)
        .width('100%')
        .padding({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })
        .margin({ top: SpaceTokens.sm })
        .accessibilityText('查看行程示例')
        .onClick((): void => {
          this.showSample = true;
          this.sampleOpen = true;
        })
        // 半模态选项照 ExpensePage「记一笔」同款（含双表面禁则的材质让位）
        .bindSheet($$this.showSample, this.sampleSheet(), {
          height: '62%',
          showClose: true,
          systemMaterial: getSheetImmersiveMaterial(),
          blurStyle: isSystemMaterialActive() ? BlurStyle.NONE : GlassBlurStyle.Floating,
          backgroundColor: isSystemMaterialActive() ? undefined : ColorTokens.canvas,
          // 关闭动画结束才清「还开着」：返回键那一路要先靠它把事件吃掉
          onDisappear: (): void => {
            this.sampleOpen = false;
          }
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      // 左右内缩走对称内缩而不是 maxWidth：卡片子级全是 width('100%')，
      // 给父 Column 加 constraintSize.maxWidth 只会左贴边、右侧空出一条（实测更坏）。
      // 折叠屏展开（窗口 707vp）时预览卡原本通铺 642vp、三行节点右侧 55% 全白。
      .padding({
        // 穿底（2026-11-08 对标有据）：让位必须挂在**内容**上、随内容一起滚走。
        // 挂在 Scroll 自己的 padding 上会把视口整体压到栏底之下，标题栏那 175px
        // 永远采样不到内容 —— 滚动后顶部仍是一块纯白（有据 HomeTab 的 Scroll 是
        // top:0 + 视口从栏底起，这里等价地让首块让位、滚动后内容穿到栏下）。
        top: HdsChrome.contentTopInset(this.statusBarHeight),
        left: symmetricInsetForCap(this.windowWidthVp, BP_MD_MIN_VP, SpaceTokens.base),
        right: symmetricInsetForCap(this.windowWidthVp, BP_MD_MIN_VP, SpaceTokens.base),
        // 悬浮 dock 压在滚动内容上：末行（示例入口行）要能滚出 dock 顶边
        bottom: LayoutTokens.floatingDockClearance
      })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .onDidScroll((): void => {
      this.syncBarScroll();
    })
    .align(Alignment.Top)
    // 不涂 canvas：这层涂色会把标题栏区盖成纯白，穿底素材全被挡在下面。
    // 底色由壳层与 TopStrip 单点负责。
  }
}
