/**
 * 屏5「帮我选（离景点最近）」的算法回归：Geo 纯函数（大圆距离）。
 * 断言用教科书量（1° 纬度 ≈ 111.19km、60°N 的 1° 经度 ≈ 其余的一半），不依赖具体 POI 坐标。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { Geo, GeoPoint } from '../../../main/ets/utils/Geo';

function pt(lat: number, lng: number): GeoPoint {
  const p: GeoPoint = { latitude: lat, longitude: lng };
  return p;
}

export default function geoTest(): void {
  describe('Geo', () => {
    it('one_degree_of_latitude_is_about_111km', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const km: number = Geo.distanceKm(pt(0, 0), pt(1, 0));
      expect(Math.abs(km - 111.19) < 0.6).assertTrue();
    });

    it('longitude_shrinks_with_cos_of_latitude', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const equator: number = Geo.distanceKm(pt(0, 0), pt(0, 1));
      const sixty: number = Geo.distanceKm(pt(60, 0), pt(60, 1));
      expect(Math.abs(equator - 111.19) < 0.6).assertTrue();
      // cos60° = 0.5
      expect(Math.abs(sixty - equator / 2) < 0.8).assertTrue();
    });

    it('symmetric_and_zero_on_same_point', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const a: GeoPoint = pt(39.9163, 116.3972);
      const b: GeoPoint = pt(39.8777, 116.4107);
      expect(Math.abs(Geo.distanceKm(a, b) - Geo.distanceKm(b, a)) < 0.0001).assertTrue();
      expect(Geo.distanceKm(a, a)).assertEqual(0);
      // 故宫→天坛的直线距离量级应在 4~6km
      const km: number = Geo.distanceKm(a, b);
      expect(km > 4 && km < 6).assertTrue();
    });

    it('mean_and_argmin_guard_empty_inputs', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const targets: GeoPoint[] = [pt(39.9, 116.4), pt(39.88, 116.41)];
      expect(Geo.meanDistanceKm(pt(39.9, 116.4), [])).assertEqual(-1);
      expect(Geo.argminMean([], targets)).assertEqual(-1);
      expect(Geo.argminMean([pt(39.9, 116.4)], [])).assertEqual(-1);
      const areas: GeoPoint[] = [pt(40.05, 116.3), pt(39.905, 116.402), pt(31.2, 121.4)];
      expect(Geo.argminMean(areas, targets)).assertEqual(1);
      const two: number = Geo.meanDistanceKm(areas[1], targets);
      const three: number = Geo.meanDistanceKm(areas[2], targets);
      expect(two < three).assertTrue();
    });

    it('usable_rejects_zero_and_nan_but_keeps_overseas', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(Geo.usable(0, 0)).assertFalse();
      expect(Geo.usable(Number.NaN, 116.4)).assertFalse();
      // 海外城市要能算距离：MapStops.usable 是国内瓦片覆盖门禁，语义不同
      expect(Geo.usable(35.0116, 135.7681)).assertTrue();
    });

    // 以下为屏15 到站判定的口径（切片2 T1）：米制距离、300m 半径、文案分档
    it('distanceM_agrees_with_distanceKm', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const a: GeoPoint = pt(39.9, 116.4);
      const b: GeoPoint = pt(39.9018, 116.4);
      const m: number = Geo.distanceM(a, b);
      expect(m > 190 && m < 210).assertTrue();
      expect(Math.abs(m - Geo.distanceKm(a, b) * 1000) < 0.001).assertTrue();
      // 无坐标一侧返回 -1，不能当成 0m 的距离
      expect(Geo.distanceM(pt(0, 0), a)).assertEqual(-1);
    });

    it('arrival_radius_is_inclusive_300m', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(Geo.ARRIVAL_RADIUS_M).assertEqual(300);
      expect(Geo.arrived(0)).assertTrue();
      expect(Geo.arrived(300)).assertTrue();
      expect(Geo.arrived(300.1)).assertFalse();
      expect(Geo.arrived(-1)).assertFalse();
    });

    it('distance_text_switches_to_km_without_printing_1000m',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(Geo.distanceText(12.4)).assertEqual('12m');
      expect(Geo.distanceText(999.6)).assertEqual('1km');
      expect(Geo.distanceText(1234)).assertEqual('1.2km');
      expect(Geo.distanceText(-1)).assertEqual('');
    });
  });
}
