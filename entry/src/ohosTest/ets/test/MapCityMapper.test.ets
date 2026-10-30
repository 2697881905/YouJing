/**
 * Stage 2 回归：Map Kit 检索结果 → Spot/Area 的纯映射（去重/标签/区县/来源）。
 * 与 tools/map_city_check.ts 同源；不碰 @kit。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import {
  DistrictAgg, MapSiteInput, addressMatchesCity, buildAreas, buildSpots, commonHours,
  dedupeSites, groupDistricts, isMapArea, tagsOfTypes, durationOf, typeLabelOf
} from '../../../main/ets/utils/MapCityMapper';
import { isMapCity, POPULAR_MAP_CITIES } from '../../../main/ets/common/constants/Cities';
import { Spot, SpotTag } from '../../../main/ets/model/Spot';
import { Area } from '../../../main/ets/model/Area';

function site(id: string, name: string, lat: number, lng: number, district: string,
  types: string[], rank: number, abstractText: string = ''): MapSiteInput {
  const s: MapSiteInput = {
    siteId: id, name: name, latitude: lat, longitude: lng, district: district,
    types: types, rank: rank, abstractText: abstractText
  };
  return s;
}

function rawSites(): MapSiteInput[] {
  return [
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
}

export default function mapCityMapperTest(): void {
  describe('MapCityMapper', () => {
    it('dedupe_keeps_first_and_drops_invalid', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const deduped: MapSiteInput[] = dedupeSites(rawSites());
      expect(deduped.length).assertEqual(4);
      expect(deduped[0].siteId).assertEqual('a');
      expect(deduped[1].siteId).assertEqual('c');
      expect(deduped[2].siteId).assertEqual('e');
      expect(deduped[3].siteId).assertEqual('f');
    });

    it('spots_carry_rank_provenance_and_no_fake_booking',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
        const spots: Spot[] = buildSpots(dedupeSites(rawSites()), '西安', '2026-10-31');
        expect(spots.length).assertEqual(4);
        expect(spots[0].id).assertEqual('mk:西安:a');
        expect(spots[0].popularity).assertEqual(100);
        expect(spots[0].booking.requiresBooking).assertFalse();
        expect(spots[0].provenance.source).assertEqual('MapKit 地点检索');
        expect(spots[0].tags.indexOf(SpotTag.CLASSIC) >= 0).assertTrue();
        expect(spots[2].brief.indexOf('唐代玄奘') >= 0).assertTrue();
        expect(spots[3].suggestedDuration).assertEqual(120);
        const hoursSite: MapSiteInput =
          site('h', '有开放时间', 34.2, 108.9, '雁塔区', ['MUSEUM'], 0);
        hoursSite.openingHoursTexts = ['星期一: 8:30 - 17:00', '星期二: 8:30 - 17:00'];
        const hoursSpots: Spot[] = buildSpots([hoursSite], '测试', '2026-10-31');
        expect(hoursSpots[0].openingHours === undefined ? '' : hoursSpots[0].openingHours)
          .assertEqual('8:30–17:00');
        expect(commonHours(['星期一: 8:30 - 17:00', '星期二: 8:30 - 17:00']))
          .assertEqual('8:30–17:00');
        expect(commonHours(['星期一: 0:00 - 23:59'])).assertEqual('全天开放');
        expect(commonHours(['星期一: 8:30 - 17:00', '星期二: 9:00 - 17:00'])).assertEqual('');
        expect(commonHours(['星期一: 休息'])).assertEqual('');
        expect(commonHours([])).assertEqual('');
        expect(commonHours(['星期一: 9:00 - 12:00, 13:00 - 17:00'])).assertEqual('');
      });

    it('type_mapping_and_defaults', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(tagsOfTypes(['ZOO']).indexOf(SpotTag.FAMILY) >= 0).assertTrue();
      expect(tagsOfTypes(['MUSEUM']).indexOf(SpotTag.CLASSIC) >= 0).assertTrue();
      expect(tagsOfTypes(['SOMETHING_ELSE']).length).assertEqual(0);
      expect(durationOf(['ZOO'])).assertEqual(180);
      expect(durationOf(['TOWER'])).assertEqual(45);
      expect(durationOf([])).assertEqual(90);
      expect(typeLabelOf(['ZOO'])).assertEqual('动物园');
    });

    it('areas_group_by_district_and_hotel_supply',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
        const deduped: MapSiteInput[] = dedupeSites(rawSites());
        const districts: DistrictAgg[] = groupDistricts(deduped);
        expect(districts.length).assertEqual(3);
        expect(districts[0].name).assertEqual('雁塔区');
        expect(districts[0].count).assertEqual(2);

        const hotel: Record<string, number> = {};
        hotel['雁塔区'] = 486;
        hotel['临潼区'] = 0;
        hotel['新城区'] = 120;
        const areas: Area[] = buildAreas(deduped, '西安', '2026-10-31', hotel);
        expect(areas.length).assertEqual(2);
        expect(areas[0].name).assertEqual('雁塔区');
        expect(areas[0].source).assertEqual('MapKit');
        expect(areas[0].priceTier).assertEqual('comfort');
        expect(areas[0].metroLines.length).assertEqual(0);
        expect(isMapArea(areas[0])).assertTrue();
        const all: Area[] = buildAreas(deduped, '西安', '2026-10-31', {});
        expect(all.length).assertEqual(3);

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
        expect(spreadAreas.length).assertEqual(2);
        expect(spreadAreas[0].name).assertEqual('中心区');
      });

    it('map_city_detection', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(isMapCity('西安')).assertTrue();
      expect(isMapCity('西安市')).assertTrue();
      expect(isMapCity('北京')).assertFalse();
      expect(isMapCity('京都')).assertFalse();
      expect(isMapCity('')).assertFalse();
      expect(POPULAR_MAP_CITIES.length).assertEqual(8);
      for (let i = 0; i < POPULAR_MAP_CITIES.length; i++) {
        expect(isMapCity(POPULAR_MAP_CITIES[i])).assertTrue();
      }
    });

    it('address_must_match_requested_city', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(addressMatchesCity('西安市', '陕西省', '雁塔区', '西安')).assertTrue();
      expect(addressMatchesCity('成都市', '四川省', '青羊区', '成都')).assertTrue();
      // 无效 cityId 实测返回全国结果：林州/岳阳不能算「不存在市」
      expect(addressMatchesCity('林州市', '安阳市', '林州市', '不存在')).assertFalse();
      expect(addressMatchesCity('岳阳市', '岳阳市', '岳阳楼区', '不存在')).assertFalse();
      expect(addressMatchesCity('上海市', '上海市', '浦东新区', '北京')).assertFalse();
      expect(addressMatchesCity('', '', '', '西安')).assertFalse();
    });
  });
}
