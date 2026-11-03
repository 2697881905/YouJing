/**
 * RDB 单例与建库迁移（开发文档 §5.2 生产级要点）。
 *
 * 纪律：
 * - 全应用复用同一 RdbStore（本文件唯一点），页面查询可独立、写事务收敛为单写通道；
 * - 增删改走 SQL/ValuesBucket，查询逐列收口成模型对象，禁直接断言；
 * - 版本号驱动迁移：onUpgrade 按 old→new 逐级执行，多条迁移放事务，成功才写新版本号；
 * - 过滤列建索引；单条记录 ≤2MB（行程 JSON 列远小于该值，tips/highlights 为文本）。
 *
 * 表结构（v10）：
 *   trip        行程聚合根（overview/tips 展平为列与 JSON 文本；user_id 为账号分区键）
 *   trip_day    单日（tripId+dayIndex 索引）
 *   activity    活动节点（含 transport 三列与 reason；tripId+dayIndex 索引）
 *   meal        餐饮（tripId+dayIndex 索引）
 *   spot/area   内置资产库（city 索引；预约/溯源列展平；v5 起 spot 带 confidence）
 *   expense     手工记账（v3；trip_id+day_index 索引，同 trip 一样按 user_id 分区；
 *               v4 起带 activity_id，可把一笔开销挂到具体节点）
 *   checkin     节点打卡（v4；(trip_id,activity_id) 唯一，本机用户态不入 AI 契约；
 *               v8 起到站凭证 uuid/坐标/精度/距离/来源，供行后勋章与将来同步用）
 *
 * 迁移纪律（开发文档 §5.2）：onUpgrade 的判断一律用 `oldVersion < N` 累积式，
 * 不用 `=== N` 精确匹配——精确匹配会让 v1 老库直接升到最新版时跳过中间步骤
 * （v1→v4 曾因此漏建 expense/checkin 两表、漏加 expense.activity_id 列）。
 * 任意 oldVersion → newVersion 的跨级升级都必须逐级补齐。
 */

import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Logger } from '../common/logger/Logger';
import { AccountConfig } from '../common/config/AccountConfig';
import { AppError } from '../common/error/AppError';
import { ErrorCode } from '../common/error/ErrorCode';

const STORE_NAME: string = 'youjing.db';
const DB_VERSION: number = 10;
const TAG: string = 'Data.DatabaseHelper';

const SQL_CREATE_TRIP: string = `CREATE TABLE IF NOT EXISTS trip (
  id TEXT PRIMARY KEY, destination TEXT NOT NULL, start_date TEXT NOT NULL, end_date TEXT NOT NULL,
  people INTEGER NOT NULL, budget INTEGER NOT NULL, style TEXT NOT NULL,
  total_cost INTEGER NOT NULL DEFAULT 0, summary TEXT NOT NULL DEFAULT '',
  highlights TEXT NOT NULL DEFAULT '[]', tips TEXT NOT NULL DEFAULT '[]',
  updated_at INTEGER NOT NULL)`;

const SQL_CREATE_TRIP_DAY: string = `CREATE TABLE IF NOT EXISTS trip_day (
  id INTEGER PRIMARY KEY AUTOINCREMENT, trip_id TEXT NOT NULL, day_index INTEGER NOT NULL,
  date TEXT NOT NULL, theme TEXT NOT NULL DEFAULT '', intensity TEXT NOT NULL DEFAULT 'medium',
  risk TEXT, daily_cost INTEGER NOT NULL DEFAULT 0, accommodation TEXT)`;

const SQL_CREATE_ACTIVITY: string = `CREATE TABLE IF NOT EXISTS activity (
  id TEXT PRIMARY KEY, trip_id TEXT NOT NULL, day_index INTEGER NOT NULL,
  time TEXT NOT NULL, end_time TEXT NOT NULL, title TEXT NOT NULL, location TEXT NOT NULL DEFAULT '',
  address TEXT NOT NULL DEFAULT '', longitude REAL NOT NULL DEFAULT 0, latitude REAL NOT NULL DEFAULT 0,
  status TEXT NOT NULL, category TEXT NOT NULL, note TEXT, reason TEXT,
  transport_mode TEXT, transport_duration INTEGER, transport_detail TEXT)`;

const SQL_CREATE_MEAL: string = `CREATE TABLE IF NOT EXISTS meal (
  id INTEGER PRIMARY KEY AUTOINCREMENT, trip_id TEXT NOT NULL, day_index INTEGER NOT NULL,
  type TEXT NOT NULL, name TEXT NOT NULL, location TEXT NOT NULL DEFAULT '',
  note TEXT, estimated_cost INTEGER NOT NULL DEFAULT 0)`;

const SQL_CREATE_SPOT: string = `CREATE TABLE IF NOT EXISTS spot (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, city TEXT NOT NULL, tags TEXT NOT NULL DEFAULT '[]',
  brief TEXT NOT NULL DEFAULT '', suggested_duration INTEGER NOT NULL DEFAULT 60,
  popularity INTEGER NOT NULL DEFAULT 50, nearby_ids TEXT NOT NULL DEFAULT '[]',
  longitude REAL NOT NULL DEFAULT 0, latitude REAL NOT NULL DEFAULT 0,
  district TEXT NOT NULL DEFAULT '', nearest_metro TEXT NOT NULL DEFAULT '', entrance_tip TEXT,
  requires_booking INTEGER NOT NULL DEFAULT 0, booking_method TEXT, advance_days INTEGER,
  release_time TEXT, closed_day TEXT, difficulty TEXT,
  source TEXT NOT NULL DEFAULT '', updated_at TEXT NOT NULL DEFAULT '')`;

const SQL_CREATE_AREA: string = `CREATE TABLE IF NOT EXISTS area (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, city TEXT NOT NULL, longitude REAL NOT NULL DEFAULT 0,
  latitude REAL NOT NULL DEFAULT 0, description TEXT NOT NULL DEFAULT '',
  anchor_stations TEXT NOT NULL DEFAULT '[]', metro_lines TEXT NOT NULL DEFAULT '[]',
  airport_minutes INTEGER NOT NULL DEFAULT 0, train_station_minutes INTEGER NOT NULL DEFAULT 0,
  commerce_tags TEXT NOT NULL DEFAULT '[]', dining_density TEXT NOT NULL DEFAULT '',
  suitable_crowds TEXT NOT NULL DEFAULT '[]', price_tier TEXT NOT NULL DEFAULT 'comfort',
  price_range TEXT, grp TEXT NOT NULL DEFAULT 'core', source TEXT NOT NULL DEFAULT '',
  updated_at TEXT NOT NULL DEFAULT '')`;

// expense 按 v3 形态建表；activity_id 一律交给 v4 迁移加列——新建库同样走一遍迁移，
// 避免「CREATE 已带该列 + 随后 ALTER 重复加列」的 duplicate column 错误
const SQL_CREATE_EXPENSE: string = `CREATE TABLE IF NOT EXISTS expense (
  id INTEGER PRIMARY KEY AUTOINCREMENT, trip_id TEXT NOT NULL, day_index INTEGER NOT NULL,
  category TEXT NOT NULL, name TEXT NOT NULL, amount INTEGER NOT NULL,
  created_at INTEGER NOT NULL, user_id TEXT NOT NULL DEFAULT '${AccountConfig.GUEST_UID}')`;

const SQL_CREATE_CHECKIN: string = `CREATE TABLE IF NOT EXISTS checkin (
  trip_id TEXT NOT NULL, activity_id TEXT NOT NULL, checked_at INTEGER NOT NULL,
  user_id TEXT NOT NULL DEFAULT '${AccountConfig.GUEST_UID}',
  PRIMARY KEY (trip_id, activity_id))`;

const SQL_INDEXES: string[] = [
  'CREATE INDEX IF NOT EXISTS idx_trip_day ON trip_day(trip_id)',
  'CREATE INDEX IF NOT EXISTS idx_activity_trip_day ON activity(trip_id, day_index)',
  'CREATE INDEX IF NOT EXISTS idx_meal_trip_day ON meal(trip_id, day_index)',
  'CREATE INDEX IF NOT EXISTS idx_spot_city ON spot(city)',
  'CREATE INDEX IF NOT EXISTS idx_area_city ON area(city)',
  'CREATE INDEX IF NOT EXISTS idx_trip_user ON trip(user_id)',
  'CREATE INDEX IF NOT EXISTS idx_expense_trip_day ON expense(trip_id, day_index)',
  'CREATE INDEX IF NOT EXISTS idx_expense_user ON expense(user_id)',
  'CREATE INDEX IF NOT EXISTS idx_checkin_user ON checkin(user_id)'
];

/** v4 → v5：景点溯源组补「可信度」列（§3.2 字段组完整；存量行默认空串） */
const SQL_V5_ADD_SPOT_CONFIDENCE: string =
  'ALTER TABLE spot ADD COLUMN confidence TEXT NOT NULL DEFAULT \'\'';

/** v3 → v4：记账可挂到具体节点（屏15 行内金额取真值） */
const SQL_V4_ADD_EXPENSE_ACTIVITY: string = 'ALTER TABLE expense ADD COLUMN activity_id TEXT';

/** v1 → v2：行程按账号分区。历史本机数据 DEFAULT 即游客分区，无需回填 */
/** v5 → v6：一餐有了时刻，屏15 才能把餐次和节点按时间并排（存量行默认空串=不显示时间） */
const SQL_V6_ADD_MEAL_TIME: string = `ALTER TABLE meal ADD COLUMN time TEXT NOT NULL DEFAULT ''`;

/** v6 → v7：分类预算（屏11）随行程存一份 JSON 数组；存量行默认空数组 */
const SQL_V7_ADD_TRIP_CATEGORY_BUDGET: string =
  `ALTER TABLE trip ADD COLUMN category_budget TEXT NOT NULL DEFAULT '[]'`;

/**
 * v7 → v8：打卡留「到站凭证」。旧记录（v4–v7 写的）一律算手动打卡：
 * source 默认 'manual'、坐标为 0——回填不了的东西不假造，行后勋章按 source 区分。
 */
const SQL_V8_CHECKIN_EVIDENCE: string[] = [
  'ALTER TABLE checkin ADD COLUMN uuid TEXT NOT NULL DEFAULT \'\'',
  'ALTER TABLE checkin ADD COLUMN latitude REAL NOT NULL DEFAULT 0',
  'ALTER TABLE checkin ADD COLUMN longitude REAL NOT NULL DEFAULT 0',
  'ALTER TABLE checkin ADD COLUMN accuracy_m REAL NOT NULL DEFAULT 0',
  'ALTER TABLE checkin ADD COLUMN distance_m REAL NOT NULL DEFAULT 0',
  'ALTER TABLE checkin ADD COLUMN source TEXT NOT NULL DEFAULT \'manual\''
];

const SQL_V2_ADD_TRIP_USER_ID: string =
  `ALTER TABLE trip ADD COLUMN user_id TEXT NOT NULL DEFAULT '${AccountConfig.GUEST_UID}'`;

/**
 * v8 → v9：删行程没有级联清子表，历史上留下的孤儿打卡/费用一次性清掉。
 * 只删「父行程已不存在」的行；仍挂在任何行程下的数据不动。
 */
const SQL_V9_CLEAN_ORPHANS: string[] = [
  'DELETE FROM checkin WHERE trip_id NOT IN (SELECT id FROM trip)',
  'DELETE FROM expense WHERE trip_id NOT IN (SELECT id FROM trip)',
  'DELETE FROM meal WHERE trip_id NOT IN (SELECT id FROM trip)',
  'DELETE FROM activity WHERE trip_id NOT IN (SELECT id FROM trip)',
  'DELETE FROM trip_day WHERE trip_id NOT IN (SELECT id FROM trip)'
];

/** v9 → v10：行程绑定通行证（商业化方案 §3）。空串 = 未购买通行证 */
const SQL_V10_ADD_TRIP_PASS_ID: string =
  `ALTER TABLE trip ADD COLUMN pass_id TEXT NOT NULL DEFAULT ''`;

export class DatabaseHelper {
  private static storePromise: Promise<relationalStore.RdbStore> | null = null;
  /** 单写通道：所有写事务排队串行，规避 RDB busy（§8 风险表） */
  private static writeChain: Promise<void> = Promise.resolve();

  static getStore(context: common.Context): Promise<relationalStore.RdbStore> {
    if (DatabaseHelper.storePromise === null) {
      DatabaseHelper.storePromise = DatabaseHelper.open(context);
    }
    return DatabaseHelper.storePromise;
  }

  /** 写事务统一入口：fn 内自行 execute 系列调用，异常自动回滚并包装 AppError */
  static write<T>(context: common.Context,
    fn: (store: relationalStore.RdbStore) => Promise<T>): Promise<T> {
    const task: Promise<T> = DatabaseHelper.writeChain.then(async (): Promise<T> => {
      const store: relationalStore.RdbStore = await DatabaseHelper.getStore(context);
      await store.beginTransaction();
      try {
        const result: T = await fn(store);
        await store.commit();
        return result;
      } catch (err) {
        await store.rollBack();
        throw new AppError(ErrorCode.RDB_TRANSACTION_FAILED,
          `写事务失败: ${(err as Error).message}`, err as Error);
      }
    });
    // 链只吞错误不断流，后续写入不被前一次失败卡死
    DatabaseHelper.writeChain = task.then((): void => {
    }, (): void => {
    });
    return task;
  }

  private static async open(context: common.Context): Promise<relationalStore.RdbStore> {
    const config: relationalStore.StoreConfig = {
      name: STORE_NAME,
      securityLevel: relationalStore.SecurityLevel.S4
    };
    try {
      const store: relationalStore.RdbStore =
        await relationalStore.getRdbStore(context, config);
      await DatabaseHelper.migrate(store);
      Logger.info(TAG, `RdbStore 就绪 v${store.version}`);
      return store;
    } catch (err) {
      throw new AppError(ErrorCode.RDB_INIT_FAILED,
        `建库失败: ${(err as Error).message}`, err as Error);
    }
  }

  private static async migrate(store: relationalStore.RdbStore): Promise<void> {
    const oldVersion: number = store.version;
    if (oldVersion === DB_VERSION) {
      return;
    }
    await store.beginTransaction();
    try {
      if (oldVersion === 0) {
        await store.executeSql(SQL_CREATE_TRIP);
        await store.executeSql(SQL_CREATE_TRIP_DAY);
        await store.executeSql(SQL_CREATE_ACTIVITY);
        await store.executeSql(SQL_CREATE_MEAL);
        await store.executeSql(SQL_CREATE_SPOT);
        await store.executeSql(SQL_CREATE_AREA);
        await store.executeSql(SQL_CREATE_EXPENSE);
        await store.executeSql(SQL_CREATE_CHECKIN);
      }
      if (oldVersion < 2) {
        await store.executeSql(SQL_V2_ADD_TRIP_USER_ID);
      }
      if (oldVersion < 3) {
        await store.executeSql(SQL_CREATE_EXPENSE);
      }
      if (oldVersion < 4) {
        await store.executeSql(SQL_CREATE_CHECKIN);
        await store.executeSql(SQL_V4_ADD_EXPENSE_ACTIVITY);
      }
      if (oldVersion < 5) {
        await store.executeSql(SQL_V5_ADD_SPOT_CONFIDENCE);
      }
      if (oldVersion < 6) {
        await store.executeSql(SQL_V6_ADD_MEAL_TIME);
      }
      if (oldVersion < 7) {
        await store.executeSql(SQL_V7_ADD_TRIP_CATEGORY_BUDGET);
      }
      if (oldVersion < 8) {
        for (const sql of SQL_V8_CHECKIN_EVIDENCE) {
          await store.executeSql(sql);
        }
      }
      if (oldVersion < 9) {
        for (const sql of SQL_V9_CLEAN_ORPHANS) {
          await store.executeSql(sql);
        }
      }
      if (oldVersion < 10) {
        await store.executeSql(SQL_V10_ADD_TRIP_PASS_ID);
      }
      for (const idx of SQL_INDEXES) {
        await store.executeSql(idx);
      }
      store.version = DB_VERSION;
      await store.commit();
      Logger.info(TAG, `迁移完成 ${oldVersion} → ${DB_VERSION}`);
    } catch (err) {
      await store.rollBack();
      throw new AppError(ErrorCode.RDB_MIGRATION_FAILED,
        `迁移失败: ${(err as Error).message}`, err as Error);
    }
  }
}
