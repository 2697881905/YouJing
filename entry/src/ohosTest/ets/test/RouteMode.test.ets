/**
 * 沿路动线的口径回归（纯逻辑，离线可跑）。
 *
 * 两件事必须离线钉住：① 自由文案 → 算路档位的映射不能因换一种说法就掉回直线；
 * ② 多段点串拼接不能留零长线段。Map Kit navi 的调用本身需要真机，不在这里验。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { routeModeOf, mergeRoutePoints, RouteTravelMode, RoutePoint } from '../../../main/ets/utils/RouteMode';
import { MapStops } from '../../../main/ets/utils/MapStops';
import { Activity, ActivityCategory, ActivityStatus, IntensityLevel, TripDay } from '../../../main/ets/model/Trip';

function activity(mode: string): Activity {
  return {
    id: 'a1', time: '09:00', endTime: '10:00', title: '故宫博物院', location: '故宫博物院',
    address: '', longitude: 116.397, latitude: 39.918,
    status: ActivityStatus.NO_NEED, category: ActivityCategory.SIGHT,
    transport: { mode: mode, duration: 20, detail: '' }
  };
}

export default function routeModeTest(): void {
  describe('RouteMode', () => {
    it('mode_words_map_to_three_planners', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(routeModeOf('步行')).assertEqual(RouteTravelMode.WALKING);
      expect(routeModeOf('徒步 15 分钟')).assertEqual(RouteTravelMode.WALKING);
      expect(routeModeOf('打车')).assertEqual(RouteTravelMode.DRIVING);
      expect(routeModeOf('出租/网约车')).assertEqual(RouteTravelMode.DRIVING);
      expect(routeModeOf('地铁 2 号线')).assertEqual(RouteTravelMode.TRANSIT);
      expect(routeModeOf('公交 22 分钟 · 2 站')).assertEqual(RouteTravelMode.TRANSIT);
    });

    it('unknown_or_empty_mode_falls_back_to_walking', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(routeModeOf('')).assertEqual(RouteTravelMode.WALKING);
      expect(routeModeOf('   ')).assertEqual(RouteTravelMode.WALKING);
      expect(routeModeOf('骑马')).assertEqual(RouteTravelMode.WALKING);
      // 混写以主段为准：先判轨道，别被「地铁口打车」带去驾车
      expect(routeModeOf('地铁口打车')).assertEqual(RouteTravelMode.TRANSIT);
    });

    it('merge_drops_shared_endpoints_and_inner_duplicates', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const a: RoutePoint = { latitude: 39.9, longitude: 116.3 };
      const b: RoutePoint = { latitude: 39.91, longitude: 116.31 };
      const c: RoutePoint = { latitude: 39.92, longitude: 116.32 };
      const merged: RoutePoint[] = mergeRoutePoints([[a, b, b], [b, c], []]);
      expect(merged.length).assertEqual(3);
      expect(merged[0].latitude).assertEqual(a.latitude);
      expect(merged[1].latitude).assertEqual(b.latitude);
      expect(merged[2].latitude).assertEqual(c.latitude);
      expect(mergeRoutePoints([]).length).assertEqual(0);
    });

    it('fromDay_carries_transport_mode_into_stop', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const d: TripDay = {
        dayIndex: 1, date: '2026-06-11', theme: '', intensity: IntensityLevel.MEDIUM,
        dailyCost: 0, activities: [activity('地铁 2 号线')], meals: []
      };
      const stops = MapStops.fromDay(d);
      expect(stops.length).assertEqual(1);
      expect(stops[0].mode).assertEqual('地铁 2 号线');
      expect(routeModeOf(stops[0].mode ?? '')).assertEqual(RouteTravelMode.TRANSIT);
    });
  });
}
