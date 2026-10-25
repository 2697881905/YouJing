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

import { APP_NAV, EditTarget, FailInfo } from '../common/constants/AppNav';
import { MAP_NAV, EXPENSE_NAV, MINE_NAV, ACTIVE_TRIP_KEY, PENDING_ROUTE_KEY,
  PENDING_PARAM_KEY, TAB_INDEX_KEY, TAB_ITINERARY, TAB_MAP, TAB_EXPENSE, TAB_MINE,
  tabOfRoute } from '../common/constants/AppNav';
import { TripDao, TripSummary } from '../data/TripDao';
import { common } from '@kit.AbilityKit';
import { YoujingStartPage } from './YoujingStartPage';
import { TripInputPage } from './TripInputPage';
import { PreferenceQAPage } from './PreferenceQAPage';
import { SpotPickPage } from './SpotPickPage';
import { StayPickPage } from './StayPickPage';
import { GeneratingPage } from './GeneratingPage';
import { ItineraryPage } from './ItineraryPage';
import { GenerateFailedPage } from './GenerateFailedPage';
import { EditItineraryPage } from './EditItineraryPage';
import { ExpensePage } from './ExpensePage';
import { TripsPage } from './TripsPage';
import { OnTripPage } from './OnTripPage';
import { SharePage } from './SharePage';
import { MapPage } from './MapPage';
import { AreaMorePage } from './AreaMorePage';
import { ComingSoonPage } from './ComingSoonPage';
import { HdsNavigation, HdsTabs, HdsTabsController } from '@kit.UIDesignKit';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { HDS_MATERIAL_LEVEL_EXQUISITE, HDS_MATERIAL_TYPE_IMMERSIVE } from '../utils/immersiveMaterial';

/**
 * 路由参数窄化（@Builder 内不允许局部 const，故放普通函数）：
 * typeof null === 'object'，必须先排掉 null 再断言，
 * 否则深链不带参数直达会抛 TypeError。
 */
function asFailInfo(param: object): FailInfo {
  const fallback: FailInfo = { code: 0, detail: '' };
  return (typeof param === 'object' && param !== null) ? param as FailInfo : fallback;
}

function asEditTarget(param: object): EditTarget {
  const fallback: EditTarget = { tripId: '', dayIndex: 0 };
  return (typeof param === 'object' && param !== null) ? param as EditTarget : fallback;
}

@Builder
function routerMap(name: string, param: object) {
  if (name === 'TripInput') {
    TripInputPage()
  } else if (name === 'PreferenceQA') {
    PreferenceQAPage()
  } else if (name === 'SpotPick') {
    SpotPickPage()
  } else if (name === 'StayPick') {
    StayPickPage()
  } else if (name === 'Generating') {
    GeneratingPage()
  } else if (name === 'Itinerary') {
    ItineraryPage({ tripId: typeof param === 'string' ? param as string : '' })
  } else if (name === 'GenerateFailed') {
    GenerateFailedPage({ code: asFailInfo(param).code, detail: asFailInfo(param).detail })
  } else if (name === 'EditItinerary') {
    EditItineraryPage({ tripId: asEditTarget(param).tripId, dayIndex: asEditTarget(param).dayIndex })
  } else if (name === 'Expense') {
    ExpensePage({ tripId: typeof param === 'string' ? param as string : '' })
  } else if (name === 'Trips') {
    TripsPage()
  } else if (name === 'OnTrip') {
    OnTripPage({ tripId: typeof param === 'string' ? param as string : '' })
  } else if (name === 'Share') {
    SharePage({ tripId: typeof param === 'string' ? param as string : '' })
  } else if (name === 'AreaMore') {
    AreaMorePage({ city: typeof param === 'string' ? param as string : '' })
  } else if (name === 'Map') {
    MapPage({ tripId: typeof param === 'string' ? param as string : '' })
  } else {
    ComingSoonPage()
  }
}

/**
 * tab 根页宿主。TabContent 首次可见才建、它的 Navigation 也那时才绑上栈，
 * 所以"进这个 tab 该看到的页面"不能由外部 push（会早于绑定、丢路由）：
 * 改由宿主在 aboutToAppear 里自推——冷启跨 tab 的深链也由这里消费。
 */
@Component
struct TabRootHost {
  stack: NavPathStack = APP_NAV;
  route: string = '';
  /** 成员名不能叫 tabIndex：与 CustomComponent 的内置成员冲突（编译器实测报错） */
  ownerTab: number = TAB_ITINERARY;
  tripScoped: boolean = false;

  aboutToAppear(): void {
    const pending: string | undefined = AppStorage.get<string>(PENDING_ROUTE_KEY);
    if (pending !== undefined && pending.length > 0 && tabOfRoute(pending) === this.ownerTab) {
      const param: string = AppStorage.get<string>(PENDING_PARAM_KEY) ?? '';
      AppStorage.setOrCreate(PENDING_ROUTE_KEY, '');
      AppStorage.setOrCreate(PENDING_PARAM_KEY, '');
      this.stack.pushPath({ name: pending, param: param });
      return;
    }
    if (this.route.length === 0 || this.stack.size() > 0) {
      return;
    }
    const tripId: string = AppStorage.get<string>(ACTIVE_TRIP_KEY) ?? '';
    if (this.tripScoped && tripId.length === 0) {
      // 地图/费用没有活跃行程就没有内容可画，留在占位上，不给一张空底图
      return;
    }
    this.stack.pushPath({ name: this.route, param: tripId });
  }

  build() {
    Column() {
      if (this.tripScoped && (AppStorage.get<string>(ACTIVE_TRIP_KEY) ?? '').length === 0) {
        Text('还没有可选行程')
          .fontSize(TypeTokens.caption.size)
          .fontColor(ColorTokens.muted)
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.canvas'))
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
    // 全新进程里 AppStorage 是空的：不种一条活跃行程，地图/费用 tab 只能对着占位发呆
    if ((AppStorage.get<string>(ACTIVE_TRIP_KEY) ?? '').length === 0) {
      TripDao.listSummaries(this.getUIContext().getHostContext() as common.Context)
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
