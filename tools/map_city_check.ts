/**
 * Stage 2（Map Kit 任意城市映射）纯逻辑离线断言。
 * 与 entry/src/ohosTest/ets/test/MapCityMapper.test.ets 同源。
 */

import {
  MapSiteInput, addressMatchesCity, buildAreas, buildSpots, commonHours, dedupeSites,
  groupDistricts, isMapArea, tagsOfTypes, durationOf, typeLabelOf
} from '../entry/src/main/ets/utils/MapCityMapper';
import { isMapCity, POPULAR_MAP_CITIES } from '../entry/src/main/ets/common/constants/Cities';
import { Spot, SpotTag } from '../entry/src/main/ets/model/Spot';
import { Area } from '../entry/src/main/ets/model/Area';

let passed: number = 0;

function ok(cond: boolean, label: string): void {
  if (!cond) {
    throw new Error(`FAIL ${label}`);
  }
  passed += 1;
}

function eq(actual: string | number | boolean, expected: string | number | boolean, label: string): void {
  if (actual !== expected) {
    throw new Error(`FAIL ${label}: actual=${actual} expected=${expected}`);
  }
  passed += 1;
}

function site(id: string, name: string, lat: number, lng: number, district: string,
  types: string[], rank: number, abstractText: string = ''): MapSiteInput {
  const s: MapSiteInput = {
    siteId: id, name: name, latitude: lat, longitude: lng, district: district,
    types: types, rank: rank, abstractText: abstractText
  };
  return s;
}

// ---------- 去重 ----------
const raw: MapSiteInput[] = [
  site('a', '西安城墙', 34.26356, 108.92537, '新城区', ['TOURIST_ATTRACTION'], 0),
  site('b', '西安城墙·碑林历史文化景区', 34.26383, 108.94830, '新城区', ['TOURIST_ATTRACTION'], 1),
  site('c', '秦始皇帝陵博物院', 34.38768, 109.28283, '临潼区', ['TOURIST_ATTRACTION'], 2),
  site('d', '秦始皇兵马俑博物馆', 34.38626, 109.28201, '临潼区', ['MUSEUM'], 3),
  site('e', '大雁塔文化休闲景区', 34.21905, 108.96421, '雁塔区', ['TOURIST_ATTRACTION'], 4,
    '唐代玄奘为保存佛经主持修建的七层方形砖塔，世界文化遗产。'),
  site('f', '陕西历史博物馆', 34.22414, 108.95506, '雁塔区', ['MUSEUM'], 5),
  site('g', ' 大雁塔文化休闲景区 ', 34.21905, 108.96421, '雁塔区', ['TOURIST_ATTRACTION'], 6),
  site('h', '无坐标景点', 0, 0, '雁塔区', ['PARK'], 7),
  site('i', '', 34.2, 108.9, '雁塔区', ['PARK'], 8)
];
const deduped: MapSiteInput[] = dedupeSites(raw);
eq(deduped.length, 4, 'dedupe.length');
eq(deduped[0].siteId, 'a', 'dedupe.keepFirstWall');
eq(deduped[1].siteId, 'c', 'dedupe.keepFirstTerracotta');
eq(deduped[2].siteId, 'e', 'dedupe.keepPagoda');
eq(deduped[3].siteId, 'f', 'dedupe.keepMuseum');

// ---------- Spot 映射 ----------
const spots: Spot[] = buildSpots(deduped, '西安', '2026-10-31');
eq(spots.length, 4, 'spots.length');
eq(spots[0].id, 'mk:西安:a', 'spots.id');
eq(spots[0].name, '西安城墙', 'spots.name');
eq(spots[0].tags.indexOf(SpotTag.CLASSIC) >= 0, true, 'spots.classicTag');
eq(spots[0].suggestedDuration, 90, 'spots.durationDefault');
eq(spots[0].popularity, 100, 'spots.popularityFirst');
eq(spots[0].booking.requiresBooking, false, 'spots.bookingFalse');
eq(spots[0].provenance.source, 'MapKit 地点检索', 'spots.provenance');
eq(spots[0].district, '新城区', 'spots.district');
eq(spots[2].brief.indexOf('唐代玄奘') >= 0, true, 'spots.briefAbstract');
eq(spots[2].brief.length <= 80, true, 'spots.briefCapped');
eq(spots[3].brief, '雁塔区 · 博物馆', 'spots.briefFallback');
eq(spots[3].suggestedDuration, 120, 'spots.museumDuration');
const hoursSite: MapSiteInput = site('h', '有开放时间', 34.2, 108.9, '雁塔区', ['MUSEUM'], 0);
hoursSite.openingHoursTexts = ['星期一: 8:30 - 17:00', '星期二: 8:30 - 17:00'];
const hoursSpots: Spot[] = buildSpots([hoursSite], '测试', '2026-10-31');
eq(hoursSpots[0].openingHours === undefined ? '' : hoursSpots[0].openingHours, '8:30–17:00',
  'spots.openingHours');
eq(commonHours(['星期一: 8:30 - 17:00', '星期二: 8:30 - 17:00']), '8:30–17:00', 'hours.common');
eq(commonHours(['星期一: 0:00 - 23:59']), '全天开放', 'hours.allDay');
eq(commonHours(['星期一: 8:30 - 17:00', '星期二: 9:00 - 17:00']), '', 'hours.variable');
eq(commonHours(['星期一: 休息']), '', 'hours.closed');
eq(commonHours([]), '', 'hours.empty');
eq(commonHours(['星期一: 9:00 - 12:00, 13:00 - 17:00']), '', 'hours.multiRange');
eq(durationOf(['ZOO']), 180, 'dur.zoo');
eq(durationOf(['TOWER']), 45, 'dur.tower');
eq(durationOf([]), 90, 'dur.default');
eq(tagsOfTypes(['ZOO']).indexOf(SpotTag.FAMILY) >= 0, true, 'tags.family');
eq(tagsOfTypes(['MUSEUM']).indexOf(SpotTag.CLASSIC) >= 0, true, 'tags.classic');
eq(tagsOfTypes(['SOMETHING_ELSE']).length, 0, 'tags.empty');
eq(typeLabelOf(['ZOO']), '动物园', 'label.zoo');

// ---------- 区县聚合 ----------
const districts = groupDistricts(deduped);
eq(districts.length, 3, 'districts.length');
eq(districts[0].name, '雁塔区', 'districts.top');
eq(districts[0].count, 2, 'districts.topCount');
eq(districts[0].latitude > 34.2 && districts[0].latitude < 34.23, true, 'districts.centroidLat');

// ---------- Area 映射 ----------
const hotel: Record<string, number> = {};
hotel['雁塔区'] = 486;
hotel['临潼区'] = 0;
hotel['新城区'] = 120;
const areas: Area[] = buildAreas(deduped, '西安', '2026-10-31', hotel);
eq(areas.length, 2, 'areas.withHotelOnly');
eq(areas[0].name, '雁塔区', 'areas.top');
eq(areas[0].source, 'MapKit', 'areas.source');
eq(areas[0].priceTier, 'comfort', 'areas.tier');
eq(areas[0].airportMinutes, 0, 'areas.noFakeMinutes');
eq(areas[0].metroLines.length, 0, 'areas.noFakeMetro');
eq(isMapArea(areas[0]), true, 'areas.isMap');
const allAreas: Area[] = buildAreas(deduped, '西安', '2026-10-31', {});
eq(allAreas.length, 3, 'areas.noSupplyFallsBackToAll');
eq(isMapArea(allAreas[0]), true, 'areas.noSupplyStillMap');

const spread: MapSiteInput[] = [
  site('c1', '中心景点一', 34.26, 108.94, '中心区', ['TOURIST_ATTRACTION'], 0),
  site('c2', '中心景点二', 34.27, 108.95, '中心区', ['TOURIST_ATTRACTION'], 1),
  site('f1', '远郊景点一', 34.50, 109.50, '远郊区', ['TOURIST_ATTRACTION'], 2),
  site('f2', '远郊景点二', 34.51, 109.51, '远郊区', ['TOURIST_ATTRACTION'], 3),
  site('f3', '远郊景点三', 34.52, 109.52, '远郊区', ['TOURIST_ATTRACTION'], 4)
];
const spreadHotels: Record<string, number> = {};
spreadHotels['中心区'] = 500;
spreadHotels['远郊区'] = 10;
const spreadAreas: Area[] = buildAreas(spread, '测试', '2026-10-31', spreadHotels);
eq(spreadAreas.length, 2, 'areas.spreadLength');
eq(spreadAreas[0].name, '中心区', 'areas.hotelSupplyFirst');

// ---------- 城市判定 ----------
eq(isMapCity('西安'), true, 'city.map');
eq(isMapCity('西安市'), true, 'city.mapWithSuffix');
eq(isMapCity('北京'), false, 'city.seed');
eq(isMapCity('京都'), false, 'city.mock');
eq(isMapCity('京都（示例数据）'), false, 'city.mockLabel');
eq(isMapCity(''), false, 'city.empty');
eq(POPULAR_MAP_CITIES.length, 8, 'city.popularCount');
ok(POPULAR_MAP_CITIES.every((c: string): boolean => isMapCity(c)), 'city.popularAllMap');

// ---------- POI 归属校验（无效 cityId 会返回全国结果的兜底） ----------
eq(addressMatchesCity('西安市', '陕西省', '雁塔区', '西安'), true, 'match.xian');
eq(addressMatchesCity('西安市', '陕西省', '雁塔区', '西安市'), true, 'match.xianSuffix');
eq(addressMatchesCity('成都市', '四川省', '青羊区', '成都'), true, 'match.chengdu');
eq(addressMatchesCity('北京市', '北京市', '东城区', '北京'), true, 'match.beijing');
eq(addressMatchesCity('林州市', '安阳市', '林州市', '不存在'), false, 'match.invalid');
eq(addressMatchesCity('岳阳市', '岳阳市', '岳阳楼区', '不存在'), false, 'match.invalid2');
eq(addressMatchesCity('上海市', '上海市', '浦东新区', '北京'), false, 'match.otherCity');
eq(addressMatchesCity('', '', '', '西安'), false, 'match.emptyAddress');

console.log(`PASS ${passed}/${passed}`);
