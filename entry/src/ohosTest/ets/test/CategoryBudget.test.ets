/**
 * 分类预算（屏11）纯逻辑回归：存量 JSON 解析、上限取值、画条基线与百分比。
 * 这三件事都可离线断言，且不碰 RDB——解析函数此前埋在 TripDao 里就等于测不到。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import {
  barBase, barPct, budgetOf, parseCategoryBudgets
} from '../../../main/ets/utils/CategoryBudget';
import { CategoryBudget } from '../../../main/ets/model/Expense';
import { ExpenseCategory } from '../../../main/ets/model/Expense';

export default function categoryBudgetTest(): void {
  describe('CategoryBudget', () => {
    it('missing_or_dirty_json_yields_empty_not_guess',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
        expect(parseCategoryBudgets(null).length).assertEqual(0);
        expect(parseCategoryBudgets('').length).assertEqual(0);
        expect(parseCategoryBudgets('not json').length).assertEqual(0);
        // 存量库没有这一列时默认 '[]'
        expect(parseCategoryBudgets('[]').length).assertEqual(0);
      });

    it('only_known_codes_and_positive_amounts_survive',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
        const list: CategoryBudget[] = parseCategoryBudgets(
          '[{"category":"ticket","amount":1200},{"category":"flight","amount":900},' +
            '{"category":"food","amount":0},{"category":"hotel","amount":-5},' +
            '{"category":"shop","amount":880.6},null]');
        expect(list.length).assertEqual(2);
        expect(list[0].category).assertEqual(ExpenseCategory.TICKET);
        expect(list[0].amount).assertEqual(1200);
        // 金额取整（屏11 一律整数元）
        expect(list[1].amount).assertEqual(881);
      });

    it('budget_of_uses_zero_as_no_cap_sentinel',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
        const list: CategoryBudget[] = parseCategoryBudgets('[{"category":"ticket","amount":1200}]');
        expect(budgetOf(list, ExpenseCategory.TICKET)).assertEqual(1200);
        expect(budgetOf(list, ExpenseCategory.FOOD)).assertEqual(0);
      });

    it('bar_prefers_the_category_cap', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      // 设了上限：1200/1000 超上限 → 封顶 100（条不画负、不画溢出）
      expect(barBase(1200, 1000, 16000)).assertEqual(1000);
      expect(barPct(1200, 1000, 16000)).assertEqual(100);
      expect(barPct(300, 1000, 16000)).assertEqual(30);
      // 没设上限：退回"占行程总预算"
      expect(barBase(300, 0, 16000)).assertEqual(16000);
      expect(barPct(300, 0, 16000)).assertEqual(2);
      // 兜底基线为 0（还没设总预算）也不能除零
      expect(barPct(0, 0, 0)).assertEqual(1);
    });
  });
}
