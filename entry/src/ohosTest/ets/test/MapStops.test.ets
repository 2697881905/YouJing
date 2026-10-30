/**
 * MapStops 回归（纯逻辑）：落点装配、usable 门禁、bounds / runs / signature。
 * 这是「AI 回写坐标跑偏会把动线拽到几内亚湾」的唯一防线，必须离线可断言。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { MapStops, MapStop } from '../../../main/ets/utils/MapStops';
import { Activity, ActivityCategory, ActivityStatus, IntensityLevel, Meal, MealType, TripDay } from '../../../main/ets/model/Trip';
import { Area, AreaGroup, AreaPriceTier } from '../../../main/ets/model/Area';
import { Spot, SpotTag } from '../../../main/ets/model/Spot';

function act(id: string, time: string, title: string, category: ActivityCategory,
  lat: number, lng: number): Activity {
  return {
    id: id, time: time, endTime: '10:00', title: title, location: title,
    address: '', longitude: lng, latitude: lat,
    status: ActivityStatus.NO_NEED, category: category
  };
}

function day(dayIndex: number, activities: Activity[]): TripDay {
  const meals: Meal[] = [{ type: MealType.LUNCH, name: '午餐', location: '附近', estimatedCost: 100 }];
  return {
    dayIndex: dayIndex, date: '2026-06-11', theme: '主题', intensity: IntensityLevel.MEDIUM,
    dailyCost: 0, activities: activities, meals: meals
  };
}

function spot(id: string, lat: number, lng: number): Spot {
  return {
    id: id, name: id, city: '北京', tags: [SpotTag.CLASSIC], brief: '',
    suggestedDuration: 60, popularity: 50, nearbySpotIds: [],
    longitude: lng, latitude: lat, district: '东城区', nearestMetro: '',
    booking: { requiresBooking: false },
    provenance: { source: 'test', updatedAt: '2026-10-25' }
  };
}

function area(id: string, lat: number, lng: number): Area {
  return {
    id: id, name: id, city: '北京', longitude: lng, latitude: lat, description: '',
    anchorStations: ['甲站'], metroLines: ['1号线'], airportMinutes: 40,
    trainStationMinutes: 20, commerceTags: [], diningDensity: '高',
    suitableCrowds: [], priceTier: AreaPriceTier.COMFORT, group: AreaGroup.CORE,
    source: 'test', updatedAt: '2026-10-25'
  };
}

export default function mapStopsTest(): void {
  describe('MapStops', () => {
    it('usable_gate', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      expect(MapStops.usable(39.9, 116.4)).assertTrue();
      // 0/0 与跑偏值必须被滤掉：模型自填坐标不受 Schema 约束
      expect(MapStops.usable(0, 0)).assertFalse();
      expect(MapStops.usable(39.9, 0)).assertFalse();
      expect(MapStops.usable(80, 116)).assertFalse();
      expect(MapStops.usable(39.9, 200)).assertFalse();
    });

    it('fromDay_skips_transport_and_unusable', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const d: TripDay = day(1, [
        act('a', '09:00', '故宫', ActivityCategory.SIGHT, 39.9, 116.4),
        act('t', '10:00', '通勤', ActivityCategory.TRANSPORT, 39.91, 116.41),
        act('b', '11:00', '跑偏站', ActivityCategory.SIGHT, 0, 0)
      ]);
      const stops: MapStop[] = MapStops.fromDay(d);
      expect(stops.length).assertEqual(1);
      expect(stops[0].index).assertEqual(1);
      expect(stops[0].group).assertEqual(1);
      expect(stops[0].title).assertEqual('故宫');
      expect(stops[0].subtitle).assertEqual('09:00–10:00');
    });

    it('fromDays_continuous_index_keeps_group', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const stops: MapStop[] = MapStops.fromDays([
        day(1, [act('a', '09:00', 'A', ActivityCategory.SIGHT, 39.9, 116.4)]),
        day(2, [act('b', '09:00', 'B', ActivityCategory.SIGHT, 39.95, 116.45)])
      ]);
      expect(stops.length).assertEqual(2);
      expect(stops[0].index).assertEqual(1);
      expect(stops[1].index).assertEqual(2);
      expect(stops[0].group).assertEqual(1);
      expect(stops[1].group).assertEqual(2);
    });

    it('fromSpots_and_fromAreas', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const spots: MapStop[] = MapStops.fromSpots([spot('s1', 39.9, 116.4), spot('s2', 0, 0)]);
      expect(spots.length).assertEqual(1);
      expect(spots[0].group).assertEqual(0);
      const areas: MapStop[] = MapStops.fromAreas([area('a1', 39.9, 116.4), area('a2', 0, 0)]);
      expect(areas.length).assertEqual(1);
      expect(areas[0].subtitle).assertEqual('近 甲站');
    });

    it('bounds_and_runs', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const stops: MapStop[] = MapStops.fromDays([
        day(1, [act('a', '09:00', 'A', ActivityCategory.SIGHT, 39.9, 116.4),
          act('b', '10:00', 'B', ActivityCategory.SIGHT, 40.0, 116.5)]),
        day(2, [act('c', '09:00', 'C', ActivityCategory.SIGHT, 39.8, 116.3)])
      ]);
      const box = MapStops.bounds(stops);
      expect(box === null ? 0 : box.minLat).assertEqual(39.8);
      expect(box === null ? 0 : box.maxLng).assertEqual(116.5);
      expect(MapStops.bounds([])).assertNull();
      const runs: MapStop[][] = MapStops.runs(stops);
      expect(runs.length).assertEqual(2);
      expect(runs[0].length).assertEqual(2);
      expect(runs[1].length).assertEqual(1);
    });

    it('signature_changes_with_content', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const a: MapStop[] = MapStops.fromSpots([spot('s1', 39.9, 116.4)]);
      const b: MapStop[] = MapStops.fromSpots([spot('s1', 39.9, 116.41)]);
      expect(MapStops.signature(a) === MapStops.signature(b)).assertFalse();
      expect(MapStops.signature(a)).assertEqual('1:39.9000,116.4000');
    });

    it('activityIndex_matches_fromDay_filter', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // 屏8 点地图落点要滚到「第几行」：序号是滤掉交通节点与坏坐标后的序号，
      // 直接当 activities 下标用会错行，所以反查必须与 fromDay 的过滤逐字一致
      const d: TripDay = day(1, [
        act('t', '08:00', '去程', ActivityCategory.TRANSPORT, 39.9, 116.4),
        act('a', '09:00', 'A', ActivityCategory.SIGHT, 39.9, 116.4),
        act('bad', '10:00', 'B', ActivityCategory.SIGHT, 0, 0),
        act('c', '11:00', 'C', ActivityCategory.FOOD, 39.9, 116.5)
      ]);
      expect(MapStops.fromDay(d).length).assertEqual(2);
      expect(MapStops.activityIndex(d, 1)).assertEqual(1);
      expect(MapStops.activityIndex(d, 2)).assertEqual(3);
      expect(MapStops.activityIndex(d, 0)).assertEqual(-1);
      expect(MapStops.activityIndex(d, 3)).assertEqual(-1);
    });
  });
}
