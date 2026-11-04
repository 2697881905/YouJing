/**
 * 应用根 · 官方 HdsTabs 四页签骨架（对齐「有据」定稿：底部悬浮页签是导航的一部分，不是页面自己贴的条）。
 *
 * 四条栈 = 四个 TabContent：`APP_NAV` 仍是**行程 tab**（主链 16 个文件都往它 push，
 * 名字不动以维持最小改动），地图/费用/我的各一条。切页签由官方组件自己管，
 * 每 tab 的返回栈互不干扰。
 *
 * 冷启深链为什么用 `index` 而不是 `changeIndex`：上一版在 aboutToAppear / onDidBuild /
 * @StorageLink+@Watch 三条路径里都调过 `hdsController.changeIndex()`，真机 dumpLayout
 * 实测全部停在 tab 0——Tabs 建完再切这条路在本机不成立。`HdsTabsOptions extends TabsOptions`
 * 且 `index?: number`（默认 0），所以把外部深链要落的页签**作为初始值**传进构造参数，
 * 首帧就在目标 tab；运行期（App 已存活时的 onNewWant）才用 changeIndex。
 */

import { APP_NAV, ACTIVE_TRIP_KEY, TAB_INDEX_KEY, TAB_SWITCH_KEY, DOCK_TABS, announceTabShown, stackOfTab, TAB_PLAN, TAB_ITINERARY, TAB_MAP, TAB_EXPENSE, TAB_MINE, PLAN_SCROLL_KEY } from '../common/constants/AppNav';
import { routerMap } from './AppRouter';
import { TripDao, TripSummary } from '../data/TripDao';
import { AUTH_STATE_KEY } from '../data/AccountStore';
import { ConsentStore, CONSENT_AGREED_KEY } from '../utils/ConsentStore';
import { PrivacyConsentDialog } from '../components/PrivacyConsentDialog';
import { LoginView } from './LoginView';
import { Logger } from '../common/logger/Logger';
import { AccountStore } from '../data/AccountStore';
import { AccountState } from '../model/Account';
import { EntitlementStore } from '../data/EntitlementStore';
import { DeviceTokenStore } from '../data/DeviceTokenStore';
import { DeviceActivator } from '../data/DeviceActivator';
import { common } from '@kit.AbilityKit';
import { YoujingStartPage } from './YoujingStartPage';
import { MapPage } from './MapPage';
import { ExpensePage } from './ExpensePage';
import { TripsPage } from './TripsPage';
import { MinePage } from './MinePage';
import { HdsNavigation, HdsNavigationTitleMode, HdsTabs, HdsTabsController } from '@kit.UIDesignKit';
import { HdsChrome } from '../design/HdsChrome';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { HDS_MATERIAL_LEVEL_EXQUISITE, HDS_MATERIAL_TYPE_IMMERSIVE } from '../utils/immersiveMaterial';
import { TopStrip, TOP_STRIP_KEY, STRIP_CANVAS, STRIP_MAP } from '../utils/TopStrip';

const TAG: string = 'Index';

@Entry
@Component
struct Index {
  /** 外部深链（小艺 / 卡片 / aa start）写这个键；作为 HdsTabs 的**初始页签**消费 */
  @StorageLink(TAB_INDEX_KEY) wantTab: number = TAB_PLAN;
  @State private currentTab: number = TAB_PLAN;
  /** 运行期切页签的请求（AppNav.enterPlanningFlow 写）；冷启不走这条路 */
  @StorageProp(TAB_SWITCH_KEY) @Watch('applyTabSwitch') tabSwitch: string = '';
  /**
   * 状态栏高度（vp）。窗口铺满物理屏之后，页面是从窗口 y=0 起排的，而 `TabContent`
   * 仍按安全区在状态栏下沿裁切 —— 不让位的话每屏顶部都会少一截（真机实测
   * 「有径」标题 144px 的框被裁成 50px）。让位收在壳层这一处，
   * 20 个页面不用各自读避让区（见 EntryAbility.makeImmersive）。
   */
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  /**
   * 底部指示条高度（vp）。`barBottomMargin` 是从**容器底**量的，窗口铺满物理屏之后
   * 容器底就是物理屏底，所以这一格必须自己加回去 —— 不加，dock 会从契约钉的
   * 「28px above the system nav inset」掉到指示条上沿（真机实测掉 27.8vp，
   * 连带让 `floatingDockClearance: 112` 多让了 27.8vp）。
   */
  @StorageProp('navIndicatorHeight') navIndicatorHeight: number = 0;
  /**
   * 顶部该用哪个底色资源名（画布 / 底图基色），与系统带同源、由 TopStrip 写。
   * 壳层 Column 必须跟着换：栏是透明的，栏区露的就是这层的底色 ——
   * 只换系统带不换这里，顶边会多出第二条色差（真机实测带子 56、栏区 18）。
   */
  @StorageProp(TOP_STRIP_KEY) stripName: string = STRIP_CANVAS;
  /** 规划格的顶栏磨砂：滚动容器在 YoujingStartPage 里，状态经 PLAN_SCROLL_KEY 递过来 */
  @StorageProp(PLAN_SCROLL_KEY) planBarScrolled: boolean = false;
  private hdsController: HdsTabsController = new HdsTabsController();

  /** 解析 'index:timestamp' 并切到该页签；同页签或解析不出就什么都不做 */
  private applyTabSwitch(): void {
    const head: string = this.tabSwitch.split(':')[0];
    const target: number = Number(head);
    if (Number.isNaN(target) || target < 0 || target >= DOCK_TABS.length || target === this.currentTab) {
      return;
    }
    this.hdsController.changeIndex(target);
    this.currentTab = target;
  }

  aboutToAppear(): void {
    this.currentTab = this.wantTab;
    this.syncTopStrip(this.wantTab);
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    ConsentStore.init(ctx)
      .then((agreed: boolean): void => {
        if (agreed) {
          this.bootstrap(ctx);
        } else {
          this.consentDialog.open();
        }
      })
      .catch((): void => {
        this.consentDialog.open();
      });
  }

  private bootstrap(ctx: common.Context): void {
    // 顺序有讲究：激活要用「当前账号的 idToken」，而 AccountStore 的登录态是异步恢复的。
    // 三者并行时曾在亚稳态下把已登录用户按游客激活（D10 之后游客与账号是不同 BFF 账号）。
    const accountReady: Promise<AccountState> = AccountStore.init(ctx);
    accountReady
      .then((): Promise<void> => DeviceTokenStore.init(ctx))
      .then((): Promise<boolean> => DeviceActivator.activate(ctx))
      .catch((): void => {});
    EntitlementStore.init(ctx).catch((): void => {});
    accountReady
      .then((): Promise<TripSummary[]> => TripDao.listSummaries(ctx))
      .then((rows: TripSummary[]): void => {
        if (rows.length > 0) {
          AppStorage.setOrCreate(ACTIVE_TRIP_KEY, rows[0].id);
        }
      })
      .catch((): void => {
      });
  }

  /**
   * dock 五个页签。**选中态用蓝色 `primary` 是用户 2026-10-26 明确拍的板**
   * （「深色 dock 选中蓝 4.46:1，差 AA 0.04，维持 #0A84FF 不改」，且选中蓝是深色帧定的值），
   * 不要为了让对比度尺变绿把它换掉。
   * 2026-11-01 逐屏走查补一条新事实供裁决：dock 是半透明材质，透的是底下那块屏 ——
   * 画布上玻璃底 lum 0.016、**地图格上 0.056（亮约三倍）**，实测选中蓝在这两处是
   * 4.39:1 与 **3.05:1**，未选中 `muted` 在地图格上是 4.24~4.77:1。当年那次决定量的是
   * 画布那一侧（4.46），地图格这一侧从没进过视野。
   */
  @Builder
  tabLabel(idx: number) {
    Column({ space: SpaceTokens.xxs }) {
      SymbolGlyph(DOCK_TABS[idx].symbol)
        .fontSize(IconSizes.control)
        .fontColor([this.currentTab === idx ? ColorTokens.primary : ColorTokens.icon])
      Text(DOCK_TABS[idx].label)
        .fontSize(TypeTokens.navLabel.size)
        .fontWeight(this.currentTab === idx ? 500 : TypeTokens.navLabel.weight)
        .fontColor(this.currentTab === idx ? ColorTokens.primary : ColorTokens.muted)
    }
    .height(LayoutTokens.tabItemHeight)
    .justifyContent(FlexAlign.Center)
    .accessibilityText(`${DOCK_TABS[idx].label}页签`)
  }

  /** 登录态：'' 水合中 / guest / huawei（AccountStore 推的 AppStorage 键） */
  @StorageProp(AUTH_STATE_KEY) authState: string = '';
  @StorageProp(CONSENT_AGREED_KEY) consentAgreed: string = '0';
  /** 本次会话内主动选了游客空间——冷启仍然先看登录页，不做静默跳过 */
  @State private guestChosen: boolean = false;
  private consentDialog: CustomDialogController = new CustomDialogController({
    builder: PrivacyConsentDialog({
      onAgree: (): void => {
        ConsentStore.agree().catch((): void => {});
        this.consentDialog.close();
        const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
        this.bootstrap(ctx);
      },
      onDecline: (): void => {
        ConsentStore.decline();
        (this.getUIContext().getHostContext() as common.UIAbilityContext).terminateSelf();
      },
      onOpenDoc: (kind: string): void => {
        // 正文已在弹窗内就地展开，这里只留一条埋点
        Logger.info(TAG, `查看协议原文 kind=${kind}`);
      }
    }),
    autoCancel: false,
    // 同意前 Back / Esc / 侧滑都不许把闸门关掉：否则「退出应用」那条出口被绕过，
    // 用户没同意也能继续用（真机实测 Back 能直接关掉，同意态仍是未同意）
    onWillDismiss: (action: DismissDialogAction): void => {
      if (ConsentStore.isAgreed()) {
        action.dismiss();
      }
    },
    alignment: DialogAlignment.Center
  });

  /**
   * 顶部系统带跟着页签换色：只有地图格是满铺底图，带子涂画布会在它上面压出一条
   * 硬色差（真机实测带子 18、底图 56~75）；其余四格顶边就是画布，涂画布才对。
   * 但"在地图格"还不够 —— 从地图栏上压进屏15 之后，屏幕顶上是**那一页**的栏带（画布），
   * 带子若仍留蓝灰就在 y=106 撞出一道 Δ38 的缝，所以还要问一句栈顶是不是地图自己。
   * 栈内那一跳由 MapPage 的 interception 负责（见 pages/MapPage.bindStripToStackTop）。
   */
  private syncTopStrip(index: number): void {
    TopStrip.apply(this.getUIContext().getHostContext() as common.UIAbilityContext,
      index === TAB_MAP && stackOfTab(TAB_MAP).size() === 0 ? STRIP_MAP : STRIP_CANVAS);
  }

  @Builder
  mainTabs() {
    HdsTabs({ controller: this.hdsController, index: this.wantTab }) {
      // 顺序必须与 AppNav 的 TAB_* 常量、DOCK_TABS 下标逐一对齐，三者错位的后果见 AppNav 注释
      TabContent() {
        MapPage({ rootMode: true })
      }
      .tabBar(this.tabLabel(TAB_MAP))

      TabContent() {
        TripsPage({ rootMode: true })
      }
      .tabBar(this.tabLabel(TAB_ITINERARY))

      // 规划 tab：门面 + 屏2→屏6 向导链都走 APP_NAV（主链 16 个文件的字段不动）。
      // 2026-11-03 主功能页化：挂官方标题栏（与其余四格同构），页面内不再自绘品牌块——
      // 「规划」页作为主功能页从官方栏起排，滚动磨砂走 HdsChrome 的既定两态。
      TabContent() {
        HdsNavigation(APP_NAV) {
          YoujingStartPage()
        }
        .navDestination(routerMap)
        .mode(NavigationMode.Stack)
        .titleMode(HdsNavigationTitleMode.MINI)
        .hideBackButton(true)
        .titleBar(HdsChrome.bar({ mainTitle: '规划', scrolled: this.planBarScrolled }))
        .backgroundColor($r('app.color.canvas'))
      }
      .tabBar(this.tabLabel(TAB_PLAN))

      TabContent() {
        ExpensePage({ rootMode: true })
      }
      .tabBar(this.tabLabel(TAB_EXPENSE))

      TabContent() {
        MinePage({ rootMode: true })
      }
      .tabBar(this.tabLabel(TAB_MINE))
    }
    .barPosition(BarPosition.End)
    .vertical(false)
    .scrollable(false)
    .barOverlap(true)
    .barFloatingStyle({
      // 材质走官方数值（IMMERSIVE=101 / EXQUISITE=0）：不静态 import hdsMaterial，
      // 该模块在低版本设备上不存在，import 即崩（immersiveMaterial.ets 的兼容性铁律）
      systemMaterialEffect: {
        materialType: HDS_MATERIAL_TYPE_IMMERSIVE,
        materialLevel: HDS_MATERIAL_LEVEL_EXQUISITE
      },
      barBottomMargin: LayoutTokens.floatingDockBottomMargin + this.navIndicatorHeight,
      barSideMargin: LayoutTokens.pagePadding
    })
    .onChange((index: number): void => {
      this.currentTab = index;
      AppStorage.setOrCreate(TAB_INDEX_KEY, index);
      this.syncTopStrip(index);
      // 五个 tab 根页只在 aboutToAppear 取一次数：在别处新建/编辑完行程、记完费用
      // 再切回页签，看到的还是第一次进入那份。广播一条，根页序号对上才重取
      announceTabShown(index);
    })
    // 重点**当前**页签时 onChange 不触发（同值），系统惯例是"再点一次 = 回到这一页签的根"。
    // 原来这条路径上什么都不发生：从「我的」点开行程后再点「我的」，界面纹丝不动，
    // 用户读到的就是"dock 坏了"（§5m 记的 P2）。Tabs 继承来的 onTabBarClick 每次都触发。
    .onTabBarClick((index: number): void => {
      if (index !== this.currentTab) {
        return;
      }
      const stack: NavPathStack = stackOfTab(index);
      if (stack.size() > 0) {
        stack.clear();
      }
      this.syncTopStrip(index);
      // 回根和切页签一样算「这一页重新露面」：刚生成的行程要在首页立刻出现
      announceTabShown(index);
    })
    .width('100%')
    .height('100%')
    // 状态栏避让交给栏体自己做，不在壳层垫。
    // 为什么：`HdsChrome.bar` 早就双开了 `avoidLayoutSafeArea: true` + `enableComponentSafeArea: true`
    // （有据首页同一配方），但这道 padding 把整个 HdsNavigation 往下挪了 34vp——
    // 栏体避让的是它自己坐标系里已经不存在的安全区，而带子归壳层涂。
    // 于是深色档滚动时栏体的渐变遮罩只压暗 y=106 以下，带子仍是画布：
    // 真机量到带子 L=18 / 栏体 L=11 一条硬台阶（用户长期报的「通知栏有色差、布局没撑满」）。
    // 撤掉 padding 后栏体从窗口 0 排起，遮罩与带子是同一层，缝没有第二个来源。
    // 全仓只有这一处读 statusBarHeight（已 grep 确认），没有页面会重复让位。
  }

  build() {
    Column() {
      if (this.consentAgreed !== '1') {
        Blank()
      } else if (this.authState === '') {
        Blank()
      } else if (this.authState !== 'huawei' && !this.guestChosen) {
        LoginView({
          onSignedIn: (): void => {
            Logger.info(TAG, '登录完成，进入主界面');
          },
          onGuest: (): void => {
            this.guestChosen = true;
            Logger.info(TAG, '用户主动选择本机游客空间');
          },
          onOpenDoc: (kind: string): void => {
            // 正文由登录页自己的半模态承载，这里只留一条埋点
            Logger.info(TAG, `登录页查看协议原文 kind=${kind}`);
          }
        })
      } else {
        this.mainTabs()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.stripName === STRIP_MAP ? $r('app.color.map_strip_base') : $r('app.color.canvas'))
  }
}
