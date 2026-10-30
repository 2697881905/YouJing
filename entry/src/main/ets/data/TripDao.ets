/**
 * 行程 DAO：聚合根整存整取（写走单写通道事务，读逐列收口成模型）。
 * activity 行主键 = `${tripId}:${activityId}` 前缀化，规避跨行程 id 撞车。
 * 分区：trip.user_id 取 AccountStore.uid()，列表与详情读均按当前登录态收口（阶段 8）。
 */

import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { DatabaseHelper } from './DatabaseHelper';
import { AccountStore } from './AccountStore';
import { TodayPlan, TodayPlanData } from './TodayPlan';
import { AccountConfig } from '../common/config/AccountConfig';
import { Activity, ActivityCategory, ActivityStatus, IntensityLevel, Meal, MealType, TransportInfo, Trip, TripDay } from '../model/Trip';
import { Logger } from '../common/logger/Logger';
import { CategoryBudget, ExpenseCategory } from '../model/Expense';
import { parseCategoryBudgets } from '../utils/CategoryBudget';
import { AppError } from '../common/error/AppError';
import { ErrorCode } from '../common/error/ErrorCode';

const TAG: string = 'Data.TripDao';

/** 列表页摘要行（屏12 卡片数据源） */
export interface TripSummary {
  id: string;
  destination: string;
  startDate: string;
  endDate: string;
  people: number;
  totalCost: number;
  spotCount: number;
  /** 需预约且尚未确认的节点数（not_booked/pending/full） */
  bookingCount: number;
  /** 有通勤记录的节点数（transport_mode 非空） */
  legCount: number;
  /** 已打卡的活动数（行后回顾的入口判据：有证据才值得回顾） */
  checkinCount: number;
  updatedAt: number;
}

function parseStringArray(text: string | null): string[] {
  if (text === null || text.length === 0) {
    return [];
  }
  try {
    const arr: string[] = JSON.parse(text) as string[];
    return arr;
  } catch (err) {
    return [];
  }
}

export class TripDao {
  static saveTrip(context: common.Context, trip: Trip): Promise<void> {
    return DatabaseHelper.write(context, async (store: relationalStore.RdbStore): Promise<void> => {
      await TripDao.deleteRows(store, trip.id);
      const tripRow: relationalStore.ValuesBucket = {
        id: trip.id, destination: trip.destination, start_date: trip.startDate,
        end_date: trip.endDate, people: trip.people, budget: trip.budget, style: trip.style,
        total_cost: trip.overview.totalCost, summary: trip.overview.summary,
        highlights: JSON.stringify(trip.overview.highlights), tips: JSON.stringify(trip.tips),
        updated_at: Date.now(), user_id: AccountStore.uid(),
        category_budget: JSON.stringify(trip.categoryBudgets === undefined ? [] : trip.categoryBudgets)
      };
      store.insertSync('trip', tripRow);
      for (const day of trip.days) {
        const dayRow: relationalStore.ValuesBucket = {
          trip_id: trip.id, day_index: day.dayIndex, date: day.date, theme: day.theme,
          intensity: day.intensity, risk: day.risk === undefined ? null : day.risk,
          daily_cost: day.dailyCost, accommodation: day.accommodation === undefined ? null : day.accommodation
        };
        store.insertSync('trip_day', dayRow);
        for (const act of day.activities) {
          TripDao.insertActivity(store, trip.id, day.dayIndex, act);
        }
        for (const meal of day.meals) {
          const mealRow: relationalStore.ValuesBucket = {
            trip_id: trip.id, day_index: day.dayIndex, type: meal.type, name: meal.name,
            location: meal.location, note: meal.note === undefined ? null : meal.note,
            estimated_cost: meal.estimatedCost, time: meal.time === undefined ? '' : meal.time
          };
          store.insertSync('meal', mealRow);
        }
      }
      Logger.info(TAG, `saveTrip ${trip.id} days=${trip.days.length}`);
    });
  }

  static listSummaries(context: common.Context): Promise<TripSummary[]> {
    return TripDao.query(context,
      'SELECT t.id, t.destination, t.start_date, t.end_date, t.people, t.total_cost, t.updated_at, ' +
        '(SELECT COUNT(*) FROM activity a WHERE a.trip_id = t.id) AS spot_count, ' +
        "(SELECT COUNT(*) FROM activity a WHERE a.trip_id = t.id AND a.status IN ('not_booked','pending','full')) AS booking_count, " +
        '(SELECT COUNT(*) FROM activity a WHERE a.trip_id = t.id AND a.transport_mode IS NOT NULL) AS leg_count, ' +
        '(SELECT COUNT(*) FROM checkin c JOIN activity a ON a.id = c.trip_id || \':\' || c.activity_id ' +
        'WHERE c.trip_id = t.id AND c.user_id = t.user_id) AS checkin_count ' +
        'FROM trip t WHERE t.user_id = ? ORDER BY t.updated_at DESC', [AccountStore.uid()],
      (rs: relationalStore.ResultSet): TripSummary => {
        const s: TripSummary = {
          id: rs.getString(rs.getColumnIndex('id')),
          destination: rs.getString(rs.getColumnIndex('destination')),
          startDate: rs.getString(rs.getColumnIndex('start_date')),
          endDate: rs.getString(rs.getColumnIndex('end_date')),
          people: rs.getLong(rs.getColumnIndex('people')),
          totalCost: rs.getLong(rs.getColumnIndex('total_cost')),
          spotCount: rs.getLong(rs.getColumnIndex('spot_count')),
          bookingCount: rs.getLong(rs.getColumnIndex('booking_count')),
          legCount: rs.getLong(rs.getColumnIndex('leg_count')),
          checkinCount: rs.getLong(rs.getColumnIndex('checkin_count')),
          updatedAt: rs.getLong(rs.getColumnIndex('updated_at'))
        };
        return s;
      });
  }

  static async loadTrip(context: common.Context, tripId: string): Promise<Trip | null> {
    const heads: Trip[] = await TripDao.query(context,
      'SELECT * FROM trip WHERE id = ? AND user_id = ?', [tripId, AccountStore.uid()],
      (rs: relationalStore.ResultSet): Trip => {
        const t: Trip = {
          id: rs.getString(rs.getColumnIndex('id')),
          destination: rs.getString(rs.getColumnIndex('destination')),
          startDate: rs.getString(rs.getColumnIndex('start_date')),
          endDate: rs.getString(rs.getColumnIndex('end_date')),
          people: rs.getLong(rs.getColumnIndex('people')),
          budget: rs.getLong(rs.getColumnIndex('budget')),
          style: rs.getString(rs.getColumnIndex('style')),
          overview: {
            totalCost: rs.getLong(rs.getColumnIndex('total_cost')),
            highlights: parseStringArray(rs.getString(rs.getColumnIndex('highlights'))),
            summary: rs.getString(rs.getColumnIndex('summary'))
          },
          days: [],
          tips: parseStringArray(rs.getString(rs.getColumnIndex('tips'))),
          categoryBudgets: parseCategoryBudgets(rs.getString(rs.getColumnIndex('category_budget')))
        };
        return t;
      });
    if (heads.length === 0) {
      return null;
    }
    const trip: Trip = heads[0];
    const days: TripDay[] = await TripDao.query(context,
      'SELECT * FROM trip_day WHERE trip_id = ? ORDER BY day_index', [tripId],
      (rs: relationalStore.ResultSet): TripDay => {
        const risk: string = rs.getString(rs.getColumnIndex('risk'));
        const acc: string = rs.getString(rs.getColumnIndex('accommodation'));
        const d: TripDay = {
          dayIndex: rs.getLong(rs.getColumnIndex('day_index')),
          date: rs.getString(rs.getColumnIndex('date')),
          theme: rs.getString(rs.getColumnIndex('theme')),
          intensity: rs.getString(rs.getColumnIndex('intensity')) as IntensityLevel,
          risk: risk.length > 0 ? risk : undefined,
          dailyCost: rs.getLong(rs.getColumnIndex('daily_cost')),
          activities: [],
          meals: [],
          accommodation: acc.length > 0 ? acc : undefined
        };
        return d;
      });
    const acts: ActivityRow[] = await TripDao.query(context,
      'SELECT * FROM activity WHERE trip_id = ? ORDER BY day_index, time', [tripId],
      (rs: relationalStore.ResultSet): ActivityRow => {
        const row: ActivityRow = {
          dayIndex: rs.getLong(rs.getColumnIndex('day_index')),
          activity: readActivity(rs)
        };
        return row;
      });
    const meals: MealRowWrap[] = await TripDao.query(context,
      'SELECT * FROM meal WHERE trip_id = ? ORDER BY day_index, type', [tripId],
      (rs: relationalStore.ResultSet): MealRowWrap => {const note: string = rs.getString(rs.getColumnIndex('note')); const tm: string = rs.getString(rs.getColumnIndex('time'));
        const wrap: MealRowWrap = {
          dayIndex: rs.getLong(rs.getColumnIndex('day_index')),
          meal: {
            type: rs.getString(rs.getColumnIndex('type')) as MealType,
            name: rs.getString(rs.getColumnIndex('name')),
            location: rs.getString(rs.getColumnIndex('location')),
            time: tm.length > 0 ? tm : undefined,
            note: note.length > 0 ? note : undefined,
            estimatedCost: rs.getLong(rs.getColumnIndex('estimated_cost'))
          }
        };
        return wrap;
      });
    for (const day of days) {
      for (const ar of acts) {
        if (ar.dayIndex === day.dayIndex) {
          day.activities.push(ar.activity);
        }
      }
      for (const mr of meals) {
        if (mr.dayIndex === day.dayIndex) {
          day.meals.push(mr.meal);
        }
      }
    }
    trip.days = days;
    return trip;
  }

  /** 桌面卡片数据源：当前登录分区里覆盖今天的行程（按更新时间取最近一条） */
  static async todayPlan(context: common.Context): Promise<TodayPlanData | null> {
    const today: string = TodayPlan.today();
    const now: string = TodayPlan.nowHHmm();
    // 先用日期范围预筛：不再对每条行程都整份 loadTrip（每次 4 条 SQL），
    // 行程数增长后卡片刷新成本从「行程数 × 全量加载」降为「命中数 × 全量加载」
    const ids: string[] = await TripDao.query(context,
      'SELECT id FROM trip WHERE user_id = ? AND start_date <= ? AND end_date >= ? ' +
        'ORDER BY updated_at DESC', [AccountStore.uid(), today, today],
      (rs: relationalStore.ResultSet): string => rs.getString(rs.getColumnIndex('id')));
    for (const id of ids) {
      const trip: Trip | null = await TripDao.loadTrip(context, id);
      if (trip === null) {
        continue;
      }
      const plan: TodayPlanData | null = TodayPlan.of(trip, today, now);
      if (plan !== null) {
        Logger.info(TAG, `今日卡片 ${plan.tripId} ${plan.dayTitle} ${plan.meta}`);
        return plan;
      }
    }
    Logger.info(TAG, `今日无在途行程 today=${today} 候选数=${ids.length}`);
    return null;
  }

  /**
   * 静默登录取到 UnionID 后，把游客分区数据归户到该账号；返回归户后该账号名下行程数。
   * 三张带 user_id 的表必须同一事务迁移：只迁 trip 会让登录前记的费用与打卡从屏15/屏16 消失。
   */
  static async adoptGuestData(context: common.Context, toUid: string): Promise<number> {
    if (toUid === AccountConfig.GUEST_UID) {
      return 0;
    }
    await DatabaseHelper.write(context, async (store: relationalStore.RdbStore): Promise<void> => {
      store.executeSync('UPDATE trip SET user_id = ? WHERE user_id = ?', [toUid, AccountConfig.GUEST_UID]);
      store.executeSync('UPDATE expense SET user_id = ? WHERE user_id = ?', [toUid, AccountConfig.GUEST_UID]);
      store.executeSync('UPDATE checkin SET user_id = ? WHERE user_id = ?', [toUid, AccountConfig.GUEST_UID]);
    });
    const trips: number[] = await TripDao.countByUid(context, 'trip', toUid);
    const expenses: number[] = await TripDao.countByUid(context, 'expense', toUid);
    const checkins: number[] = await TripDao.countByUid(context, 'checkin', toUid);
    const count: number = trips.length > 0 ? trips[0] : 0;
    Logger.info(TAG,
      `游客数据归户 uid=${AccountStore.masked()} trip=${count} ` +
      `expense=${expenses.length > 0 ? expenses[0] : 0} checkin=${checkins.length > 0 ? checkins[0] : 0}`);
    return count;
  }

  private static countByUid(context: common.Context, table: string, uid: string): Promise<number[]> {
    return TripDao.query(context, `SELECT COUNT(*) AS c FROM ${table} WHERE user_id = ?`, [uid],
      (rs: relationalStore.ResultSet): number => rs.getLong(rs.getColumnIndex('c')));
  }

  /** 只动 trip 一行：分类预算是行程级设置，不重建整棵行程树 */
  static saveCategoryBudgets(context: common.Context, tripId: string,
    list: CategoryBudget[]): Promise<void> {
    const json: string = JSON.stringify(list);
    return DatabaseHelper.write(context, async (store: relationalStore.RdbStore): Promise<void> => {
      store.executeSql('UPDATE trip SET category_budget = ?, updated_at = ? WHERE id = ? AND user_id = ?',
        [json, Date.now(), tripId, AccountStore.uid()]);
      Logger.info(TAG, `saveCategoryBudgets ${tripId} n=${list.length}`);
    });
  }

  static deleteTrip(context: common.Context, tripId: string): Promise<void> {
    return DatabaseHelper.write(context, async (store: relationalStore.RdbStore): Promise<void> => {
      await TripDao.deleteRows(store, tripId);
    });
  }

  private static insertActivity(store: relationalStore.RdbStore, tripId: string,
    dayIndex: number, act: Activity): void {
    const row: relationalStore.ValuesBucket = {
      id: `${tripId}:${act.id}`, trip_id: tripId, day_index: dayIndex,
      time: act.time, end_time: act.endTime, title: act.title, location: act.location,
      address: act.address, longitude: act.longitude, latitude: act.latitude,
      status: act.status, category: act.category,
      note: act.note === undefined ? null : act.note,
      reason: act.reason === undefined ? null : act.reason,
      transport_mode: act.transport === undefined ? null : act.transport.mode,
      transport_duration: act.transport === undefined ? null : act.transport.duration,
      transport_detail: act.transport === undefined ? null : act.transport.detail
    };
    store.insertSync('activity', row);
  }

  private static async deleteRows(store: relationalStore.RdbStore, tripId: string): Promise<void> {
    store.executeSync('DELETE FROM trip WHERE id = ?', [tripId]);
    store.executeSync('DELETE FROM trip_day WHERE trip_id = ?', [tripId]);
    store.executeSync('DELETE FROM activity WHERE trip_id = ?', [tripId]);
    store.executeSync('DELETE FROM meal WHERE trip_id = ?', [tripId]);
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

interface ActivityRow {
  dayIndex: number;
  activity: Activity;
}

interface MealRowWrap {
  dayIndex: number;
  meal: Meal;
}

function readActivity(rs: relationalStore.ResultSet): Activity {
  const note: string = rs.getString(rs.getColumnIndex('note'));
  const reason: string = rs.getString(rs.getColumnIndex('reason'));
  const mode: string = rs.getString(rs.getColumnIndex('transport_mode'));
  let transport: TransportInfo | undefined = undefined;
  if (mode.length > 0) {
    transport = {
      mode: mode,
      duration: rs.getLong(rs.getColumnIndex('transport_duration')),
      detail: rs.getString(rs.getColumnIndex('transport_detail'))
    };
  }
  const rawId: string = rs.getString(rs.getColumnIndex('id'));
  const tripPrefix: string = `${rs.getString(rs.getColumnIndex('trip_id'))}:`;
  const act: Activity = {
    id: rawId.startsWith(tripPrefix) ? rawId.substring(tripPrefix.length) : rawId,
    time: rs.getString(rs.getColumnIndex('time')),
    endTime: rs.getString(rs.getColumnIndex('end_time')),
    title: rs.getString(rs.getColumnIndex('title')),
    location: rs.getString(rs.getColumnIndex('location')),
    address: rs.getString(rs.getColumnIndex('address')),
    longitude: rs.getDouble(rs.getColumnIndex('longitude')),
    latitude: rs.getDouble(rs.getColumnIndex('latitude')),
    status: rs.getString(rs.getColumnIndex('status')) as ActivityStatus,
    category: rs.getString(rs.getColumnIndex('category')) as ActivityCategory,
    note: note.length > 0 ? note : undefined,
    reason: reason.length > 0 ? reason : undefined,
    transport: transport
  };
  return act;
}
