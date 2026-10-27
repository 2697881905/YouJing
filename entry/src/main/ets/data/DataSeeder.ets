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

const TAG: string = 'Data.Seeder';
const SEED_DATE: string = '2026-10-23';
/** 种子结构版本：jsonl 字段或坐标数据一变就 bump，触发已装机 upsert 回填 */
const SEED_VERSION: string = 'v2-geo-3-yl';
const SEED_PREFS: string = 'youjing_seed';
const KEY_SEED_VERSION: string = 'version';
/** 坐标缺失时片区不落点（0 会被 MapStops.usable 滤掉），比按城市质心插错地方诚实 */
const NO_COORD: number = 0;

/** 标签白名单（SpotTag 四值封闭）：种子里的陌生值直接丢，不猜 */
const SPOT_TAGS: string[] = ['must_see', 'classic', 'niche', 'family'];
const AREA_TIERS: string[] = ['economy', 'comfort', 'luxury'];
const AREA_GROUPS: string[] = ['core', 'commercial', 'metro'];

interface CitySeed {
  city: string;
  spotsFile: string;
  areasFile: string;
}

const CITIES: CitySeed[] = [
  { city: '北京', spotsFile: 'seed/spots_beijing.jsonl', areasFile: 'seed/areas_beijing.jsonl' },
  { city: '上海', spotsFile: 'seed/spots_shanghai.jsonl', areasFile: 'seed/areas_shanghai.jsonl' },
  { city: '广州', spotsFile: 'seed/spots_guangzhou.jsonl', areasFile: 'seed/areas_guangzhou.jsonl' },
  { city: '深圳', spotsFile: 'seed/spots_shenzhen.jsonl', areasFile: 'seed/areas_shenzhen.jsonl' },
  // 杨凌：用户本人所在地，拿来当"真实用户视角"的测试城。
  // 坐标是按公开资料里**街道/村镇位置**给的近似值（与 DistrictCoords 同一档精度），
  // 精确经纬度待地理编码回填；`lines` 用公交线名，因为杨凌没有轨道交通。
  { city: '杨凌', spotsFile: 'seed/spots_yangling.jsonl', areasFile: 'seed/areas_yangling.jsonl' }
];

/** 区中心近似坐标（度）。正式经纬度待 Map Kit 地理编码回填。 */
export class DistrictCoords {
  private static readonly MAP: Map<string, number[]> = new Map<string, number[]>([
    ['杨凌:杨陵区', [34.2727, 108.0811]],
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
      const spots: Spot[] = [];
      for (const line of spotLines) {
        const spot: Spot | null = DataSeeder.toSpot(line, c.city);
        if (spot !== null) {
          spots.push(spot);
        }
      }
      await SpotDao.saveSpots(context, spots);
      const areaLines: string[] = await DataSeeder.readJsonl(context, c.areasFile);
      const areas: Area[] = [];
      for (const line of areaLines) {
        const area: Area | null = DataSeeder.toArea(line, c.city);
        if (area !== null) {
          areas.push(area);
        }
      }
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

  // ---- 种子行安全读取原语：JSON.parse 出来的是 Object，禁直接断言 ----
  // 缺键/错类型一律走默认值或跳过该行；一个坏键不该在首启 bootstrap 里炸掉启动
  private static strOf(o: Obj, key: string, fallback: string): string {
    const v: Object | undefined = o[key];
    return typeof v === 'string' ? v as string : fallback;
  }

  private static numOf(o: Obj, key: string, fallback: number): number {
    const v: Object | undefined = o[key];
    return typeof v === 'number' && Number.isFinite(v) ? v as number : fallback;
  }

  private static strsOf(o: Obj, key: string): string[] {
    const v: Object | undefined = o[key];
    if (!Array.isArray(v)) {
      return [];
    }
    // Array.isArray 窄化后 ArkTS 仍按 any[] 处理，先显式转成 Object[] 再遍历
    const arr: Object[] = v as Object[];
    const out: string[] = [];
    for (const item of arr) {
      if (typeof item === 'string') {
        out.push(item as string);
      }
    }
    return out;
  }

  private static objOf(o: Obj, key: string): Obj {
    const v: Object | undefined = o[key];
    if (typeof v === 'object' && v !== null && !Array.isArray(v)) {
      return v as Obj;
    }
    return {};
  }

  /** 白名单过滤：只保留契约枚举内的值，顺序保持种子序 */
  private static whitelist(values: string[], allowed: string[]): string[] {
    const out: string[] = [];
    for (const v of values) {
      if (allowed.indexOf(v) >= 0 && out.indexOf(v) < 0) {
        out.push(v);
      }
    }
    return out;
  }

  /**
   * 单值枚举白名单：命中返回原值，否则返回 fallback。
   * 不能写成 `whitelist([v], allowed)[0]`——键存在但值非法时 whitelist 返回空数组，
   * 下标取到 undefined 会直接写进库（ohosTest 的 toArea_whitelist_fallback 抓到过）。
   */
  private static pickEnum(value: string, allowed: string[], fallback: string): string {
    return allowed.indexOf(value) >= 0 ? value : fallback;
  }

  /**
   * 种子行 → Spot。id/name 缺失或 JSON 坏行返回 null（该行不灌库）。
   * brief / nearestMetro / entranceTip / nearbySpotIds：种子未采集这些字段，
   * 一律留空——不拿「名称（区）」冒充简介，也不编地铁站名（§3.2 数据缺口登记在 INIT_REPORT）。
   */
  static toSpot(line: string, city: string): Spot | null {
    let o: Obj;
    try {
      o = JSON.parse(line) as Obj;
    } catch (err) {
      Logger.warn(TAG, `景点种子行 JSON 解析失败，跳过: ${line.substring(0, 40)}`);
      return null;
    }
    const id: string = DataSeeder.strOf(o, 'id', '');
    const name: string = DataSeeder.strOf(o, 'n', '');
    const district: string = DataSeeder.strOf(o, 'd', '');
    if (id.length === 0 || name.length === 0) {
      Logger.warn(TAG, `景点种子行缺 id/name，跳过: ${line.substring(0, 40)}`);
      return null;
    }
    const bk: Obj = DataSeeder.objOf(o, 'bk');
    const geo: number[] | null = DataSeeder.geoOf(o);
    const coord: number[] = geo !== null ? geo : DistrictCoords.lookup(city, district);
    const method: string = DataSeeder.strOf(bk, 'm', '');
    const release: string = DataSeeder.strOf(bk, 'rel', '');
    const closed: string = DataSeeder.strOf(bk, 'closed', '');
    const diff: string = DataSeeder.strOf(bk, 'diff', '');
    const advance: number = DataSeeder.numOf(bk, 'adv', 0);
    const spot: Spot = {
      id: id,
      name: name,
      city: city,
      tags: DataSeeder.whitelist(DataSeeder.strsOf(o, 't'), SPOT_TAGS).map(
        (t: string): SpotTag => t as SpotTag),
      brief: '',
      suggestedDuration: Math.max(1, DataSeeder.numOf(o, 'dur', 60)),
      popularity: DataSeeder.numOf(o, 'pop', 50),
      nearbySpotIds: [],
      longitude: coord[1],
      latitude: coord[0],
      district: district,
      nearestMetro: '',
      booking: {
        requiresBooking: bk['req'] === true,
        bookingMethod: method.length > 0 ? method : undefined,
        advanceDays: advance > 0 ? advance : undefined,
        releaseTime: release.length > 0 ? release : undefined,
        closedDay: closed.length > 0 ? closed : undefined,
        difficulty: diff.length > 0 ? diff : undefined
      },
      provenance: {
        source: geo !== null ? 'seed-v2-geo' : 'seed-v1',
        updatedAt: SEED_DATE,
        confidence: geo !== null ? '中' : '低'
      }
    };
    return spot;
  }

  /**
   * 种子行 → Area。id/name 缺失或 JSON 坏行返回 null。
   * description：种子未采集一句话描述，留空（不拿区域名冒充）。
   * priceTier / group 白名单校验，陌生值落到默认档（comfort / metro）。
   */
  static toArea(line: string, city: string): Area | null {
    let o: Obj;
    try {
      o = JSON.parse(line) as Obj;
    } catch (err) {
      Logger.warn(TAG, `区域种子行 JSON 解析失败，跳过: ${line.substring(0, 40)}`);
      return null;
    }
    const id: string = DataSeeder.strOf(o, 'id', '');
    const name: string = DataSeeder.strOf(o, 'n', '');
    if (id.length === 0 || name.length === 0) {
      Logger.warn(TAG, `区域种子行缺 id/name，跳过: ${line.substring(0, 40)}`);
      return null;
    }
    // 片区没有「所在区」字段，编不出坐标就不落点：以前统一取 lookup(city, city)，
    // 而表里没有 city:city 键，四城 144 片全部落到深圳那个兜底值上
    const geo: number[] | null = DataSeeder.geoOf(o);
    const coord: number[] = geo !== null ? geo : [NO_COORD, NO_COORD];
    // 白名单逐项判定：键缺失走 strOf 默认值、键在但值非法走 pickEnum 回退，
    // 两条路都不会把 undefined 写进库
    const tier: string = DataSeeder.pickEnum(
      DataSeeder.strOf(o, 'tier', 'comfort'), AREA_TIERS, 'comfort');
    const group: string = DataSeeder.pickEnum(
      DataSeeder.strOf(o, 'g', 'metro'), AREA_GROUPS, 'metro');
    const area: Area = {
      id: id,
      name: name,
      city: city,
      longitude: coord[1],
      latitude: coord[0],
      description: '',
      anchorStations: DataSeeder.strsOf(o, 'st'),
      metroLines: DataSeeder.strsOf(o, 'lines'),
      airportMinutes: Math.max(0, DataSeeder.numOf(o, 'air', 0)),
      trainStationMinutes: Math.max(0, DataSeeder.numOf(o, 'train', 0)),
      commerceTags: [],
      diningDensity: DataSeeder.strOf(o, 'din', ''),
      suitableCrowds: DataSeeder.strsOf(o, 'crowds'),
      priceTier: tier as AreaPriceTier,
      group: group as AreaGroup,
      source: geo !== null ? 'seed-v2-geo' : 'seed-v1',
      updatedAt: SEED_DATE
    };
    return area;
  }
}
