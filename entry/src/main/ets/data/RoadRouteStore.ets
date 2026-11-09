/**
 * 沿路点串（Map Kit `navi`）。
 *
 * 放 data/ 层与 `MapKitCityStore` 同款：`@kit.MapKit` 的调用不漏进组件和纯逻辑层。
 * 只负责「相邻两站 → 一段道路折线」，失败返回 null，由调用方回退成原来的直线，
 * 保证离线 / 鉴权失败 / 公交无方案时地图不断线。
 *
 * 坐标系：种子层已把 WGS84 转成 GCJ02（`TripMapView` 头注释第 2 条），
 * Map Kit 的 navi 同用 GCJ02，这里不再转换。
 */

import { navi, mapCommon } from '@kit.MapKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../common/logger/Logger';
import { RouteTravelMode, mergeRoutePoints, RoutePoint } from '../utils/RouteMode';

const TAG: string = 'Data.RoadRoute';
const TTL_MS: number = 30 * 60 * 1000;

interface CachedPoints {
  points: mapCommon.LatLng[];
  at: number;
}

export class RoadRouteStore {
  /** 键 = 起终点坐标 + 出行方式；一天的行程里同一段会被「全程 / Day N」反复请求 */
  private static cache: Map<string, CachedPoints> = new Map<string, CachedPoints>();

  static async segment(
    context: common.Context,
    from: mapCommon.LatLng,
    to: mapCommon.LatLng,
    mode: RouteTravelMode
  ): Promise<mapCommon.LatLng[] | null> {
    if (from.latitude === to.latitude && from.longitude === to.longitude) {
      return null;
    }
    const key: string = `${from.latitude.toFixed(5)},${from.longitude.toFixed(5)}>` +
      `${to.latitude.toFixed(5)},${to.longitude.toFixed(5)}:${mode}`;
    const hit: CachedPoints | undefined = RoadRouteStore.cache.get(key);
    if (hit !== undefined && Date.now() - hit.at < TTL_MS) {
      return hit.points;
    }
    try {
      const points: mapCommon.LatLng[] = await RoadRouteStore.fetch(context, from, to, mode);
      if (points.length < 2) {
        return null;
      }
      RoadRouteStore.cache.set(key, { points: points, at: Date.now() });
      return points;
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      // 1002600002 连不上服务 / 1002600003 鉴权 / 1002600004 权限未开通：
      // 三种都不该把地图打成空线，交给调用方回退直线
      Logger.warn(TAG, `算路失败 code=${e.code} msg=${e.message} mode=${mode}`);
      return null;
    }
  }

  private static async fetch(
    context: common.Context,
    from: mapCommon.LatLng,
    to: mapCommon.LatLng,
    mode: RouteTravelMode
  ): Promise<mapCommon.LatLng[]> {
    if (mode === RouteTravelMode.TRANSIT) {
      return RoadRouteStore.transit(context, from, to);
    }
    let result: navi.RouteResult;
    if (mode === RouteTravelMode.DRIVING) {
      const params: navi.DrivingRouteParams = {
        origins: [from], destination: to, language: 'zh_CN'
      };
      result = await navi.getDrivingRoutes(params);
    } else {
      const params: navi.RouteParams = {
        origins: [from], destination: to, language: 'zh_CN'
      };
      result = await navi.getWalkingRoutes(params);
    }
    if (result.routes.length === 0) {
      return [];
    }
    return result.routes[0].overviewPolyline ?? [];
  }

  /** 公交结果按 sections 分步行段与乘车段，各自带 polyline，要顺序拼起来 */
  private static async transit(
    context: common.Context,
    from: mapCommon.LatLng,
    to: mapCommon.LatLng
  ): Promise<mapCommon.LatLng[]> {
    const params: navi.TransitRouteParams = { origin: from, destination: to };
    const result: navi.TransitRouteResult = await navi.getTransitRoutes(context, params);
    const routes: navi.TransitRoute[] | undefined = result.routes;
    if (routes === undefined || routes.length === 0) {
      return [];
    }
    const segments: RoutePoint[][] = [];
    for (const section of routes[0].sections) {
      const walk = section.pedestrianSection;
      if (walk !== undefined && walk.polyline !== undefined) {
        segments.push(walk.polyline);
      }
      const ride = section.transitSection;
      if (ride !== undefined && ride.polyline !== undefined) {
        segments.push(ride.polyline);
      }
    }
    const merged: RoutePoint[] = mergeRoutePoints(segments);
    const out: mapCommon.LatLng[] = [];
    for (const p of merged) {
      out.push({ latitude: p.latitude, longitude: p.longitude });
    }
    return out;
  }
}
