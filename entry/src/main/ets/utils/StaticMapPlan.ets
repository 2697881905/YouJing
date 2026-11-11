/**
 * 分享长图静态地图取景（纯逻辑，不引 @kit）：把 MapStops 收敛成 staticMap.getMapImage
 * 的取景参数。staticMap 只收整数 zoom 且没有 fitBounds，必须自己算——算错一档，
 * 13 站的上海就会有一半落点被裁出图外。
 *
 * 三条口径（别改回「看起来更简单」的写法）：
 * 1. 落点复用 MapStops.fromDays：交通节点与跑偏坐标已在源头滤掉，GCJ02 直喂 Map Kit；
 * 2. zoom 由经纬两个方向各自解出后取近的一档、四舍五入：staticMap 对小数向下取整，
 *    先 floor 会白丢近一档（12.92→12 时落点带只占图幅 36%）；留白系数 1.6 保证
 *    取整后最坏也只占图幅 ~88%，图钉不会贴边被裁；
 * 3. path 只在单天行程画：StaticMapPath 是单条连续线，跨天会把 Day1 末站直连
 *    Day2 首站（与 TripMapView 的 runs 同一条教训），多天只落图钉、不画误导线。
 */

import { MapStop, MapStops } from './MapStops';

export interface StaticMapSpec {
  centerLatitude: number;
  centerLongitude: number;
  /** 已夹取整数档位，直接喂 staticMap.zoom */
  zoom: number;
  /** 图钉坐标（与落点同序，供 markers 逐个转换） */
  points: MapStop[];
  /** 是否画动线（仅单天行程） */
  withPath: boolean;
}

const WORLD_PX: number = 256;
const ZOOM_MIN: number = 4;
const ZOOM_MAX: number = 16;
/** 取景留白：落点带目标占图幅 ~62%（1/1.6），四边各留一口气 */
const FRAME_PAD: number = 1.6;
/** 单落点档位：与 TripMapView.SINGLE_ZOOM 同一口径，街区级最近视角 */
const SINGLE_ZOOM: number = 15;

export class StaticMapPlan {
  static build(stops: MapStop[], widthPx: number, heightPx: number): StaticMapSpec | null {
    const box = MapStops.bounds(stops);
    if (box === null) {
      return null;
    }
    const midLat: number = (box.minLat + box.maxLat) / 2;
    const midLng: number = (box.minLng + box.maxLng) / 2;
    let zoom: number;
    if (stops.length === 1) {
      zoom = SINGLE_ZOOM;
    } else {
      // 墨卡托下纬度 1° 占的像素随纬度升高变多（×1/cosφ），不除 cos 高纬会裁边
      const spanLat: number = Math.max(0.01,
        (box.maxLat - box.minLat) * FRAME_PAD / Math.max(0.2, Math.cos(midLat * Math.PI / 180)));
      const spanLng: number = Math.max(0.01, (box.maxLng - box.minLng) * FRAME_PAD);
      const zoomLat: number = Math.log2(heightPx * 360 / (spanLat * WORLD_PX));
      const zoomLng: number = Math.log2(widthPx * 360 / (spanLng * WORLD_PX));
      zoom = Math.round(Math.min(zoomLat, zoomLng));
      zoom = Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, zoom));
    }
    // 动线仅单天：跨天连线会撒谎（见文件头口径 3）
    let withPath: boolean = stops.length >= 2;
    if (withPath) {
      for (const s of stops) {
        if (s.group !== stops[0].group) {
          withPath = false;
          break;
        }
      }
    }
    return {
      centerLatitude: midLat,
      centerLongitude: midLng,
      zoom: zoom,
      points: stops,
      withPath: withPath
    };
  }
}
