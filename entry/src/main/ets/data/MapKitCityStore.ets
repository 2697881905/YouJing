/**
 * 任意城市数据源（Stage 2）：Map Kit 地点检索 → Spot/Area。
 *
 * 三条约束（2026-10-31 探针结论 / Docs/MapKit地点检索探针-2026-10-31.md）：
 * - 结果只放内存，30 分钟 TTL；**不写 RDB、不落缓存文件**，许可边界未确认前不持久化；
 * - 检索必须带 cityId + isCityLimit=true，否则会拿到全球结果；
 * - 评分/预约字段不可得：映射层按检索秩给热度、预约一律 false，界面标「以官方为准」。
 */

import { site, mapCommon } from '@kit.MapKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppError } from '../common/error/AppError';
import { ErrorCode } from '../common/error/ErrorCode';
import { Logger } from '../common/logger/Logger';
import { DateUtils } from '../utils/DateUtils';
import {
  DistrictAgg, MapCityData, MapSiteInput, addressMatchesCity, buildAreas, buildSpots, dedupeSites,
  groupDistricts
} from '../utils/MapCityMapper';

const TAG: string = 'Data.MapCity';
const PAGE_SIZE: number = 20;
const MAX_PAGES: number = 3;
const MAX_DISTRICTS: number = 10;
const HOTEL_RADIUS: number = 3000;
const TTL_MS: number = 30 * 60 * 1000;

interface CachedCity {
  data: MapCityData;
  at: number;
}

export class MapKitCityStore {
  private static cache: Map<string, CachedCity> = new Map<string, CachedCity>();

  /** 取一座城市的景点/住宿区；命中 30 分钟缓存则不再请求 */
  static async load(context: common.Context, city: string): Promise<MapCityData> {
    const hit: CachedCity | undefined = MapKitCityStore.cache.get(city);
    if (hit !== undefined && Date.now() - hit.at < TTL_MS) {
      Logger.info(TAG, `${city} 命中缓存 spots=${hit.data.spots.length} areas=${hit.data.areas.length}`);
      return hit.data;
    }
    const data: MapCityData = await MapKitCityStore.fetch(context, city);
    MapKitCityStore.cache.set(city, { data: data, at: Date.now() });
    return data;
  }

  private static async fetch(context: common.Context, city: string): Promise<MapCityData> {
    const startedAt: number = Date.now();
    try {
      // 「西安市」这类带行政后缀的输入退一层再送 cityId；展示仍用用户原输入
      const cityId: string = city.endsWith('市') ? city.substring(0, city.length - 1) : city;
      const inputs: MapSiteInput[] = [];
      let rank: number = 0;
      for (let page = 1; page <= MAX_PAGES; page++) {
        const sites: site.Site[] = await MapKitCityStore.searchPage(context, cityId, page);
        if (sites.length === 0) {
          break;
        }
        for (const s of sites) {
          const input: MapSiteInput | null = MapKitCityStore.toInput(s, rank, cityId);
          if (input !== null) {
            inputs.push(input);
            rank += 1;
          }
        }
        if (sites.length < PAGE_SIZE) {
          break;
        }
      }
      const deduped: MapSiteInput[] = dedupeSites(inputs);
      if (deduped.length === 0) {
        throw new AppError(ErrorCode.MAP_CITY_DATA_FAILED, `地图服务没有返回「${city}」的景点`);
      }
      const hotelCounts: Record<string, number> = {};
      // 先给更多区县查供给，映射层再按供给排序取前 8；否则远郊高景点数区县会挤掉市中心
      const districts: DistrictAgg[] = groupDistricts(deduped).slice(0, MAX_DISTRICTS);
      // 区县之间没有依赖：串行 10 次 nearbySearch 要等约 4–5 秒，并发后取最慢的一条
      const hotelJobs: Promise<number>[] = [];
      for (const d of districts) {
        hotelJobs.push(MapKitCityStore.hotelCount(context, d.latitude, d.longitude));
      }
      const counts: number[] = await Promise.all(hotelJobs);
      for (let i = 0; i < districts.length; i++) {
        hotelCounts[districts[i].name] = counts[i];
      }
      const today: string = DateUtils.todayIso();
      const spots = buildSpots(deduped, city, today);
      const areas = buildAreas(deduped, city, today, hotelCounts);
      Logger.info(TAG, `${city} raw=${inputs.length} deduped=${deduped.length} ` +
        `spots=${spots.length} areas=${areas.length} districts=${districts.length} ` +
        `costMs=${Date.now() - startedAt}`);
      const data: MapCityData = { spots: spots, areas: areas };
      return data;
    } catch (err) {
      if (err instanceof AppError) {
        throw err;
      }
      const e: BusinessError = err as BusinessError;
      Logger.warn(TAG, `${city} 检索失败 code=${e.code} msg=${e.message}`);
      throw new AppError(ErrorCode.MAP_CITY_DATA_FAILED, `地图服务请求失败（${e.code}）`, e as Error);
    }
  }

  private static async searchPage(context: common.Context, cityId: string,
    page: number): Promise<site.Site[]> {
    const params: site.SearchByTextParams = {
      query: '景点', cityId: cityId, isCityLimit: true,
      pageIndex: page, pageSize: PAGE_SIZE, language: 'zh-CN'
    };
    const result: site.SearchByTextResult = await site.searchByText(context, params);
    return result.sites === undefined ? [] : result.sites;
  }

  private static toInput(s: site.Site, rank: number, cityKey: string): MapSiteInput | null {
    const location: mapCommon.LatLng | undefined = s.location;
    const name: string = s.name === undefined ? '' : s.name.trim();
    if (location === undefined || name.length === 0) {
      return null;
    }
    const poi: site.Poi | undefined = s.poi;
    const types: string[] = poi === undefined || poi.poiTypes === undefined ? [] : poi.poiTypes;
    let abstractText: string = '';
    if (poi !== undefined) {
      if (poi.abstractText !== undefined) {
        abstractText = poi.abstractText;
      } else if (poi.description !== undefined) {
        abstractText = poi.description;
      }
    }
    const hoursTexts: string[] = poi === undefined || poi.openingHours === undefined ||
      poi.openingHours.texts === undefined ? [] : poi.openingHours.texts;
    const addr: site.AddressComponent = s.addressComponent;
    const locality: string = addr.locality === undefined ? '' : addr.locality;
    const admin2: string = addr.adminLevel2 === undefined ? '' : addr.adminLevel2;
    const district: string = addr.adminLevel3 !== undefined ? addr.adminLevel3 :
      (locality.length > 0 ? locality : '');
    if (rank === 0) {
      // 首条地址字段真机实测：admin2 是市级、admin3 是区县级，用来兜城市归属
      Logger.info(TAG, `${cityKey} 地址样本 locality=${locality} admin2=${admin2} admin3=${district}`);
    }
    // 无效 cityId 会静默返回全国结果：必须验归属，否则「不存在市」也能出 60 个景点
    if (!addressMatchesCity(locality, admin2, district, cityKey)) {
      return null;
    }
    const input: MapSiteInput = {
      siteId: s.siteId, name: name, longitude: location.longitude, latitude: location.latitude,
      district: district, types: types, rank: rank, abstractText: abstractText,
      openingHoursTexts: hoursTexts
    };
    return input;
  }

  private static async hotelCount(context: common.Context, lat: number, lng: number): Promise<number> {
    const location: mapCommon.LatLng = { latitude: lat, longitude: lng };
    const params: site.NearbySearchParams = {
      location: location, query: '酒店', radius: HOTEL_RADIUS, pageSize: 1
    };
    try {
      const result: site.NearbySearchResult = await site.nearbySearch(context, params);
      return result.totalCount;
    } catch (err) {
      // 单个区县的住宿供给查不到不阻断整座城市；映射层会在「有供给」为空时退回全部区县
      Logger.warn(TAG, `酒店供给查询失败 code=${(err as BusinessError).code}`);
      return 0;
    }
  }
}
