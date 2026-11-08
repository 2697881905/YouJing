/**
 * 屏1 首启与静默登录（帧 77ed8d08）——五格导航后它是「规划」格的根页。
 * 2026-11-03 主功能页化（对齐「有据」家族契约 v2）：
 * - 标题栏交还官方 HdsChrome，本页不再自绘品牌块（字牌 + 英文 overline + 标语是首启门面的残留，
 *   不是工作台形态）。2026-11-05 起这条 `HdsNavigation(APP_NAV)` 由**本页自己**挂（以前挂在
 *   Index 壳层里，滚动状态只能经 AppStorage 递一层，是五格里唯一的异形）。
 * - 内容按主功能页骨架重排：创建入口（serif 页题 + 副题 + 唯一实心主按钮）
 *   → 草稿续办卡（field-row 卡形态：overline + headline 值 + chevron，契约行卡规格）
 *   → 「规划预览」分区 overline + 预览卡（spine 几何与屏8 同源）。
 * - 组件级对齐：预览卡头的实心蓝 pill 摘除（动作色不做标签，改 muted「示例数据」标注）；
 *   交通腿对齐屏8 口径（透明无填充 + 2px dashed 主轴段，去胶囊边框——solid pill 是
 *   stitch 预检第 3 条点名的已知破坏）；承诺块补 reason-block 的 2px primary 左条
 *   （契约 reason-block.leftRule，与屏8/屏10 同款）。
 * - 内容 Scroll 化：固定 Column 在大字号/小屏上会把预览卡裁掉，主功能页一律可滚，
 *   底部预留 floatingDockClearance，末行不再藏进 dock。
 *
 * 状态栏 mock 为设备 chrome，不实现。这一屏不读行程数据（历史行程归「行程」格）。
 */

import { APP_NAV, enterPlanningFlow, markDraftDirty, DRAFT_DIRTY_KEY, isDraftDirty } from '../common/constants/AppNav';
import { routerMap } from './AppRouter';
import { HdsChrome } from '../design/HdsChrome';
import { HdsNavigation, HdsNavigationTitleMode, HideMode } from '@kit.UIDesignKit';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { ImmersiveSurface } from '../components/ImmersiveSurface';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';
import { AccountStore } from '../data/AccountStore';
import { DeviceActivator } from '../data/DeviceActivator';
import { PlanDraft } from '../data/PlanDraft';
import { requestSystemBarRefresh } from '../utils/systemBar';
import { AccountKind, AccountState } from '../model/Account';
import { TripBasicInput } from '../model/PlanParams';
import { TripDao } from '../data/TripDao';
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
    .titleBar(HdsChrome.bar({ mainTitle: '规划', scrolled: this.barScrolled }))
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
        // ① 创建入口：serif 页题 + 副题（屏2 同款页题档与文案，主功能页从这里的排版起算）
        Column({ space: SpaceTokens.xs }) {
          Text('开启一次有迹可循的旅程')
            .fontSize(TypeTokens.title.size)
            .fontWeight(700)
            .fontFamily(TypeTokens.title.family)
            .fontColor(ColorTokens.ink)
          Text('设定出行基础参数，AI 将基于本地精选数据库构建动线')
            .fontSize(TypeTokens.small.size)
            .fontColor(ColorTokens.body)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .margin({ top: SpaceTokens.sm, bottom: SpaceTokens.sm })

        // ② 唯一实心主按钮（契约：一屏一颗 primary，其余 outline）
        YoujingButton({
          variant: YoujingButtonVariant.PRIMARY,
          label: this.starting ? '正在准备…' : '开始规划新行程',
          fullWidth: true,
          trailingSymbol: $r('sys.symbol.arrow_right'),
          disabled: this.starting,
          onAction: (): void => {
            this.enterApp();
          }
        })

        // ③ 草稿续办卡：field-row 卡形态（overline 标签 + headline 值 + chevron），
        // 整卡可点。点它**不 fresh()**：屏2/屏3/屏4/屏5 都从 `PlanDraft` 起值，
        // 从屏2 重进就是接着上次的进度走（§5q/§5w 那条主链缺口的收口）
        if (this.draftDirty) {
          Row() {
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

            // chevron 是「这行能点开」的 affordance：按契约取 muted，不用 faint（2.67:1 不过 3:1）
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
        }

        // ④ 分区 overline（屏11「分类支出」同款 section label），不再用实心蓝 pill 当标签
        Text('规划预览')
          .fontSize(TypeTokens.overline.size)
          .fontWeight(600)
          .fontColor(ColorTokens.muted)
          .width('100%')
          .margin({ top: SpaceTokens.lg, bottom: SpaceTokens.sm })

        // ⑤ 预览卡：spine 几何与屏8 同源（52 时间槽 / 24 节点 / 76 行 / 44 交通腿）
        ImmersiveSurface({ radius: RadiusTokens.card, surfaceWidth: '100%' }) {
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

            // 承诺块 = 契约 reason-block：surfacePanel + 2px primary 左条（补上此前缺的左条）
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
          .borderRadius(RadiusTokens.card)
          .backgroundColor(ColorTokens.surfaceElevated)
          .width('100%')
        }
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
        // 悬浮 dock 压在滚动内容上：末行（预览卡承诺块）要能滚出 dock 顶边
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
