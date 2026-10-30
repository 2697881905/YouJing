/**
 * Map Kit 检索结果 → Spot/Area 的纯映射（禁依赖 @kit；可离线 tsc + 断言验证）。
 *
 * 三条硬口径（来自 2026-10-31 真机探针）：
 * 1) 评分恒 0、预约字段没有：热度按检索顺序做秩，预约一律 requiresBooking=false 并
 *    由界面标「以官方为准」，不伪造评分/预约；
 * 2) 结果会有重复（西安城墙/城墙·碑林、兵马俑两条）与远郊混入：这里做名称包含 +
 *    近距同前缀的去重，远郊由调用方按区县/距离决定是否展示；
 * 3) 区县 adminLevel3 是 Area 的聚合键；没有酒店供给数据时仍给出区县质心，
 *    但档位/通勤/餐饮一律留空并在界面标「未校准」。
 */

import { Spot, SpotTag } from '../model/Spot';
import { Area, AreaGroup, AreaPriceTier } from '../model/Area';
import { Geo, GeoPoint } from './Geo';

export const MAP_SOURCE: string = 'MapKit';
export const MAP_SPOT_SOURCE: string = 'MapKit 地点检索';

/** 由 data/MapKitCityStore 从 site.Site 抽出的最小字段（纯逻辑不碰 SDK 类型） */
export interface MapSiteInput {
  siteId: string;
  name: string;
  longitude: number;
  latitude: number;
  /** adminLevel3；空串表示没有区县 */
  district: string;
  /** poi.poiTypes */
  types: string[];
  /** 检索顺序，0 起；用于热度秩 */
  rank: number;
  /** poi.abstractText / description，可空 */
  abstractText?: string;
}

export interface MapCityData {
  spots: Spot[];
  areas: Area[];
}

export interface DistrictAgg {
  name: string;
  count: number;
  latitude: number;
  longitude: number;
}

const FAMILY_TYPES: string[] = ['ZOO', 'AQUARIUM', 'PARK', 'BOTANICAL_GARDEN', 'AMUSEMENT_PARK'];
const CLASSIC_TYPES: string[] = ['MUSEUM', 'ART_MUSEUM', 'SCIENCE_MUSEUM', 'TOURIST_ATTRACTION',
  'TEMPLE', 'PLACE_OF_WORSHIP', 'TOWER', 'MEMORIAL', 'LANDMARK'];

function norm(text: string): string {
  return text.trim().replace(/\s+/g, '');
}

function pointOf(site: MapSiteInput): GeoPoint {
  const p: GeoPoint = { latitude: site.latitude, longitude: site.longitude };
  return p;
}

function lcpLen(a: string, b: string): number {
  const max: number = Math.min(a.length, b.length);
  let i: number = 0;
  while (i < max && a.charAt(i) === b.charAt(i)) {
    i += 1;
  }
  return i;
}

function isDuplicate(site: MapSiteInput, kept: MapSiteInput[]): boolean {
  const n1: string = norm(site.name);
  for (const k of kept) {
    const n2: string = norm(k.name);
    if (n1 === n2) {
      return true;
    }
    const km: number = Geo.distanceKm(pointOf(site), pointOf(k));
    // 一个名字包含另一个且相距 3km 内：西安城墙 / 城墙·碑林、大雁塔 / 大雁塔文化休闲景区
    if ((n1.indexOf(n2) >= 0 || n2.indexOf(n1) >= 0) && km <= 3) {
      return true;
    }
    // 同区县、500m 内、共同前缀 ≥3 字：秦始皇帝陵博物院 / 秦始皇兵马俑博物馆
    if (site.district === k.district && km <= 0.5 && lcpLen(n1, n2) >= 3) {
      return true;
    }
  }
  return false;
}

/** 去重并丢掉缺名称/坐标的条目；保留检索顺序（先出现的留下） */
export function dedupeSites(sites: MapSiteInput[]): MapSiteInput[] {
  const kept: MapSiteInput[] = [];
  for (const site of sites) {
    if (norm(site.name).length === 0 || !Geo.usable(site.latitude, site.longitude)) {
      continue;
    }
    if (!isDuplicate(site, kept)) {
      kept.push(site);
    }
  }
  return kept;
}

/** POI 类型 → 四值标签；只映射高置信类型，其余留空（留给屏4「其他」分组） */
export function tagsOfTypes(types: string[]): SpotTag[] {
  const tags: SpotTag[] = [];
  for (const t of types) {
    if (FAMILY_TYPES.indexOf(t) >= 0 && tags.indexOf(SpotTag.FAMILY) < 0) {
      tags.push(SpotTag.FAMILY);
    }
    if (CLASSIC_TYPES.indexOf(t) >= 0 && tags.indexOf(SpotTag.CLASSIC) < 0) {
      tags.push(SpotTag.CLASSIC);
    }
  }
  return tags;
}

/** 无字段可依，按 POI 类型给保守的停留估算；界面需标「估算」 */
export function durationOf(types: string[]): number {
  for (const t of types) {
    if (t === 'ZOO' || t === 'AQUARIUM' || t === 'AMUSEMENT_PARK') {
      return 180;
    }
    if (t === 'MUSEUM' || t === 'ART_MUSEUM' || t === 'SCIENCE_MUSEUM') {
      return 120;
    }
    if (t === 'PARK' || t === 'BOTANICAL_GARDEN') {
      return 90;
    }
    if (t === 'TEMPLE' || t === 'PLACE_OF_WORSHIP') {
      return 60;
    }
    if (t === 'TOWER') {
      return 45;
    }
  }
  return 90;
}

export function typeLabelOf(types: string[]): string {
  for (const t of types) {
    if (t === 'MUSEUM' || t === 'ART_MUSEUM' || t === 'SCIENCE_MUSEUM') {
      return '博物馆';
    }
    if (t === 'TOURIST_ATTRACTION') {
      return '景点';
    }
    if (t === 'PARK' || t === 'BOTANICAL_GARDEN') {
      return '公园';
    }
    if (t === 'ZOO') {
      return '动物园';
    }
    if (t === 'AQUARIUM') {
      return '水族馆';
    }
    if (t === 'TEMPLE' || t === 'PLACE_OF_WORSHIP') {
      return '寺庙';
    }
    if (t === 'TOWER') {
      return '地标';
    }
    if (t === 'MEMORIAL') {
      return '纪念地';
    }
  }
  return '地点';
}

function briefOf(site: MapSiteInput): string {
  const text: string = site.abstractText === undefined ? '' : site.abstractText.trim();
  if (text.length > 0) {
    return text.substring(0, 80);
  }
  const district: string = site.district.length > 0 ? site.district : '地图服务';
  return `${district} · ${typeLabelOf(site.types)}`;
}

/** 检索顺序 → Spot[]；热度是秩不是评分，预约一律 false（界面标注以官方为准） */
export function buildSpots(sites: MapSiteInput[], city: string, today: string): Spot[] {
  const ordered: MapSiteInput[] = sites.slice().sort((a: MapSiteInput, b: MapSiteInput): number =>
    a.rank - b.rank);
  const spots: Spot[] = [];
  for (let i = 0; i < ordered.length; i++) {
    const site: MapSiteInput = ordered[i];
    const spot: Spot = {
      id: `mk:${city}:${site.siteId}`,
      name: site.name,
      city: city,
      tags: tagsOfTypes(site.types),
      brief: briefOf(site),
      suggestedDuration: durationOf(site.types),
      // 100 → 5：第 1 名最高，越后越低；没有评分可用，不冒充评分
      popularity: Math.max(5, 100 - Math.min(95, site.rank * 2)),
      nearbySpotIds: [],
      longitude: site.longitude,
      latitude: site.latitude,
      district: site.district.length > 0 ? site.district : '地图服务',
      nearestMetro: '',
      booking: { requiresBooking: false },
      provenance: { source: MAP_SPOT_SOURCE, updatedAt: today, confidence: '中' }
    };
    spots.push(spot);
  }
  return spots;
}

/** 按区县聚合坐标与景点数 */
export function groupDistricts(sites: MapSiteInput[]): DistrictAgg[] {
  const byDistrict: Map<string, MapSiteInput[]> = new Map<string, MapSiteInput[]>();
  for (const site of sites) {
    if (!Geo.usable(site.latitude, site.longitude)) {
      continue;
    }
    const name: string = site.district.length > 0 ? site.district : '地图服务';
    const list: MapSiteInput[] | undefined = byDistrict.get(name);
    if (list === undefined) {
      byDistrict.set(name, [site]);
    } else {
      list.push(site);
    }
  }
  const out: DistrictAgg[] = [];
  byDistrict.forEach((list: MapSiteInput[], name: string): void => {
    let lat: number = 0;
    let lng: number = 0;
    for (const s of list) {
      lat += s.latitude;
      lng += s.longitude;
    }
    const agg: DistrictAgg = {
      name: name, count: list.length,
      latitude: lat / list.length, longitude: lng / list.length
    };
    out.push(agg);
  });
  out.sort((a: DistrictAgg, b: DistrictAgg): number => b.count - a.count);
  return out;
}

/**
 * 区县 → Area：取景点数最多的 6 个区县；有酒店供给的区县优先。
 * 住宿档/通勤/餐饮没有可靠字段，一律留空并在界面标「未校准」。
 */
export function buildAreas(sites: MapSiteInput[], city: string, today: string,
  hotelCounts: Record<string, number>): Area[] {
  const districts: DistrictAgg[] = groupDistricts(sites);
  const withHotel: DistrictAgg[] = [];
  for (const d of districts) {
    const count: number = hotelCounts[d.name] === undefined ? 0 : hotelCounts[d.name];
    if (count > 0) {
      withHotel.push(d);
    }
  }
  const pool: DistrictAgg[] = withHotel.length > 0 ? withHotel : districts;
  const top: DistrictAgg[] = pool.slice(0, 6);
  const areas: Area[] = [];
  for (const d of top) {
    const name: string = d.name === '地图服务' ? `${city}市区` : d.name;
    const area: Area = {
      id: `mk-area:${city}:${name}`,
      name: name,
      city: city,
      longitude: d.longitude,
      latitude: d.latitude,
      description: `${city}${name} · 地图服务区县，住宿档与通勤未校准`,
      anchorStations: [],
      metroLines: [],
      airportMinutes: 0,
      trainStationMinutes: 0,
      commerceTags: ['地图服务'],
      diningDensity: '',
      suitableCrowds: [],
      priceTier: AreaPriceTier.COMFORT,
      group: AreaGroup.CORE,
      source: MAP_SOURCE,
      updatedAt: today
    };
    areas.push(area);
  }
  return areas;
}

export function isMapArea(area: Area): boolean {
  return area.source === MAP_SOURCE;
}

/**
 * 校验一条 POI 是否真的属于请求城市。
 *
 * 真机实测（2026-10-31）：无效 cityId（如「不存在市」）不会报错，而是返回全国结果
 * （红旗渠、岳阳楼、赛里木湖都出现）；isCityLimit 也拦不住。因此必须用
 * locality / adminLevel2 / adminLevel3 做归属校验，三项都不含城市名就丢弃。
 * adminLevel2 实测是**市级**字段（adminLevel1 才是省）：只查这三项，不查 adminLevel1，
 * 避免「吉林市 / 吉林省」这类省名与市名相同的误伤；也不看 formatAddress，
 * 后者可能把「北京东路」这类路名误判成北京。
 */
export function addressMatchesCity(locality: string, admin2: string, admin3: string,
  city: string): boolean {
  const trimmed: string = city.trim();
  if (trimmed.length === 0) {
    return false;
  }
  const key: string = trimmed.endsWith('市') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
  if (key.length === 0) {
    return false;
  }
  return locality.indexOf(key) >= 0 || admin2.indexOf(key) >= 0 || admin3.indexOf(key) >= 0;
}
