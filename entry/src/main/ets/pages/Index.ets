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

import { APP_NAV, MAP_NAV, EXPENSE_NAV, MINE_NAV, ACTIVE_TRIP_KEY, PENDING_ROUTE_KEY,
  PENDING_PARAM_KEY, TAB_INDEX_KEY, TAB_ITINERARY, TAB_MAP, TAB_EXPENSE, TAB_MINE,
  tabOfRoute } from '../common/constants/AppNav';
import { routerMap } from './AppRouter';
import { TripDao, TripSummary } from '../data/TripDao';
import { AccountStore } from '../data/AccountStore';
import { common } from '@kit.AbilityKit';
import { YoujingStartPage } from './YoujingStartPage';
import { HdsNavigation, HdsTabs, HdsTabsController } from '@kit.UIDesignKit';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { HDS_MATERIAL_LEVEL_EXQUISITE, HDS_MATERIAL_TYPE_IMMERSIVE } from '../utils/immersiveMaterial';

/**
 * tab 根页宿主。TabContent 首次可见才建，所以"进这个 tab 该看到的页面"不能由外部 push
 * （会早于绑定、丢路由）：改由宿主自己推。
 *
 * 待路由和活跃行程都挂成响应式，不能只在创建时读一次：TabContent 建完后一直活着，
 * 同一个 tab 的第二次深链再没有创建期回调来消费，路由就静默丢了；
 * 而活跃行程是异步种下的，首帧读到的空值会把占位文案永久钉在屏幕上。
 */
@Component
struct TabRootHost {
  stack: NavPathStack = APP_NAV;
  route: string = '';
  /** 成员名不能叫 tabIndex：与 CustomComponent 的内置成员冲突（编译器实测报错） */
  ownerTab: number = TAB_ITINERARY;
  tripScoped: boolean = false;
  @StorageProp(PENDING_ROUTE_KEY) @Watch('onPendingChange') pendingRoute: string = '';
  @StorageProp(ACTIVE_TRIP_KEY) @Watch('onActiveTripChange') activeTripId: string = '';

  onPendingChange(): void {
    this.routeOwnTab();
  }

  onActiveTripChange(): void {
    this.routeOwnTab();
  }

  /** 深链指向本 tab 就消费掉；否则确保本 tab 的根页在栈上（没有活跃行程时留在占位） */
  routeOwnTab(): void {
    if (this.pendingRoute.length > 0 && tabOfRoute(this.pendingRoute) === this.ownerTab) {
      const param: string = AppStorage.get<string>(PENDING_PARAM_KEY) ?? '';
      AppStorage.setOrCreate(PENDING_ROUTE_KEY, '');
      AppStorage.setOrCreate(PENDING_PARAM_KEY, '');
      this.stack.pushPath({ name: this.pendingRoute, param: param });
      return;
    }
    if (this.route.length === 0 || this.stack.size() > 0) {
      return;
    }
    if (this.tripScoped && this.activeTripId.length === 0) {
      // 地图/费用没有活跃行程就没有内容可画，留在占位上，不给一张空底图
      return;
    }
    this.stack.pushPath({ name: this.route, param: this.activeTripId });
  }

  build() {
    Column() {
      if (this.tripScoped && this.activeTripId.length === 0) {
        Text('还没有可选行程')
          .fontSize(TypeTokens.caption.size)
          .fontColor(ColorTokens.muted)
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.canvas'))
    // 首帧路由挂在内容的 onAppear，而不是 aboutToAppear：后者跑在宿主自己的 Navigation
    // 把栈绑上之前，那时 push 出来的落点解析不出来（真机证据：冷启 route=Expense
    // 落 ComingSoonPage，§4k ④）。routeOwnTab 幂等，页签反复出现再走一次也无害。
    .onAppear((): void => {
      this.routeOwnTab();
    })
  }
}

interface DockTab {
  label: string;
  symbol: Resource;
}

const DOCK_TABS: DockTab[] = [
  { label: '行程', symbol: $r('sys.symbol.calendar') },
  { label: '地图', symbol: $r('sys.symbol.map') },
  { label: '费用', symbol: $r('sys.symbol.wallet') },
  { label: '我的', symbol: $r('sys.symbol.person') }
];

@Entry
@Component
struct Index {
  /** 外部深链（小艺 / 卡片 / aa start）写这个键；作为 HdsTabs 的**初始页签**消费 */
  @StorageLink(TAB_INDEX_KEY) wantTab: number = TAB_ITINERARY;
  @State private currentTab: number = TAB_ITINERARY;
  private hdsController: HdsTabsController = new HdsTabsController();

  aboutToAppear(): void {
    this.currentTab = this.wantTab;
    // 全新进程里 AppStorage 是空的：不种一条活跃行程，地图/费用 tab 只能对着占位发呆。
    // 但必须先等登录态恢复——DAO 一律按 AccountStore.uid() 收口分区，
    // 而 aboutToAppear 跑在 EntryAbility.bootstrap 的 await init 之前，
    // 直接用游客键种出来的行程 id 到真账号分区里查不到，地图 tab 会对着空底图。
    if ((AppStorage.get<string>(ACTIVE_TRIP_KEY) ?? '').length === 0) {
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      AccountStore.init(ctx)
        .then((): Promise<TripSummary[]> => TripDao.listSummaries(ctx))
        .then((rows: TripSummary[]): void => {
          if (rows.length > 0) {
            AppStorage.setOrCreate(ACTIVE_TRIP_KEY, rows[0].id);
          }
        })
        .catch((): void => {
        });
    }
  }

  @Builder
  tabLabel(idx: number) {
    Column({ space: SpaceTokens.xs }) {
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

  build() {
    HdsTabs({ controller: this.hdsController, index: this.wantTab }) {
      TabContent() {
        HdsNavigation(APP_NAV) {
          YoujingStartPage()
        }
        .navDestination(routerMap)
        .mode(NavigationMode.Stack)
        .hideTitleBar(true)
        .backgroundColor($r('app.color.canvas'))
      }
      .tabBar(this.tabLabel(TAB_ITINERARY))

      TabContent() {
        HdsNavigation(MAP_NAV) {
          TabRootHost({ stack: MAP_NAV, route: 'Map', ownerTab: TAB_MAP, tripScoped: true })
        }
        .navDestination(routerMap)
        .mode(NavigationMode.Stack)
        .hideTitleBar(true)
        .backgroundColor($r('app.color.canvas'))
      }
      .tabBar(this.tabLabel(TAB_MAP))

      TabContent() {
        HdsNavigation(EXPENSE_NAV) {
          TabRootHost({ stack: EXPENSE_NAV, route: 'Expense', ownerTab: TAB_EXPENSE,
            tripScoped: true })
        }
        .navDestination(routerMap)
        .mode(NavigationMode.Stack)
        .hideTitleBar(true)
        .backgroundColor($r('app.color.canvas'))
      }
      .tabBar(this.tabLabel(TAB_EXPENSE))

      TabContent() {
        HdsNavigation(MINE_NAV) {
          TabRootHost({ stack: MINE_NAV, route: 'Trips', ownerTab: TAB_MINE })
        }
        .navDestination(routerMap)
        .mode(NavigationMode.Stack)
        .hideTitleBar(true)
        .backgroundColor($r('app.color.canvas'))
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
      barBottomMargin: LayoutTokens.floatingDockBottomMargin,
      barSideMargin: LayoutTokens.pagePadding
    })
    .onChange((index: number): void => {
      this.currentTab = index;
      AppStorage.setOrCreate(TAB_INDEX_KEY, index);
    })
    .width('100%')
    .height('100%')
  }
}
