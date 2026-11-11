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
 *
 * 2026-11-09 全量对标有据 ProfileHeader 结构（用户令「搬运」，后续共享两 App 资料）：
 * · 资料区 = 身份行（头像 + 衬线名 + 说明）+ 统计行（StatRow 三列：行程/勋章/足迹）
 *   + 右端胶囊双态：游客「去登录」/ 登录「编辑资料」（有据 ProfileHeader 同位；
 *   编辑资料 → ProfileEditPage，字段集与有据 User 同形——共享资料的模型契约）。
 *   有据的 16:10 封面卡与
 *   草稿箱/废纸篓 胶囊不搬（背景图基建未立 / UGC 域概念）
 * · 右上角菜单对标 profileMenuItems：分享在前、设置在后，加号(新建行程)摘除
 * · 分享走系统分享面板带足迹概要文案；有据的 ProfileShareSheet 全面板待主页链接基建
 */

import { HOST_NAV, PROFILE_NAV, TAB_MINE, TAB_SHOWN_KEY, isTabShownTick } from '../common/constants/AppNav';
import { routerMap } from './AppRouter';
import { AccountStore, AUTH_STATE_KEY } from '../data/AccountStore';
import { BadgeDao } from '../data/BadgeDao';
import { EntitlementStore, Entitlement, SubscriptionInfo, PassInfo } from '../data/EntitlementStore';
import { DateUtils } from '../utils/DateUtils';
import { membershipStatus, membershipUsage, subscriptionActive, MembershipStatus } from '../utils/MembershipCopy';
import { BadgeGroup, BadgeRecord, badgeCityCount, badgeTotal, buildBadgeBoard } from '../utils/BadgeBoard';
import { ProfileStore, UserProfileData, PROFILE_TICK_KEY } from '../data/ProfileStore';
import { TripDao, TripSummary } from '../data/TripDao';
import { ProfileHeader } from '../components/ProfileHeader';
import { resolveDisplayImageUrl } from '../utils/DisplayMedia';
import { Pressable } from '../components/Pressable';
import { Logger } from '../common/logger/Logger';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { HdsChrome } from '../design/HdsChrome';
import { common } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { HdsNavigation, HdsNavigationTitleMode, HdsNavDestination, HdsNavDestinationTitleMode, HideMode } from '@kit.UIDesignKit';
import { requestSystemBarRefresh } from '../utils/systemBar';

@Component
export struct MinePage {
  // 深浅档代 tick：翻档时 EntryAbility 自增，@StorageProp 变化带动本页 build 重跑，
  // 把新 tick 传进 HdsChrome.bar → 标题内容换新 ComponentContent 重挂载、按当前档重解色
  // （官方 HdsTitleBar 自绘内容不随配置切换重渲染，真机实证见 HdsChrome.themeTick）
  @StorageProp('chromeThemeTick') chromeThemeTick: number = 0;

  /** true = 作为 dock 根页内联在 TabContent 里（路线 B），此时要自己挂 HdsNavigation */
  @Prop rootMode: boolean = false;
  /**
   * 内层 `HdsNavigation` 的绑定。2026-11-11 二级页全屏化后这条栈不再收任何子页；
   * ⚠ 绝不能绑 HOST_NAV——会把 Index 外层宿主的绑定抢走，二级页就渲染不出来。
   */
  private pathStack: NavPathStack = PROFILE_NAV;
  /** push 统一走宿主栈：二级页（ProfileEdit/Badges/Settings）全屏盖住 dock，宿主 Navigation 在 Index */
  private pushStack: NavPathStack = HOST_NAV;
  /** 切回这一格时重取勋章计数：在屏15 收了新章再切回来，不该还看到旧那份 */
  @StorageProp(TAB_SHOWN_KEY) @Watch('onDockShown') dockTick: string = '';
  /** 登录态：'' 水合中 / guest / huawei。资料区要跟它即时变 */
  @StorageProp(AUTH_STATE_KEY) authState: string = '';
  /** 权益变更（购买/刷新/登出）时即时刷新会员卡 */
  @StorageProp(EntitlementStore.TICK_KEY) @Watch('onEntitlementTick') entTick: number = 0;
  @State private badgeCount: number = 0;
  @State private cityCount: number = 0;
  /** 行程数：资料区统计行第一列（对标有据 关注/粉丝/获赞 三列位） */
  @State private tripCount: number = 0;
  /** 用户资料（昵称/简介）：编辑页保存后经 PROFILE_TICK_KEY 广播回显 */
  @State private profile: UserProfileData = { nickname: '', bio: '', gender: 0, avatar: '', profileBackground: '' };
  @StorageProp(PROFILE_TICK_KEY) @Watch('onProfileTick') profileTick: number = 0;
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

  /** 编辑资料页保存 → ProfileStore 广播 → 这里重读回显 */
  private onProfileTick(): void {
    this.reloadProfile();
  }

  /** 用户资料（昵称/简介）：编辑页返回后的显示层来源 */
  private reloadProfile(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ProfileStore.loadProfile(ctx, AccountStore.uid()).then((p: UserProfileData): void => {
      this.profile = p;
    }).catch((err: Error): void => {
      Logger.warn('Ui.Mine', `用户资料读取失败: ${err.message}`);
    });
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
    // 统计行第一列：行程数（只取个数，不展开列表——列表归「行程」格）
    TripDao.listSummaries(ctx).then((rows: TripSummary[]): void => {
      this.tripCount = rows.length;
    }).catch((err: Error): void => {
      Logger.warn('Ui.Mine', `行程计数读取失败: ${err.message}`);
    });
    this.reloadProfile();
    this.refreshMembership();
  }

  /**
   * 分享主页（对标有据：菜单 share 钮 → 分享）。有据走 ProfileShareSheet 全面板
   * （复制链接/复制卡片文字/系统分享，需要 profileUrl 基建）；有径还没有主页链接，
   * 先走系统分享面板带足迹概要文案——面板与链接基建等共享资料立项时再对齐。
   */
  private shareProfile(): void {
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const text: string = `我的有径足迹：${this.tripCount} 次行程 · ${this.badgeCount} 枚勋章 · 走过 ${this.cityCount} 座城市`;
    const data: systemShare.SharedData = new systemShare.SharedData({
      utd: 'general.plain-text',
      content: text,
      title: '我的有径主页'
    });
    const options: systemShare.ShareControllerOptions = {};
    new systemShare.ShareController(data).show(ctx, options).catch((err: Error): void => {
      Logger.warn('Ui.Mine', `系统分享失败: ${err.message}`);
    });
  }

  /**
   * 资料区 · 2026-11-10 直接搬有据 Index.profileHeroBlock + ProfileHeader 全套源码
   * （用户令「不要效仿，直接搬现成代码」）：
   * · 有背景图：16:10 Stack（Image Cover + #52000000 压暗层）+ ProfileHeader(true) 恒白字
   * · 无背景图：ProfileHeader(false) 主题字色（ProfileIdentity 双态自适配）
   * · 组件 = 有据同名文件原样（ProfileHeader/ProfileIdentity/ProfileStatItem/GlassPillButton/
   *   CountRoll），统计标签按旅行域换值（statLabels），域回调 onOpenFollowing/Followers 空实现
   * · 草稿箱/废纸篓 胶囊随组件保留（登录态渲染），路由属 UGC 域待共享资料立项
   */
  @Builder
  profileHeader() {
    if (this.profile.profileBackground !== '') {
      Column() {
        Stack() {
          Image(resolveDisplayImageUrl(this.profile.profileBackground))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .draggable(false)
          Column() {
            this.profileHeaderBlock(true)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.End)
          .backgroundColor('#52000000')
        }
        .width('100%')
        .aspectRatio(16 / 10)
        .borderRadius(RadiusTokens.lg)
        .clip(true)
      }
      .width('100%')
      .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm, top: SpaceTokens.xs, bottom: SpaceTokens.xs })
    } else {
      Column() {
        this.profileHeaderBlock(false)
      }
      .width('100%')
    }
  }

  /** 有据 profileHeaderBlock 同款：ProfileHeader 挂载段（参数域换值，结构原样） */
  @Builder
  profileHeaderBlock(onBackground: boolean) {
    ProfileHeader({
      avatar: this.profile.avatar,
      name: ProfileStore.displayName(this.profile),
      gender: this.profile.gender,
      bio: this.profile.bio,
      userId: 0,
      isLoggedIn: this.authState === 'huawei',
      followingCount: this.tripCount,
      followerCount: this.badgeCount,
      totalLikes: this.cityCount,
      statLabels: ['行程', '勋章', '足迹'],
      onBackground: onBackground,
      // 草稿箱/废纸篓是有据 UGC 域胶囊，有径无对应页——不渲染（用户裁定）
      showToolPills: false,
      onOpenFollowing: (): void => {},
      onOpenFollowers: (): void => {},
      onEdit: (): void => {
        this.pushStack.pushPath({ name: 'ProfileEdit' });
      },
      onOpenDrafts: (): void => {},
      onOpenTrash: (): void => {},
      onLogin: (): void => {
        this.goLogin();
      }
    })
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
    // 横向内缩在 ListItem 的 padding 上（hero 资料卡同款范式）：width('100%') 与横向
    // margin 同节点 = 100%+边距，卡面必然外溢屏幕（audit_button_width 同一条）
    .margin({ top: SpaceTokens.sm })
    .borderRadius(RadiusTokens.card)
    .backgroundColor(ColorTokens.surfaceElevated)
    .onClick((): void => {
      this.pushStack.pushPath({ name: 'Pricing' });
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
    // 同 memberCard：横向内缩归 ListItem padding，卡面 width('100%') 不再加横向 margin
    .margin({ top: SpaceTokens.sm })
    .borderRadius(RadiusTokens.card)
    .backgroundColor(ColorTokens.surfaceElevated)
    .onClick((): void => {
      this.pushStack.pushPath({ name: 'Badges' });
    })
  }

  @Builder
  body() {
    Column() {
      // 有据 ProfilePage 同款：List 无 space、无左右内缩——间距与呼吸全部由
      // 各项自带（资料卡 hero 内层 sm、内容项自带左右 sm），List 只管滚动。
      List({ scroller: this.barScroller }) {
        ListItem() {
          this.profileHeader()
        }
        ListItem() {
          this.memberCard()
        }
        // 横向内缩在这一层（hero 资料卡同款：包层让位、卡面撑满内容宽）
        .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm })
        ListItem() {
          this.medalCard()
        }
        .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm })
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .divider({ strokeWidth: 0 })
      // 末行住在悬浮 dock 底下，按实测净空让位（与 TripsPage/BadgePage 同一写法）
      .padding({ bottom: LayoutTokens.floatingDockClearance })
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
    this.getUIContext().getPromptAction().showToast({ message: '到「规划」格开始一趟行程即可登录' });
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
      .titleBar(HdsChrome.bar({ themeTick: this.chromeThemeTick,
        mainTitle: '我的',
        backSlot: false,
        scrolled: this.barScrolled,

        // 右上角官方圆钮排（对标有据 profileMenuItems）：分享在前、设置在后。
        // 原先的 plus(新建行程) 摘除——新建入口归「行程」格，「我的」只留身份动作。
        menu: [HdsChrome.item($r('app.media.action_share'), '分享主页', (): void => {
          this.shareProfile();
        }), HdsChrome.item($r('app.media.set_gear'), '设置', (): void => {
          this.pushStack.pushPath({ name: 'Settings' });
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
      .titleBar(HdsChrome.bar({ themeTick: this.chromeThemeTick,
        mainTitle: '我的',
        scrolled: this.barScrolled,
        menu: [HdsChrome.item($r('app.media.action_share'), '分享主页', (): void => {
          this.shareProfile();
        }), HdsChrome.item($r('app.media.set_gear'), '设置', (): void => {
          this.pushStack.pushPath({ name: 'Settings' });
        })]
      }))
      .titleMode(HdsNavDestinationTitleMode.MINI)
      // 不收栏（2026-11-08）：NavDestination 内容区恒预留 56vp 栏位、收栏后不回收，收起只留一条 175px 白带
      .bindToScrollable([this.barScroller])
      .clip(false)
    }
  }
}
