/**
 * 页签 → 导航栈的路由映射。
 *
 * 为什么值得单独钉：主链复审查出的那个 P0 就是"页面写死 `APP_NAV`"——
 * 从「我的」页签点开的行程页，它自己的四个按钮（全图/编辑/分享/日历）
 * 全推在一条看不见的栈上，点了没反应。修法是全页改走 `ctx.pathStack` /
 * `stackOfTab(index)`。这类缺陷在真机上一屏一屏拍是拍不出"按钮画得好好的但失灵"的，
 * 而映射本身是纯的：给一个页签序号，必须拿到那条**唯一**的栈。
 *
 * 2026-11-11 二级页全屏化后映射改了形状：**所有子页一律落宿主栈 HOST_NAV**
 * （全屏盖住 dock，不显示页签栏、不随 HdsTabs 左右滑切页）；页签栈只承载五个根页。
 * 所以"最值钱的断言"从「tabOfRoute 与 stackOfRoute 同栈」改成
 * 「stackOfRoute 恒等 HOST_NAV」——万一有人把子页推回某条页签栈，
 * 它就会渲染在 TabContent 里，dock 与横滑切页跟着回来。
 *
 * 四格改五格之后，这个文件还多担一件事：**页签序号重排**
 * （地图0/行程1/规划2/费用3/我的4）。错位不会崩，只会让某个根页的
 * `isTabShownTick` 永远对不上而静默不刷新，或让深链把页面 push 进不可见的栈。
 * 所以下面几条穷举断言是这类"静默错位"唯一的程序化闸门。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import {
  APP_NAV, MAP_NAV, EXPENSE_NAV, TRIPS_NAV, PROFILE_NAV, HOST_NAV,
  stackOfTab, stackOfRoute, tabOfRoute, isTabRoot,
  TAB_MAP, TAB_ITINERARY, TAB_PLAN, TAB_EXPENSE, TAB_MINE
} from '../../../main/ets/common/constants/AppNav';

/** 五个页签序号，按 dock 从左到右 */
const ALL_TABS: number[] = [TAB_MAP, TAB_ITINERARY, TAB_PLAN, TAB_EXPENSE, TAB_MINE];

/** 深链会用到的全部路由名（与 AppRouter.routerMap 的分支保持人工同步） */
const ROUTE_NAMES: string[] = [
  'TripInput', 'PreferenceQA', 'SpotPick', 'StayPick', 'AreaMore', 'Generating',
  'GenerateFailed', 'Itinerary', 'EditItinerary', 'OnTrip', 'Share', 'Review',
  'Badges', 'Settings', 'Map', 'Expense', 'Trips'
];

export default function navStackTest(): void {
  describe('NavStackRouting', () => {

    it('each_tab_gets_its_own_stack', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(stackOfTab(TAB_MAP) === MAP_NAV).assertTrue();
      expect(stackOfTab(TAB_ITINERARY) === TRIPS_NAV).assertTrue();
      // 规划 tab 复用 APP_NAV：主链 16 个文件的 pathStack 字段不用动
      expect(stackOfTab(TAB_PLAN) === APP_NAV).assertTrue();
      expect(stackOfTab(TAB_EXPENSE) === EXPENSE_NAV).assertTrue();
      expect(stackOfTab(TAB_MINE) === PROFILE_NAV).assertTrue();
    });

    it('tabs_do_not_share_a_stack', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      // 五条栈必须是五个不同实例——共用一条就是"在 A 页签 push，B 页签也跟着变"。
      // 这里按实例去重，不是按数组长度：长度永远是 5，那样的断言等于没断言。
      const distinct: NavPathStack[] = [];
      ALL_TABS.forEach((i: number) => {
        const s: NavPathStack = stackOfTab(i);
        if (distinct.indexOf(s) < 0) {
          distinct.push(s);
        }
      });
      expect(distinct.length).assertEqual(5);
    });

    it('tab_indices_are_five_consecutive_distinct_values',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
        // 序号重排最容易出的错是两个页签拿到同一个值：那样 changeIndex 只能切到一个。
        const seen: number[] = [];
        ALL_TABS.forEach((i: number) => {
          expect(seen.indexOf(i) < 0).assertTrue();
          seen.push(i);
        });
        expect(seen.length).assertEqual(5);
        // 且必须正好铺满 0..4，HdsTabs 的 index 与 TabContent 顺序才对得上
        seen.sort((a: number, b: number): number => a - b);
        for (let i = 0; i < 5; i++) {
          expect(seen[i]).assertEqual(i);
        }
      });

    it('secondary_routes_all_land_on_host_stack', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      /**
       * 核心不变量（2026-11-11 二级页全屏化）：**所有路由落点都是宿主栈 HOST_NAV**。
       *
       * `EntryAbility.routeTo` 先用 `tabOfRoute` 决定底下切到哪个页签、
       * 再把子页 push 到 `stackOfRoute` 给的栈。子页一旦落回某条页签栈，
       * 就会渲染进 TabContent——dock 页签栏与 HdsTabs 左右滑切页跟着回来，
       * 正是用户报的"二级页面能滑走切页、还显示底部 TabBar"。穷举拦住它。
       */
      ROUTE_NAMES.forEach((n: string) => {
        expect(stackOfRoute(n) === HOST_NAV).assertTrue();
      });
    });

    it('unknown_index_falls_back_to_app_stack', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(stackOfTab(99) === APP_NAV).assertTrue();
      expect(stackOfTab(-1) === APP_NAV).assertTrue();
    });

    it('route_lands_on_the_tab_that_owns_it', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      // 深链进来要先切到归属页签（宿主栈盖住的是这个页签的根页），否则 pop 回来时
      // 用户看到的是另一个页签，位置感就断了
      expect(tabOfRoute('Map')).assertEqual(TAB_MAP);
      expect(tabOfRoute('Expense')).assertEqual(TAB_EXPENSE);
      // 「行程」列表从旧的「我的」页签搬走了，这条断言就是那次搬家留下的锚
      expect(tabOfRoute('Trips')).assertEqual(TAB_ITINERARY);
      expect(tabOfRoute('Badges')).assertEqual(TAB_MINE);
      // 设置页从「我的」右上角齿轮进，深链也必须落回我的格
      expect(tabOfRoute('Settings')).assertEqual(TAB_MINE);
      // 规划链与它的产物都归规划 tab
      expect(tabOfRoute('TripInput')).assertEqual(TAB_PLAN);
      expect(tabOfRoute('Itinerary')).assertEqual(TAB_PLAN);
    });

    it('tab_roots_are_not_pushed_onto_their_own_stack',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
        // 根页内联在各自 TabContent 里（路线 B），routeTo 靠这个判定决定要不要 push；
        // 判错的后果是切到页签后又叠一层同样的根页
        expect(isTabRoot('Map')).assertTrue();
        expect(isTabRoot('Trips')).assertTrue();
        expect(isTabRoot('Expense')).assertTrue();
        expect(isTabRoot('Mine')).assertTrue();
        expect(isTabRoot('Badges')).assertFalse();
        expect(isTabRoot('TripInput')).assertFalse();
      });
  });
}
