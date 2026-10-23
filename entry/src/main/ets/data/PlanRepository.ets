/**
 * 规划数据仓储：USE_MOCK_DATA 数据路由（P3 预留的开关在此生效）。
 * 页面经本层取数，不直连 DAO（分层纪律）。
 */

import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { MockConfig } from '../common/config/MockConfig';
import { DatabaseHelper } from './DatabaseHelper';
import { SpotDao } from './SpotDao';
import { AreaDao } from './AreaDao';
import { Spot } from '../model/Spot';
import { Area } from '../model/Area';
import { MockSpots, MockAreas } from '../mock/MockData';
import { Logger } from '../common/logger/Logger';

export class PlanRepository {
  static async loadSpots(context: common.Context, city: string): Promise<Spot[]> {
    if (!MockConfig.USE_MOCK_DATA || city !== '京都') {
      const spots: Spot[] = await SpotDao.loadByCity(context, city);
      if (spots.length > 0) {
        return spots;
      }
    }
    // mock 兜底：京都演示数据（底稿帧同源）
    Logger.info('Data.PlanRepository', `loadSpots ${city} 走 mock 兜底`);
    return MockSpots.CULTURE.concat(MockSpots.FOOD).concat(MockSpots.NATURE);
  }

  static async loadAreas(context: common.Context, city: string): Promise<Area[]> {
    if (!MockConfig.USE_MOCK_DATA || city !== '京都') {
      const areas: Area[] = await AreaDao.loadByCity(context, city);
      if (areas.length > 0) {
        return areas.map((a: Area): Area => a);
      }
    }
    Logger.info('Data.PlanRepository', `loadAreas ${city} 走 mock 兜底`);
    return MockAreas.PICKS.map((p): Area => p.area);
  }

  static async hasTrips(context: common.Context): Promise<boolean> {
    const store: relationalStore.RdbStore = await DatabaseHelper.getStore(context);
    const rs: relationalStore.ResultSet = await store.querySql('SELECT COUNT(*) AS c FROM trip');
    let c: number = 0;
    try {
      if (rs.goToFirstRow()) {
        c = rs.getLong(rs.getColumnIndex('c'));
      }
    } finally {
      rs.close();
    }
    return c > 0;
  }
}
