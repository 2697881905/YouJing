/**
 * 动线算路口径（纯逻辑，不引 @kit）。
 *
 * 行程里的 `Activity.transport.mode` 是自由文案（「地铁 2 号线」「打车」「步行」…），
 * 由规则引擎或云端生成；不能把裸字符串漏给算路层，否则换一种说法就整段掉回直线。
 * 这里收敛成三档，data/RoadRouteStore 再映射到 Map Kit navi 的三个接口。
 */

export enum RouteTravelMode {
  WALKING = 'walking',
  DRIVING = 'driving',
  TRANSIT = 'transit'
}

/** 结构对齐 mapCommon.LatLng，但不依赖 @kit —— 离线用例跑得动 */
export interface RoutePoint {
  latitude: number;
  longitude: number;
}

const WALK_WORDS: string[] = ['步行', '徒步', '走路'];
const DRIVE_WORDS: string[] = ['打车', '出租', '自驾', '驾车', '开车', '网约车', '专车'];
const TRANSIT_WORDS: string[] = ['地铁', '公交', '巴士', '轻轨', '有轨', '高铁', '火车', '城际', '轮渡', '索道'];

/**
 * 顺序有讲究：先判公共交通再判打车，因为「地铁口打车」这类混写里
 * 主段仍是轨道；步行词最后判，未识别的一律回退步行（最保守、覆盖市内短途）。
 */
export function routeModeOf(mode: string): RouteTravelMode {
  const text: string = (mode ?? '').trim();
  if (text.length === 0) {
    return RouteTravelMode.WALKING;
  }
  for (const word of TRANSIT_WORDS) {
    if (text.indexOf(word) >= 0) {
      return RouteTravelMode.TRANSIT;
    }
  }
  for (const word of DRIVE_WORDS) {
    if (text.indexOf(word) >= 0) {
      return RouteTravelMode.DRIVING;
    }
  }
  for (const word of WALK_WORDS) {
    if (text.indexOf(word) >= 0) {
      return RouteTravelMode.WALKING;
    }
  }
  return RouteTravelMode.WALKING;
}

/**
 * 把逐段点串接成一条。相邻两段共用端点，不去重会让 MapPolyline 出现零长线段；
 * 段内自身的重复点也一并去掉（公交 sections 拼接时常见）。
 */
export function mergeRoutePoints(segments: RoutePoint[][]): RoutePoint[] {
  const out: RoutePoint[] = [];
  for (const seg of segments) {
    for (const p of seg) {
      const last: RoutePoint | undefined = out.length > 0 ? out[out.length - 1] : undefined;
      if (last !== undefined && last.latitude === p.latitude && last.longitude === p.longitude) {
        continue;
      }
      out.push({ latitude: p.latitude, longitude: p.longitude });
    }
  }
  return out;
}
