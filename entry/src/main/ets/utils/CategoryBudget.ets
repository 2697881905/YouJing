/**
 * 分类预算（屏11）的纯逻辑：解析存量 JSON、算某一类的上限、算画条基线。
 *
 * 单独成文件而不是留在 TripDao / ExpensePage 里：这三件事都是**可离线断言**的纯函数，
 * 而 ohosTest 的上下文拿不到 RDB（见 §5ci 那条"只卡 DB/偏好类"的边界），
 * 放在 DAO 里就等于测不到。
 */

import { CategoryBudget, ExpenseCategory } from '../model/Expense';

/** 六档封闭枚举的稳定码，顺序与 ExpensePage 的展示顺序一致 */
export const CATEGORY_CODES: string[] = ['ticket', 'food', 'transport', 'hotel', 'shop', 'other'];

/**
 * 分类预算 JSON → 数组。
 * 只认六档稳定码、只收正数；脏条目**整条丢掉而不是猜**（存量库没有这一列时给空数组）。
 */
export function parseCategoryBudgets(text: string | null): CategoryBudget[] {
  if (text === null || text.length === 0) {
    return [];
  }
  let raw: CategoryBudget[] = [];
  try {
    raw = JSON.parse(text) as CategoryBudget[];
  } catch (err) {
    return [];
  }
  const out: CategoryBudget[] = [];
  for (const item of raw) {
    if (item === null || item === undefined) {
      continue;
    }
    if (CATEGORY_CODES.indexOf(item.category) < 0 || !(item.amount > 0)) {
      continue;
    }
    const row: CategoryBudget = { category: item.category as ExpenseCategory, amount: Math.round(item.amount) };
    out.push(row);
  }
  return out;
}

/** 某一类的上限；没设过就是 0（0 是"不设上限"的哨兵，不是"预算为零"） */
export function budgetOf(list: CategoryBudget[], category: ExpenseCategory): number {
  for (const b of list) {
    if (b.category === category) {
      return b.amount;
    }
  }
  return 0;
}

/** 画条基线（vp 无关，纯数值）：设了上限用上限，否则用调用方给的兜底基线 */
export function barBase(amount: number, budget: number, fallbackBase: number): number {
  if (budget > 0) {
    return budget;
  }
  return Math.max(1, fallbackBase);
}

/** 百分比：封顶 100、至少 1（画 0 会看不出这条存在），超上限不画负值 */
export function barPct(amount: number, budget: number, fallbackBase: number): number {
  return Math.min(100, Math.max(1, Math.round((amount / barBase(amount, budget, fallbackBase)) * 100)));
}
