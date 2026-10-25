/**
 * 规划数据仓储：USE_MOCK_DATA 数据路由（P3 预留的开关在此生效）。
 * 页面经本层取数，不直连 DAO（分层纪律）。
 */

import { common } from '@kit.AbilityKit';
import { MockConfig } from '../common/config/MockConfig';
import { SpotDao } from './SpotDao';
import { AreaDao } from './AreaDao';
import { Spot } from '../model/Spot';
import { Area } from '../model/Area';
import { MockSpots, MockAreas } from '../mock/MockData';
import { Logger } from '../common/logger/Logger';

export class PlanRepository {
  static async loadSpots(context: common.Context, city: string): Promise<Spot[]> {
    // mock 只服务「京都」这一座演示城；四城走真种子库。
    // 不支持的城市返回空列表，由调用方走空态——不拿京都数据冒充别的城市
    if (MockConfig.USE_MOCK_DATA && city === '京都') {
      Logger.info('Data.PlanRepository', `loadSpots ${city} 走 mock 演示数据`);
      return MockSpots.CULTURE.concat(MockSpots.FOOD).concat(MockSpots.NATURE);
    }
    const spots: Spot[] = await SpotDao.loadByCity(context, city);
    if (spots.length === 0) {
      Logger.info('Data.PlanRepository', `loadSpots ${city} 景点库为空`);
    }
    return spots;
  }

  static async loadAreas(context: common.Context, city: string): Promise<Area[]> {
    if (MockConfig.USE_MOCK_DATA && city === '京都') {
      Logger.info('Data.PlanRepository', `loadAreas ${city} 走 mock 演示数据`);
      return MockAreas.PICKS.map((p): Area => p.area);
    }
    const areas: Area[] = await AreaDao.loadByCity(context, city);
    if (areas.length === 0) {
      Logger.info('Data.PlanRepository', `loadAreas ${city} 区域库为空`);
    }
    return areas;
  }
}
