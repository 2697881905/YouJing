/**
 * 节点打卡 DAO（v4 checkin 表）。写走单写通道，读逐列收口，按 uid 分区。
 * 同一 (trip_id, activity_id) 唯一：重复打卡走 ON_CONFLICT_REPLACE 更新时刻。
 */

import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { DatabaseHelper } from './DatabaseHelper';
import { AccountStore } from './AccountStore';
import { Logger } from '../common/logger/Logger';

const TAG: string = 'Data.CheckinDao';

export class CheckinDao {
  /** 打卡/取消打卡；checked=true 记当前时刻，false 删记录 */
  static set(context: common.Context, tripId: string, activityId: string,
    checked: boolean): Promise<void> {
    return DatabaseHelper.write(context, async (store: relationalStore.RdbStore): Promise<void> => {
      if (checked) {
        const row: relationalStore.ValuesBucket = {
          trip_id: tripId, activity_id: activityId, checked_at: Date.now(), user_id: AccountStore.uid()
        };
        store.insertSync('checkin', row, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
      } else {
        // 分区键必须带上：同机切换账号后，A 不该能删掉 B 的打卡
        store.executeSync('DELETE FROM checkin WHERE trip_id = ? AND activity_id = ? AND user_id = ?',
          [tripId, activityId, AccountStore.uid()]);
      }
      Logger.info(TAG, `${checked ? '打卡' : '取消打卡'} ${tripId}:${activityId}`);
    });
  }

  /** 该行程全部打卡记录：activityId → 打卡时刻 */
  static async listForTrip(context: common.Context, tripId: string): Promise<Record<string, number>> {
    const store: relationalStore.RdbStore = await DatabaseHelper.getStore(context);
    const rs: relationalStore.ResultSet = await store.querySql(
      'SELECT activity_id, checked_at FROM checkin WHERE trip_id = ? AND user_id = ?',
      [tripId, AccountStore.uid()]);
    const out: Record<string, number> = {};
    try {
      while (rs.goToNextRow()) {
        out[rs.getString(rs.getColumnIndex('activity_id'))] = rs.getLong(rs.getColumnIndex('checked_at'));
      }
    } finally {
      rs.close();
    }
    return out;
  }
}
