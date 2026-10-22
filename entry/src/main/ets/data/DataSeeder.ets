/**
 * 内置资产种子导入（开发文档 §6 阶段 5）。
 *
 * 数据来源：seed-v1 公开常识整理（用户拍板），经纬度取所在区中心近似值——
 * Map Kit 开通后用地理编码回填精确坐标（INIT_REPORT 待办）；预约信息 UI 标「以官方为准」。
 * 幂等：spot 表有行即跳过；购买数据到位后整表替换（INSERT OR REPLACE 同 id）。
 */

import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { DatabaseHelper } from './DatabaseHelper';
import { SpotDao } from './SpotDao';
import { AreaDao } from './AreaDao';
import { Spot, SpotTag } from '../model/Spot';
import { Area, AreaGroup, AreaPriceTier } from '../model/Area';
import { Logger } from '../common/logger/Logger';
import { AppError } from '../common/error/AppError';
import { ErrorCode } from '../common/error/ErrorCode';

type Obj = Record<string, Object>;
type Strs = string[];

const TAG: string = 'Data.Seeder';
const SEED_DATE: string = '2026-10-23';

interface CitySeed {
  city: string;
  spotsFile: string;
  areasFile: string;
}

const CITIES: CitySeed[] = [
  { city: '北京', spotsFile: 'seed/spots_beijing.jsonl', areasFile: 'seed/areas_beijing.jsonl' },
  { city: '上海', spotsFile: 'seed/spots_shanghai.jsonl', areasFile: 'seed/areas_shanghai.jsonl' },
  { city: '广州', spotsFile: 'seed/spots_guangzhou.jsonl', areasFile: 'seed/areas_guangzhou.jsonl' },
  { city: '深圳', spotsFile: 'seed/spots_shenzhen.jsonl', areasFile: 'seed/areas_shenzhen.jsonl' }
];

/** 区中心近似坐标（度）。正式经纬度待 Map Kit 地理编码回填。 */
export class DistrictCoords {
  private static readonly MAP: Map<string, number[]> = new Map<string, number[]>([
    ['北京:东城区', [39.928, 116.414]], ['北京:西城区', [39.912, 116.366]],
    ['北京:朝阳区', [39.921, 116.443]], ['北京:海淀区', [39.959, 116.298]],
    ['北京:丰台区', [39.858, 116.287]], ['北京:石景山区', [39.906, 116.223]],
    ['北京:通州区', [39.902, 116.657]], ['北京:昌平区', [40.221, 116.231]],
    ['北京:怀柔区', [40.316, 116.637]], ['北京:延庆区', [40.457, 115.975]],
    ['北京:门头沟区', [39.941, 116.102]], ['北京:房山区', [39.742, 116.143]],
    ['北京:顺义区', [40.129, 116.654]], ['北京:大兴区', [39.726, 116.341]],
    ['上海:黄浦区', [31.232, 121.484]], ['上海:徐汇区', [31.188, 121.437]],
    ['上海:长宁区', [31.220, 121.425]], ['上海:静安区', [31.229, 121.458]],
    ['上海:普陀区', [31.250, 121.396]], ['上海:虹口区', [31.265, 121.487]],
    ['上海:杨浦区', [31.260, 121.526]], ['上海:浦东新区', [31.221, 121.544]],
    ['上海:闵行区', [31.112, 121.381]], ['上海:宝山区', [31.405, 121.489]],
    ['上海:嘉定区', [31.375, 121.266]], ['上海:松江区', [31.032, 121.227]],
    ['上海:青浦区', [31.151, 121.112]], ['上海:奉贤区', [30.918, 121.474]],
    ['上海:崇明区', [31.624, 121.397]],
    ['广州:越秀区', [23.129, 113.267]], ['广州:荔湾区', [23.126, 113.243]],
    ['广州:海珠区', [23.102, 113.317]], ['广州:天河区', [23.124, 113.363]],
    ['广州:白云区', [23.269, 113.267]], ['广州:黄埔区', [23.181, 113.487]],
    ['广州:番禺区', [22.938, 113.384]], ['广州:花都区', [23.404, 113.220]],
    ['广州:南沙区', [22.802, 113.525]], ['广州:增城区', [23.292, 113.811]],
    ['广州:从化区', [23.548, 113.586]],
    ['深圳:罗湖区', [22.548, 114.127]], ['深圳:福田区', [22.541, 114.055]],
    ['深圳:南山区', [22.531, 113.930]], ['深圳:宝安区', [22.560, 113.883]],
    ['深圳:龙岗区', [22.720, 114.247]], ['深圳:龙华区', [22.610, 114.030]],
    ['深圳:盐田区', [22.556, 114.235]], ['深圳:光明区', [22.762, 113.935]],
    ['深圳:坪山区', [22.691, 114.346]], ['深圳:大鹏新区', [22.590, 114.480]]
  ]);

  static lookup(city: string, district: string): number[] {
    const hit: number[] | undefined = DistrictCoords.MAP.get(`${city}:${district}`);
    if (hit !== undefined) {
      return hit;
    }
    const cityHit: number[] | undefined = DistrictCoords.MAP.get(`${city}:${city}`);
    return cityHit !== undefined ? cityHit : [22.54, 114.06];
  }
}

export class DataSeeder {
  /** 首启灌入：spot 表非空即跳过（幂等）。返回是否执行了灌入。 */
  static async seedIfEmpty(context: common.UIAbilityContext): Promise<boolean> {
    const store: relationalStore.RdbStore = await DatabaseHelper.getStore(context);
    const rs: relationalStore.ResultSet =
      await store.querySql('SELECT COUNT(*) AS c FROM spot');
    let count: number = 0;
    try {
      if (rs.goToFirstRow()) {
        count = rs.getLong(rs.getColumnIndex('c'));
      }
    } finally {
      rs.close();
    }
    if (count > 0) {
      Logger.info(TAG, `已有 ${count} 景点，跳过灌入`);
      return false;
    }
    for (const c of CITIES) {
      const spotLines: string[] = await DataSeeder.readJsonl(context, c.spotsFile);
      const spots: Spot[] = spotLines.map((line: string): Spot => DataSeeder.toSpot(line, c.city));
      await SpotDao.saveSpots(context, spots);
      const areaLines: string[] = await DataSeeder.readJsonl(context, c.areasFile);
      const areas: Area[] = areaLines.map((line: string): Area => DataSeeder.toArea(line, c.city));
      await AreaDao.saveAreas(context, areas);
      Logger.info(TAG, `${c.city} 灌入 spots=${spots.length} areas=${areas.length}`);
    }
    return true;
  }

  static async readJsonl(context: common.UIAbilityContext, path: string): Promise<string[]> {
    try {
      const bytes: Uint8Array = await context.resourceManager.getRawFileContent(path);
      const text: string = new util.TextDecoder().decodeToString(bytes);
      const lines: string[] = text.split('\n').filter((l: string): boolean => l.trim().length > 0);
      return lines;
    } catch (err) {
      throw new AppError(ErrorCode.RDB_INIT_FAILED, `读取种子失败 ${path}: ${(err as Error).message}`);
    }
  }

  static toSpot(line: string, city: string): Spot {
    const o: Obj = JSON.parse(line) as Obj;
    const tags: string[] = o['t'] as Strs;
    const bk: Obj = o['bk'] as Obj;
    const coord: number[] = DistrictCoords.lookup(city, o['d'] as string);
    const spot: Spot = {
      id: o['id'] as string,
      name: o['n'] as string,
      city: city,
      tags: tags.map((t: string): SpotTag => t as SpotTag),
      brief: `${o['n'] as string}（${o['d'] as string}）`,
      suggestedDuration: o['dur'] as number,
      popularity: o['pop'] as number,
      nearbySpotIds: [],
      longitude: coord[1],
      latitude: coord[0],
      district: o['d'] as string,
      nearestMetro: '',
      booking: {
        requiresBooking: bk['req'] === true,
        bookingMethod: (bk['m'] as string).length > 0 ? bk['m'] as string : undefined,
        advanceDays: (bk['adv'] as number) > 0 ? bk['adv'] as number : undefined,
        releaseTime: (bk['rel'] as string).length > 0 ? bk['rel'] as string : undefined,
        closedDay: (bk['closed'] as string).length > 0 ? bk['closed'] as string : undefined,
        difficulty: (bk['diff'] as string).length > 0 ? bk['diff'] as string : undefined
      },
      provenance: { source: 'seed-v1', updatedAt: SEED_DATE, confidence: '中' }
    };
    return spot;
  }

  static toArea(line: string, city: string): Area {
    const o: Obj = JSON.parse(line) as Obj;
    const coord: number[] = DistrictCoords.lookup(city, city);
    const area: Area = {
      id: o['id'] as string,
      name: o['n'] as string,
      city: city,
      longitude: coord[1],
      latitude: coord[0],
      description: `${o['n'] as string}`,
      anchorStations: o['st'] as Strs,
      metroLines: o['lines'] as Strs,
      airportMinutes: o['air'] as number,
      trainStationMinutes: o['train'] as number,
      commerceTags: [],
      diningDensity: o['din'] as string,
      suitableCrowds: o['crowds'] as Strs,
      priceTier: o['tier'] as string as AreaPriceTier,
      group: o['g'] as string as AreaGroup,
      source: 'seed-v1',
      updatedAt: SEED_DATE
    };
    return area;
  }
}
