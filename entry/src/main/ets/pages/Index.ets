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

import { APP_NAV, ACTIVE_TRIP_KEY, TAB_INDEX_KEY, TAB_ITINERARY, TAB_MAP, TAB_EXPENSE, TAB_MINE } from '../common/constants/AppNav';
import { routerMap } from './AppRouter';
import { TripDao, TripSummary } from '../data/TripDao';
import { AccountStore } from '../data/AccountStore';
import { common } from '@kit.AbilityKit';
import { YoujingStartPage } from './YoujingStartPage';
import { MapPage } from './MapPage';
import { ExpensePage } from './ExpensePage';
import { TripsPage } from './TripsPage';
import { HdsNavigation, HdsTabs, HdsTabsController } from '@kit.UIDesignKit';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { HDS_MATERIAL_LEVEL_EXQUISITE, HDS_MATERIAL_TYPE_IMMERSIVE } from '../utils/immersiveMaterial';

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
        MapPage({ rootMode: true })
      }
      .tabBar(this.tabLabel(TAB_MAP))

      TabContent() {
        ExpensePage({ rootMode: true })
      }
      .tabBar(this.tabLabel(TAB_EXPENSE))

      TabContent() {
        TripsPage({ rootMode: true })
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
