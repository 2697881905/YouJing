/**
 * 屏2 预算档位 · 全工程唯一定义点（元/人）。
 * 小艺预填新建行程时回到 DEFAULT，避免无声沿用上一段草稿的预算。
 */

export interface BudgetConfigType {
  MIN: number;
  MAX: number;
  STEP: number;
  DEFAULT: number;
}

export const BudgetConfig: BudgetConfigType = {
  MIN: 3000,
  MAX: 12000,
  STEP: 500,
  DEFAULT: 8000
};
