/**
 * 「我的」页 · dock 第五格根页。
 *
 * 为什么单独一页而不是继续用 `TripsPage`：五格分工后「行程」格才是历史/编辑的入口，
 * 而这一格要装个人信息与两张概览卡（会员 / 勋章）。设置与三份法务文书已独立成
 * `SettingsPage`，从右上角齿轮进；这里只留概览，不再自己铺设置行。
 *
 * 结构照 `TripsPage` 的 rootMode 双分支：作为 TabContent 根页时自己挂 `HdsNavigation`
 * （`hideBackButton(true)` + `titleMode(MINI)`），被 push 时走 `HdsNavDestination`。
 * 取数一次在 `aboutToAppear`、之后靠 dock 广播重取 —— 只挂 `onShown` 会让根页永不取数
 * （真机实测过的坑，见 INIT_REPORT §4k）。
 *
 * 头像/昵称一律问 `data/ProfileStore`，不在这里写死：真头像是已确认的后续需求，
 * 两条实现路（profile scope 弹窗 vs 接服务端）都还没拍，出口留在这一层，
 * 接的时候页面结构一行不用动。
 */

import { PROFILE_NAV, TAB_MINE, TAB_SHOWN_KEY, isTabShownTick, enterPlanningFlow } from '../common/constants/AppNav';
import { routerMap } from './AppRouter';
import { AccountStore, AUTH_STATE_KEY } from '../data/AccountStore';
import { BadgeDao } from '../data/BadgeDao';
import { EntitlementStore, Entitlement, SubscriptionInfo, PassInfo } from '../data/EntitlementStore';
import { DateUtils } from '../utils/DateUtils';
import { membershipStatus, membershipUsage, subscriptionActive, MembershipStatus } from '../utils/MembershipCopy';
import { BadgeGroup, BadgeRecord, badgeCityCount, badgeTotal, buildBadgeBoard } from '../utils/BadgeBoard';
import { ProfileStore } from '../data/ProfileStore';
import { YoujingButton, YoujingButtonVariant } from '../components/YoujingButton';
import { Logger } from '../common/logger/Logger';
import { PlanDraft } from '../data/PlanDraft';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { HdsChrome } from '../design/HdsChrome';
import { common } from '@kit.AbilityKit';
import { HdsNavigation, HdsNavigationTitleMode, HdsNavDestination, HdsNavDestinationTitleMode, HideMode } from '@kit.UIDesignKit';
import { requestSystemBarRefresh } from '../utils/systemBar';

@Component
export struct MinePage {
  /** true = 作为 dock 根页内联在 TabContent 里（路线 B），此时要自己挂 HdsNavigation */
  @Prop rootMode: boolean = false;
  /** 本页是 PROFILE_NAV 这条 tab 栈的宿主，push 必须落在自己的栈上 */
  private pathStack: NavPathStack = PROFILE_NAV;
  /** 切回这一格时重取勋章计数：在屏15 收了新章再切回来，不该还看到旧那份 */
  @StorageProp(TAB_SHOWN_KEY) @Watch('onDockShown') dockTick: string = '';
  /** 登录态：'' 水合中 / guest / huawei。资料区要跟它即时变 */
  @StorageProp(AUTH_STATE_KEY) authState: string = '';
  /** 权益变更（购买/刷新/登出）时即时刷新会员卡 */
  @StorageProp(EntitlementStore.TICK_KEY) @Watch('onEntitlementTick') entTick: number = 0;
  @State private badgeCount: number = 0;
  @State private cityCount: number = 0;
  /** 会员卡：订阅/通行证状态（付费后 App 内唯一能看到权益的地方） */
  @State private memberTitle: string = '未开通会员';
  @State private memberDetail: string = '生成免费；导出与无限重排需解锁';
  @State private memberActive: boolean = false;
  /** 顶栏磨砂两态：由**绝对**滚动偏移驱动（每帧增量会被松手回弹的负帧打灭，契约 §Translucency） */
  @State private barScrolled: boolean = false;
  private barScroller: Scroller = new Scroller();
  // 穿底档让位要含状态栏：内容原点回到窗口 0（真机实证见 HdsChrome.contentTopInset）
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  private onDockShown(): void {
    if (isTabShownTick(this.dockTick, TAB_MINE)) {
      this.reload();
    }
  }

  aboutToAppear(): void {
    this.reload();
  }

  private onEntitlementTick(): void {
    this.refreshMembership();
  }

  /** 会员卡按权益缓存即时刷新：订阅看有效期（不信单字段），通行证按条数（MembershipCopy 单点文案）。 */
  private refreshMembership(): void {
    const ent: Entitlement = EntitlementStore.get();
    const sub: SubscriptionInfo | null = ent.subscription;
    const hasSub: boolean = sub !== null &&
      subscriptionActive(sub.status, sub.periodEnd, DateUtils.todayIso());
    const activePasses: number = ent.passes.filter((p: PassInfo): boolean =>
      p.status === 'active').length;
    const status: MembershipStatus = membershipStatus(
      hasSub, sub !== null ? sub.periodEnd : '', activePasses, DateUtils.todayIso());
    this.memberActive = status.active;
    this.memberTitle = status.title;
    this.memberDetail = status.detail;
  }

  private reload(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    BadgeDao.listMine(ctx).then((rows: BadgeRecord[]): void => {
      const groups: BadgeGroup[] = buildBadgeBoard(rows);
      this.badgeCount = badgeTotal(groups);
      this.cityCount = badgeCityCount(groups);
    }).catch((err: Error): void => {
      // 读失败只让卡片显示 0：这是概览，不是勋章墙本体，不该拦住这一格
      Logger.warn('Ui.Mine', `勋章计数读取失败: ${err.message}`);
    });
    this.refreshMembership();
  }

  @Builder
  profileHeader() {
    Row({ space: SpaceTokens.base }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle()
          .width(LayoutTokens.profileAvatarSize)
          .height(LayoutTokens.profileAvatarSize)
          .fill(ColorTokens.primaryTint)
        // 头像来源只有一个出口：本轮恒返回官方符号占位，接真头像时改 ProfileStore 即可
        if (ProfileStore.avatarOf(AccountStore.uid()).kind === ProfileStore.KIND_SYMBOL) {
          SymbolGlyph(ProfileStore.avatarOf(AccountStore.uid()).symbol)
            .fontSize(LayoutTokens.profileAvatarSize * 0.62)
            .fontColor([ColorTokens.primary])
        } else {
          Image(ProfileStore.avatarOf(AccountStore.uid()).url)
            .width(LayoutTokens.profileAvatarSize)
            .height(LayoutTokens.profileAvatarSize)
            .borderRadius(RadiusTokens.pill)
            .objectFit(ImageFit.Cover)
            .draggable(false)
        }
      }
      .width(LayoutTokens.profileAvatarSize)
      .height(LayoutTokens.profileAvatarSize)
      .borderRadius(RadiusTokens.pill)
      .border({ width: LayoutTokens.hairlineWidth, color: ColorTokens.hairline })

      Column({ space: SpaceTokens.xxs }) {
        // headline 而非 title：这串是脱敏 ID（操作型文本），契约里 serif 只给编辑性标题
        Text(ProfileStore.displayName())
          .fontSize(TypeTokens.headline.size)
          .fontWeight(TypeTokens.headline.weight)
          .fontFamily(TypeTokens.headline.family)
          .fontColor(ColorTokens.ink)
        Text(ProfileStore.displayHint())
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: SpaceTokens.base, bottom: SpaceTokens.base })
  }

  @Builder
  memberCard() {
    Row({ space: SpaceTokens.sm }) {
      SymbolGlyph($r('sys.symbol.crown'))
        .fontSize(IconSizes.display)
        .fontColor([this.memberActive ? ColorTokens.primary : ColorTokens.icon])
      Column({ space: SpaceTokens.xxs }) {
        Text(this.memberTitle)
          .fontSize(TypeTokens.small.size)
          .fontWeight(600)
          .fontColor(ColorTokens.ink)
        Text(this.memberDetail)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(IconSizes.control)
        .fontColor([ColorTokens.muted])
    }
    .width('100%')
    .padding(SpaceTokens.base)
    .borderRadius(RadiusTokens.card)
    .backgroundColor(ColorTokens.surfaceElevated)
    .onClick((): void => {
      this.pathStack.pushPath({ name: 'Pricing' });
    })
  }

  @Builder
  medalCard() {
    Row({ space: SpaceTokens.sm }) {
      SymbolGlyph($r('sys.symbol.medal'))
        .fontSize(IconSizes.display)
        .fontColor([ColorTokens.primary])
      Column({ space: SpaceTokens.xxs }) {
        Text(this.badgeCount > 0 ? `已收 ${this.badgeCount} 枚勋章` : '还没有勋章')
          .fontSize(TypeTokens.small.size)
          .fontWeight(600)
          .fontColor(ColorTokens.ink)
        Text(this.badgeCount > 0 ? `走过 ${this.cityCount} 座城市 · 打卡即可能得章`
          : '打卡到过的景点会攒成勋章，按城市归档')
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(ColorTokens.muted)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(IconSizes.control)
        .fontColor([ColorTokens.muted])
    }
    .width('100%')
    .padding(SpaceTokens.base)
    .borderRadius(RadiusTokens.card)
    .backgroundColor(ColorTokens.surfaceElevated)
    .onClick((): void => {
      this.pathStack.pushPath({ name: 'Badges' });
    })
  }

  @Builder
  body() {
    Column() {
      List({ space: SpaceTokens.sm, scroller: this.barScroller }) {
        ListItem() {
          this.profileHeader()
        }
        // 游客分区也要能进来看看，所以登录 CTA 放在资料区之后而不是挡整页：
        // Index 的登录闸门已经拦过"没同意隐私就什么都不给看"，这里只处理已同意未登录
        if (this.authState === 'guest') {
          ListItem() {
            YoujingButton({
              variant: YoujingButtonVariant.PRIMARY,
              label: '登录华为账号',
              fullWidth: true,
              onAction: (): void => {
                this.goLogin();
              }
            })
          }
        }
        ListItem() {
          this.memberCard()
        }
        ListItem() {
          this.medalCard()
        }
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      // 末行住在悬浮 dock 底下，按实测净空让位（与 TripsPage/BadgePage 同一写法）
      .padding({ left: SpaceTokens.base, right: SpaceTokens.base,
        bottom: LayoutTokens.floatingDockClearance })
      // 穿底（2026-11-08 对标有据 ProfilePage）：让位必须走 contentStartOffset，
      // 不能挂 padding —— padding 会把**视口**整体压到栏底之下，内容永远上不到
      // 标题栏那 175px 里，栏体磨砂采样不到任何东西，顶部就永远是一块纯白。
      // contentStartOffset 只挪首屏起点，滚动后内容照常穿到栏下被糊掉。
      .contentStartOffset(HdsChrome.contentTopInset(this.statusBarHeight))
      .onDidScroll((): void => {
        this.syncBarScroll();
      })
    }
    .width('100%')
    .height('100%')
    // 不涂 canvas：这一层涂色会把 106..281 的标题栏区整块盖成纯白，穿底素材全被挡在下面。
    // 底色由壳层（Index 的 Column）与 TopStrip 单点负责，本页只负责内容。
  }

  /**
   * 游客点「登录华为账号」：走的是 Index 那套登录闸门，不是本页自己拉账号接口。
   * 这里只把用户送回主链入口，避免在两个地方各写一次 AccountStore.login。
   */
  private goLogin(): void {
    this.getUIContext().getPromptAction().showToast({ message: '可在首页点「开始规划新行程」时登录' });
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
        this.body()
      }
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(true)
      .titleBar(HdsChrome.bar({
        mainTitle: '我的',
        backSlot: false,
        scrolled: this.barScrolled,
        
        menu: [HdsChrome.item($r('sys.symbol.plus'), '新建行程', (): void => {
          PlanDraft.fresh();
          enterPlanningFlow('TripInput');
        }), HdsChrome.item($r('sys.symbol.gearshape'), '设置', (): void => {
          this.pathStack.pushPath({ name: 'Settings' });
        })]
      }))
      .navDestination(routerMap)
      .mode(NavigationMode.Stack)
      // 跟手收起（第 13 行）：有径栏内没有 bottomBuilder，收的是标题区本身；
      // hideRatio=1.0 才是滚 1vp 收 1vp（官方默认 2.0 是半速），滚动源由 bindToScrollable 供给
      // 不收标题栏（2026-11-08 对标有据）：有据根页标题栏常驻——只有 HomeTab 用
      // hideBottomBuilder 收分段那一行，ProfilePage 完全没有 dynamicHideTitleBar。
      // 整条收起后滚动时顶部没有栏体磨砂，穿底内容直接顶到状态栏下，
      // 与有据「栏体把内容糊住」的观感不是一回事。bindToScrollable 保留（驱动渐变模糊）。
      .bindToScrollable([this.barScroller])
      .clip(false)
      .width('100%')
      .height('100%')
    } else {
      HdsNavDestination() {
        this.body()
      }
      // HDS 深色档这层默认纯黑，透明栏会把它露成一条比画布暗一档的带（成因与实测见 Docs/INIT_REPORT.md §5ci 续 80）
      .backgroundColor(ColorTokens.canvas)
      .titleBar(HdsChrome.bar({ mainTitle: '我的', scrolled: this.barScrolled }))
      .titleMode(HdsNavDestinationTitleMode.MINI)
      // 不收栏（2026-11-08）：NavDestination 内容区恒预留 56vp 栏位、收栏后不回收，收起只留一条 175px 白带
      .bindToScrollable([this.barScroller])
      .clip(false)
    }
  }
}
