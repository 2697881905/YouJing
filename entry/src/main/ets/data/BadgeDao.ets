/**
 * 勋章读侧（无新表）：从 checkin 联 activity/trip 取「打卡证据」，交由 utils/BadgeBoard 合并。
 *
 * 为什么不在 v9 建 badge 表：一枚章目前完全可由打卡证据推出（uuid/时刻/坐标/来源都在
 * checkin 上），先落一份就成了两处真相；等真要做服务器同步与防伪时再按那时口径建表。
 * 联表用 `activity.id = trip_id || ':' || activity_id`——activity 行主键是前缀化过的，
 * 餐次打卡的派生 key 没有 activity 行，会在 JOIN 处自然落选。
 *
 * 分区：checkin 与 trip 都按当前 uid 收口（同一台设备切账号后互不可见）。
 */

import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { DatabaseHelper } from './DatabaseHelper';
import { AccountStore } from './AccountStore';
import { BadgeRecord } from '../utils/BadgeBoard';

const SQL_SELECT: string =
  'SELECT c.activity_id, c.checked_at, c.source, c.distance_m, c.trip_id, ' +
  'a.title, t.destination, t.start_date, t.end_date ' +
  'FROM checkin c ' +
  'JOIN activity a ON a.id = c.trip_id || \':\' || c.activity_id ' +
  'JOIN trip t ON t.id = c.trip_id ' +
  'WHERE c.user_id = ? AND t.user_id = ? ';

export class BadgeDao {
  /** 当前账号全部可作为勋章凭证的打卡（只含活动，不含餐次） */
  static listMine(context: common.Context): Promise<BadgeRecord[]> {
    return BadgeDao.query(context, `${SQL_SELECT}ORDER BY c.checked_at DESC`,
      [AccountStore.uid(), AccountStore.uid()]);
  }

  /** 单条行程的打卡凭证（行后回顾：只取本次旅程的证据，不拿全量在页面里筛） */
  static listForTrip(context: common.Context, tripId: string): Promise<BadgeRecord[]> {
    return BadgeDao.query(context, `${SQL_SELECT}AND c.trip_id = ? ORDER BY c.checked_at DESC`,
      [AccountStore.uid(), AccountStore.uid(), tripId]);
  }

  private static async query(context: common.Context, sql: string,
    args: relationalStore.ValueType[]): Promise<BadgeRecord[]> {
    const store: relationalStore.RdbStore = await DatabaseHelper.getStore(context);
    const rs: relationalStore.ResultSet = await store.querySql(sql, args);
    const out: BadgeRecord[] = [];
    try {
      while (rs.goToNextRow()) {
        out.push(BadgeDao.read(rs));
      }
    } finally {
      rs.close();
    }
    return out;
  }

  private static read(rs: relationalStore.ResultSet): BadgeRecord {
    const tripId: string = rs.getString(rs.getColumnIndex('trip_id'));
    const activityId: string = rs.getString(rs.getColumnIndex('activity_id'));
    const record: BadgeRecord = {
      id: `${tripId}:${activityId}`,
      tripId: tripId,
      spotName: rs.getString(rs.getColumnIndex('title')),
      city: rs.getString(rs.getColumnIndex('destination')),
      tripStartDate: rs.getString(rs.getColumnIndex('start_date')),
      tripEndDate: rs.getString(rs.getColumnIndex('end_date')),
      earnedAt: rs.getLong(rs.getColumnIndex('checked_at')),
      arrival: rs.getString(rs.getColumnIndex('source')) === 'arrival',
      distanceM: rs.getDouble(rs.getColumnIndex('distance_m'))
    };
    return record;
  }
}
