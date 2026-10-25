/**
 * 费用记账 DAO（阶段 10）：写走 DatabaseHelper 单写通道，读逐列收口，
 * 与 trip 一样按 AccountStore.uid() 分区（表列 user_id，v3 起）。
 */

import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { DatabaseHelper } from './DatabaseHelper';
import { AccountStore } from './AccountStore';
import { CategoryTotal, Expense, ExpenseCategory } from '../model/Expense';
import { Logger } from '../common/logger/Logger';

const TAG: string = 'Data.ExpenseDao';

export class ExpenseDao {
  /** 新增一笔，返回自增 id */
  static add(context: common.Context, expense: Expense): Promise<number> {
    return DatabaseHelper.write(context, async (store: relationalStore.RdbStore): Promise<number> => {
      const row: relationalStore.ValuesBucket = {
        trip_id: expense.tripId, day_index: expense.dayIndex, category: expense.category,
        name: expense.name, amount: expense.amount, created_at: expense.createdAt,
        activity_id: expense.activityId === undefined ? null : expense.activityId,
        user_id: AccountStore.uid()
      };
      return store.insert('expense', row);
    });
  }

  static delete(context: common.Context, id: number): Promise<void> {
    return DatabaseHelper.write(context, async (store: relationalStore.RdbStore): Promise<void> => {
      // 分区键必须带上：同机切换账号后，A 不该能删掉 B 的记账
      store.executeSync('DELETE FROM expense WHERE id = ? AND user_id = ?', [id, AccountStore.uid()]);
    });
  }

  /** 最近记账列表（新→旧），屏11 取前若干条 */
  static listByTrip(context: common.Context, tripId: string, limit: number): Promise<Expense[]> {
    return ExpenseDao.query(context,
      'SELECT id, trip_id, day_index, category, name, amount, created_at FROM expense ' +
        'WHERE trip_id = ? AND user_id = ? ORDER BY created_at DESC LIMIT ?',
      [tripId, AccountStore.uid(), limit],
      (rs: relationalStore.ResultSet): Expense => {
        const e: Expense = {
          id: rs.getLong(rs.getColumnIndex('id')),
          tripId: rs.getString(rs.getColumnIndex('trip_id')),
          dayIndex: rs.getLong(rs.getColumnIndex('day_index')),
          category: rs.getString(rs.getColumnIndex('category')) as ExpenseCategory,
          name: rs.getString(rs.getColumnIndex('name')),
          amount: rs.getLong(rs.getColumnIndex('amount')),
          createdAt: rs.getLong(rs.getColumnIndex('created_at'))
        };
        return e;
      });
  }

  /** 分类聚合（一次 SQL 出全部档，缺项不补零，由表现层按固定 6 档渲染） */
  static sumByCategory(context: common.Context, tripId: string): Promise<CategoryTotal[]> {
    return ExpenseDao.query(context,
      'SELECT category, SUM(amount) AS total FROM expense WHERE trip_id = ? AND user_id = ? ' +
        'GROUP BY category ORDER BY total DESC', [tripId, AccountStore.uid()],
      (rs: relationalStore.ResultSet): CategoryTotal => {
        const t: CategoryTotal = {
          category: rs.getString(rs.getColumnIndex('category')) as ExpenseCategory,
          amount: rs.getLong(rs.getColumnIndex('total'))
        };
        return t;
      });
  }

  /** 按节点聚合开销，屏15 行内金额取这里（一次 SQL，不在页面里循环查） */
  static sumGroupedByActivity(context: common.Context, tripId: string): Promise<Record<string, number>> {
    return ExpenseDao.query(context,
      'SELECT activity_id AS aid, SUM(amount) AS total FROM expense ' +
        'WHERE trip_id = ? AND user_id = ? AND activity_id IS NOT NULL GROUP BY activity_id',
      [tripId, AccountStore.uid()],
      (rs: relationalStore.ResultSet): string[] => {
        return [rs.getString(rs.getColumnIndex('aid')), `${rs.getLong(rs.getColumnIndex('total'))}`];
      }).then((rows: string[][]): Record<string, number> => {
      const out: Record<string, number> = {};
      for (const pair of rows) {
        out[pair[0]] = Number(pair[1]);
      }
      return out;
    });
  }

  static async totalOfTrip(context: common.Context, tripId: string): Promise<number> {
    const sums: CategoryTotal[] = await ExpenseDao.sumByCategory(context, tripId);
    let total: number = 0;
    for (const s of sums) {
      total += s.amount;
    }
    Logger.info(TAG, `trip=${tripId} 记账合计 ${total} 元（${sums.length} 类）`);
    return total;
  }

  private static async query<T>(context: common.Context, sql: string,
    args: relationalStore.ValueType[], map: (rs: relationalStore.ResultSet) => T): Promise<T[]> {
    const store: relationalStore.RdbStore = await DatabaseHelper.getStore(context);
    const rs: relationalStore.ResultSet = await store.querySql(sql, args);
    const out: T[] = [];
    try {
      while (rs.goToNextRow()) {
        out.push(map(rs));
      }
    } finally {
      rs.close();
    }
    return out;
  }
}
