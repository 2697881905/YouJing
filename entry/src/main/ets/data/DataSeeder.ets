/**
 * 内置资产种子导入（开发文档 §6 阶段 5）。
 *
 * 数据来源：seed-v1 公开常识整理（用户拍板）。v2 起补逐条经纬度：
 * 由 Photon(OpenStreetMap) 按景点名/片区锚定站名地理编码得 WGS84，再转 GCJ02 落进
 * seed/*.jsonl 的 la/lo 字段——Map Kit 在中国大陆按 GCJ02 绘制，喂 WGS84 会整体偏几百米。
 * 没编出坐标的行仍退回区中心（景点）或不落点（片区），并在 provenance.source 上区分开。
 * 预约信息 UI 标「以官方为准」。
 * 幂等：spot 表有行且种子版本一致即跳过；版本变了整表 upsert（同 id ON_CONFLICT_REPLACE），
 * 已装机用户不必清数据也能拿到新坐标。
 */

import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { preferences, relationalStore } from '@kit.ArkData';
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
/** 种子结构版本：jsonl 字段或坐标数据一变就 bump，触发已装机 upsert 回填 */
const SEED_VERSION: string = 'v2-geo-2';
const SEED_PREFS: string = 'youjing_seed';
const KEY_SEED_VERSION: string = 'version';
/** 坐标缺失时片区不落点（0 会被 MapStops.usable 滤掉），比按城市质心插错地方诚实 */
const NO_COORD: number = 0;

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
  /** 首启灌入 + 种子版本升级回填：库里有行且版本一致才跳过。返回是否执行了灌入。 */
  static async seedIfEmpty(context: common.Context): Promise<boolean> {
    const count: number = await DataSeeder.spotCount(context);
    const stored: string = DataSeeder.storedVersion(context);
    if (count > 0 && stored === SEED_VERSION) {
      Logger.info(TAG, `已有 ${count} 景点，种子 ${SEED_VERSION} 已灌，跳过`);
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
    DataSeeder.recordVersion(context);
    return true;
  }

  private static async spotCount(context: common.Context): Promise<number> {
    const store: relationalStore.RdbStore = await DatabaseHelper.getStore(context);
    const rs: relationalStore.ResultSet = await store.querySql('SELECT COUNT(*) AS c FROM spot');
    try {
      return rs.goToFirstRow() ? rs.getLong(rs.getColumnIndex('c')) : 0;
    } finally {
      rs.close();
    }
  }

  private static storedVersion(context: common.Context): string {
    try {
      const prefs: preferences.Preferences =
        preferences.getPreferencesSync(context, { name: SEED_PREFS });
      return prefs.getSync(KEY_SEED_VERSION, '') as string;
    } catch (err) {
      Logger.warn(TAG, `种子版本读取失败，按未灌处理: ${(err as Error).message}`);
      return '';
    }
  }

  private static recordVersion(context: common.Context): void {
    try {
      const prefs: preferences.Preferences =
        preferences.getPreferencesSync(context, { name: SEED_PREFS });
      prefs.putSync(KEY_SEED_VERSION, SEED_VERSION);
      prefs.flushSync();
    } catch (err) {
      Logger.warn(TAG, `种子版本写入失败: ${(err as Error).message}`);
    }
  }

  static async readJsonl(context: common.Context, path: string): Promise<string[]> {
    try {
      const bytes: Uint8Array = await context.resourceManager.getRawFileContent(path);
      const text: string = new util.TextDecoder().decodeToString(bytes);
      const lines: string[] = text.split('\n').filter((l: string): boolean => l.trim().length > 0);
      return lines;
    } catch (err) {
      throw new AppError(ErrorCode.RDB_INIT_FAILED, `读取种子失败 ${path}: ${(err as Error).message}`);
    }
  }

  /** 种子行自带的 GCJ02 坐标（la=纬度/lo=经度）；缺字段或非法值返回 null */
  private static geoOf(o: Obj): number[] | null {
    const la: Object | undefined = o['la'];
    const lo: Object | undefined = o['lo'];
    if (typeof la !== 'number' || typeof lo !== 'number') {
      return null;
    }
    if (la < 18 || la > 54 || lo < 73 || lo > 135) {
      return null;
    }
    return [la, lo];
  }

  static toSpot(line: string, city: string): Spot {
    const o: Obj = JSON.parse(line) as Obj;
    const tags: string[] = o['t'] as Strs;
    const bk: Obj = o['bk'] as Obj;
    const geo: number[] | null = DataSeeder.geoOf(o);
    const coord: number[] = geo !== null ? geo : DistrictCoords.lookup(city, o['d'] as string);
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
      provenance: {
        source: geo !== null ? 'seed-v2-geo' : 'seed-v1',
        updatedAt: SEED_DATE,
        confidence: geo !== null ? '中' : '低'
      }
    };
    return spot;
  }

  static toArea(line: string, city: string): Area {
    const o: Obj = JSON.parse(line) as Obj;
    // 片区没有「所在区」字段，编不出坐标就不落点：以前统一取 lookup(city, city)，
    // 而表里没有 city:city 键，四城 144 片全部落到深圳那个兜底值上
    const geo: number[] | null = DataSeeder.geoOf(o);
    const coord: number[] = geo !== null ? geo : [NO_COORD, NO_COORD];
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
      source: geo !== null ? 'seed-v2-geo' : 'seed-v1',
      updatedAt: SEED_DATE
    };
    return area;
  }
}
