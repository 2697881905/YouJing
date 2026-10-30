/**
 * 距离计算（纯函数，不碰 @kit，可离线断言）。
 *
 * 只有大圆距离：本项目不接路径规划，所以「通勤最短」在本App里能算的最近似
 * 就是到所选景点的平均直线距离，界面文案按这个口径写，不谎报成导航里程。
 *
 * 同一份距离也给屏15 的到站判定用。到站半径取 300m：2026-10-27 真机探针室内
 * acc≈237m，100/200m 半径在室内只剩噪声，300m 还能分开「已在景区里」与「还在路上」；
 * 定位精度只显示、不参与判定——让精度参与会把一次室内漂移算成「已到站」。
 */

export interface GeoPoint {
  latitude: number;
  longitude: number;
}

const EARTH_RADIUS_KM: number = 6371;

function toRad(deg: number): number {
  return deg * Math.PI / 180;
}

export class Geo {
  /** 有没有可用坐标（0,0 与 NaN 算没坐标）。与 MapStops.usable 不同：那条是国内瓦片
   *  覆盖范围的门禁，这里只问「这点能不能算距离」，海外城市要能过。 */
  static usable(lat: number, lng: number): boolean {
    return !Number.isNaN(lat) && !Number.isNaN(lng) &&
      Math.abs(lat) > 0.0001 && Math.abs(lng) > 0.0001;
  }

  /** 大圆距离，公里 */
  static distanceKm(a: GeoPoint, b: GeoPoint): number {
    const dLat: number = toRad(b.latitude - a.latitude);
    const dLng: number = toRad(b.longitude - a.longitude);
    const la1: number = toRad(a.latitude);
    const la2: number = toRad(b.latitude);
    const h: number = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(la1) * Math.cos(la2) * Math.sin(dLng / 2) * Math.sin(dLng / 2);
    return 2 * EARTH_RADIUS_KM * Math.asin(Math.min(1, Math.sqrt(h)));
  }

  /** 到一组目标点的平均距离；targets 为空返回 -1，调用方据此走兜底 */
  static meanDistanceKm(from: GeoPoint, targets: GeoPoint[]): number {
    if (targets.length === 0) {
      return -1;
    }
    let sum: number = 0;
    for (const t of targets) {
      sum += Geo.distanceKm(from, t);
    }
    return sum / targets.length;
  }

  /** 到站半径（米） */
  static readonly ARRIVAL_RADIUS_M: number = 300;

  /** 两点距离（米）；任一点不可用返回 -1 */
  static distanceM(a: GeoPoint, b: GeoPoint): number {
    if (!Geo.usable(a.latitude, a.longitude) || !Geo.usable(b.latitude, b.longitude)) {
      return -1;
    }
    return Geo.distanceKm(a, b) * 1000;
  }

  /** 距离 ≤ 300m 即到站；不可用距离（-1）不算到站 */
  static arrived(distanceM: number): boolean {
    return Number.isFinite(distanceM) && distanceM >= 0 && distanceM <= Geo.ARRIVAL_RADIUS_M;
  }

  /** 距离文案：<1km 取整到米，≥1km 保留一位小数；不可用距离返回空串（界面不显示） */
  static distanceText(distanceM: number): string {
    if (!Number.isFinite(distanceM) || distanceM < 0) {
      return '';
    }
    // 先取整再分档：999.6m 约成 1000 后要走公里档，避免出现「1000m」
    const meters: number = Math.round(distanceM);
    if (meters < 1000) {
      return `${meters}m`;
    }
    return `${Math.round(meters / 100) / 10}km`;
  }

  /** 平均距离最小的下标；points 或 targets 不可用时返回 -1 */
  static argminMean(points: GeoPoint[], targets: GeoPoint[]): number {
    if (points.length === 0 || targets.length === 0) {
      return -1;
    }
    let best: number = -1;
    let bestKm: number = Number.MAX_VALUE;
    for (let i = 0; i < points.length; i++) {
      const mean: number = Geo.meanDistanceKm(points[i], targets);
      if (mean < bestKm) {
        bestKm = mean;
        best = i;
      }
    }
    return best;
  }
}
