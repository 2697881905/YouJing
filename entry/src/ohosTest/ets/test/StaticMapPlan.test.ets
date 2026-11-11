/**
 * StaticMapPlan 回归（纯逻辑）：分享长图静态地图的取景与口径。
 * 重点钉住三条：单点档位、跨天不画动线、zoom 夹取（远不至于看不清街区、近不至于裁掉落点）。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { StaticMapPlan, StaticMapSpec } from '../../../main/ets/utils/StaticMapPlan';
import { MapStop } from '../../../main/ets/utils/MapStops';

function stop(index: number, group: number, lat: number, lng: number): MapStop {
  return {
    index: index, group: group, latitude: lat, longitude: lng,
    title: `站${index}`, subtitle: ''
  };
}

function specOf(stops: MapStop[]): StaticMapSpec | null {
  return StaticMapPlan.build(stops, 960, 600);
}

export default function staticMapPlanTest(): void {
  describe('StaticMapPlan', () => {
    it('empty_returns_null', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      expect(specOf([])).assertNull();
    });

    it('single_stop_street_zoom_no_path', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const s: StaticMapSpec | null = specOf([stop(1, 1, 39.9, 116.4)]);
      expect(s === null).assertFalse();
      if (s !== null) {
        expect(s.zoom).assertEqual(15);
        expect(s.withPath).assertFalse();
        expect(s.centerLatitude).assertEqual(39.9);
        expect(s.points.length).assertEqual(1);
      }
    });

    it('same_day_draws_path_center_is_midpoint', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const s: StaticMapSpec | null = specOf([
        stop(1, 1, 31.20, 121.40),
        stop(2, 1, 31.24, 121.50)
      ]);
      expect(s === null).assertFalse();
      if (s !== null) {
        expect(s.withPath).assertTrue();
        expect(s.centerLatitude).assertEqual(31.22);
        expect(s.centerLongitude).assertEqual(121.45);
        expect(s.zoom >= 4 && s.zoom <= 16).assertTrue();
      }
    });

    it('cross_day_never_draws_path', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // 跨天直连线会撒谎（Day1 末站直连 Day2 首站），这是 TripMapView.runs 的同一条教训
      const s: StaticMapSpec | null = specOf([
        stop(1, 1, 31.20, 121.40),
        stop(2, 2, 31.24, 121.50)
      ]);
      if (s !== null) {
        expect(s.withPath).assertFalse();
        expect(s.points.length).assertEqual(2);
      }
    });

    it('wider_span_zooms_out_monotonically', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const near: StaticMapSpec | null = specOf([
        stop(1, 1, 31.20, 121.40), stop(2, 1, 31.21, 121.41)
      ]);
      const far: StaticMapSpec | null = specOf([
        stop(1, 1, 31.20, 121.40), stop(2, 1, 31.40, 121.80)
      ]);
      if (near !== null && far !== null) {
        expect(far.zoom < near.zoom).assertTrue();
      }
    });

    it('tiny_span_clamped_and_integer', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // 两站相距百米：不夹取会算到 19 档，staticMap 上限 17 且要留街区感
      const s: StaticMapSpec | null = specOf([
        stop(1, 1, 31.2000, 121.4000), stop(2, 1, 31.2005, 121.4005)
      ]);
      if (s !== null) {
        expect(s.zoom).assertEqual(16);
        expect(Number.isInteger(s.zoom)).assertTrue();
      }
    });

    it('continental_span_clamped_low', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const s: StaticMapSpec | null = specOf([
        stop(1, 1, 39.90, 116.40), stop(2, 1, 23.15, 113.26)
      ]);
      if (s !== null) {
        expect(s.zoom >= 4).assertTrue();
        expect(s.zoom <= 8).assertTrue();
      }
    });
  });
}
