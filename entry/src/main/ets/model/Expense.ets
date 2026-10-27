/**
 * 费用记录模型（开发文档 §6 阶段 10：费用记录）。
 * 金额单位「元」取整，与 Trip.budget / Activity 门票口径一致；分类固定 6 档，
 * 展示名与配色属表现层，不放本文件。
 */

export enum ExpenseCategory {
  TICKET = 'ticket',
  FOOD = 'food',
  TRANSPORT = 'transport',
  HOTEL = 'hotel',
  SHOP = 'shop',
  OTHER = 'other'
}

export interface Expense {
  /** 自增主键，新建时为 0 */
  id: number;
  tripId: string;
  /** 归属行程第几天，从 1 开始 */
  dayIndex: number;
  category: ExpenseCategory;
  name: string;
  amount: number;
  /** 记账时刻（ms） */
  createdAt: number;
  /** 挂在哪个行程节点上（屏15 行内金额用），可空 */
  activityId?: string;
}

/**
 * 分类预算（屏11「分类支出」那一卡的对照基线）。
 * 用户口径：总预算之外，每一类也要能各自设上限——所以它随行程存一份，
 * 而不是从总预算按百分比硬拆（拆出来的数字没人认）。
 */
export interface CategoryBudget {
  category: ExpenseCategory;
  amount: number;
}

/** 分类聚合行（屏11 分类支出条） */
export interface CategoryTotal {
  category: ExpenseCategory;
  amount: number;
}
