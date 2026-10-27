/**
 * 页签 → 导航栈的路由映射。
 *
 * 为什么值得单独钉：主链复审查出的那个 P0 就是"页面写死 `APP_NAV`"——
 * 从「我的」页签点开的行程页，它自己的四个按钮（全图/编辑/分享/日历）
 * 全推在一条看不见的栈上，点了没反应。修法是全页改走 `ctx.pathStack` /
 * `stackOfTab(index)`。这类缺陷在真机上一屏一屏拍是拍不出"按钮画得好好的但失灵"的，
 * 而映射本身是纯的：给一个页签序号，必须拿到那条**唯一**的栈。
 * 以后谁再加第五个页签或调换顺序，这条会先红。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import {
  APP_NAV, MAP_NAV, EXPENSE_NAV, MINE_NAV, stackOfTab, tabOfRoute,
  TAB_ITINERARY, TAB_MAP, TAB_EXPENSE, TAB_MINE
} from '../../../main/ets/common/constants/AppNav';

export default function navStackTest(): void {
  describe('NavStackRouting', () => {

    it('each_tab_gets_its_own_stack', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(stackOfTab(TAB_ITINERARY) === APP_NAV).assertTrue();
      expect(stackOfTab(TAB_MAP) === MAP_NAV).assertTrue();
      expect(stackOfTab(TAB_EXPENSE) === EXPENSE_NAV).assertTrue();
      expect(stackOfTab(TAB_MINE) === MINE_NAV).assertTrue();
    });

    it('tabs_do_not_share_a_stack', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      // 四条栈必须是四个不同实例——共用一条就是"在 A 页签 push，B 页签也跟着变"。
      // 这里按实例去重，不是按数组长度：长度永远是 4，那样的断言等于没断言。
      const distinct: NavPathStack[] = [];
      [TAB_ITINERARY, TAB_MAP, TAB_EXPENSE, TAB_MINE].forEach((i: number) => {
        const s: NavPathStack = stackOfTab(i);
        if (distinct.indexOf(s) < 0) {
          distinct.push(s);
        }
      });
      expect(distinct.length).assertEqual(4);
    });

    it('unknown_index_falls_back_to_app_stack', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(stackOfTab(99) === APP_NAV).assertTrue();
      expect(stackOfTab(-1) === APP_NAV).assertTrue();
    });

    it('route_lands_on_the_tab_that_owns_it', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      // 深链进来要先切到归属页签，否则 push 落在当前页签的栈上、用户看不到落点
      expect(tabOfRoute('Map')).assertEqual(TAB_MAP);
      expect(tabOfRoute('Expense')).assertEqual(TAB_EXPENSE);
      expect(tabOfRoute('Trips')).assertEqual(TAB_MINE);
    });
  });
}
