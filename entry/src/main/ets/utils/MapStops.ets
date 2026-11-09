/**
 * 地图落点装配（纯逻辑，不引 @kit）：把行程/景点/片区三类数据收敛成同一份 MapStop，
 * Map Kit 的调用只留在组件里，这里可离线断言。
 *
 * usable() 是中国大陆范围粗筛：AI 回写的 activity 坐标是模型自己填的（TripSchema 只校验
 * 「是不是 number」），0/0 与跑偏值直接丢弃，否则整条动线会被一根线拽到几内亚湾。
 */

import { Activity, ActivityCategory, TripDay } from '../model/Trip';
import { Area } from '../model/Area';
import { Spot } from '../model/Spot';

export interface MapStop {
  /** 动线序号，从 1 开始且连续 */
  index: number;
  /** 所属分组（行程按天，0 = 单组）；跨组不连线，否则会把 Day1 末站直连到 Day2 首站 */
  group: number;
  latitude: number;
  longitude: number;
  title: string;
  subtitle: string;
  /** 到达本节点前的出行方式自由文案（Activity.transport.mode）；片区/景点落点没有，默认步行 */
  mode?: string;
}

export interface MapBounds {
  minLat: number;
  maxLat: number;
  minLng: number;
  maxLng: number;
}

export class MapStops {
  static usable(latitude: number, longitude: number): boolean {
    return latitude >= 18 && latitude <= 54 && longitude >= 73 && longitude <= 135;
  }

  /** 一个 activity 会不会成为地图落点：交通节点不上图，坐标不可用的也不上 */
  static eligible(act: Activity): boolean {
    return act.category !== ActivityCategory.TRANSPORT && MapStops.usable(act.latitude, act.longitude);
  }

  /**
   * 反查：MapStop.index（1 起）→ day.activities 下标，找不到 -1。
   * 屏8 点地图落点要把对应行带回视野，而 index 是「滤掉不可上图节点后」的序号，
   * 直接当数组下标用会错行——这里与 fromDay 共用 eligible()，两处不会再漂。
   */
  static activityIndex(day: TripDay, index: number): number {
    if (index < 1) {
      return -1;
    }
    let seen: number = 0;
    for (let i = 0; i < day.activities.length; i++) {
      if (!MapStops.eligible(day.activities[i])) {
        continue;
      }
      seen += 1;
      if (seen === index) {
        return i;
      }
    }
    return -1;
  }

  static fromDay(day: TripDay): MapStop[] {
    const out: MapStop[] = [];
    for (const act of day.activities) {
      if (!MapStops.eligible(act)) {
        continue;
      }
      out.push({
        index: out.length + 1,
        group: day.dayIndex,
        latitude: act.latitude,
        longitude: act.longitude,
        title: act.title.length > 0 ? act.title : act.location,
        subtitle: `${act.time}–${act.endTime}`,
        mode: act.transport !== undefined ? act.transport.mode : ''
      });
    }
    return out;
  }

  /** 全程：序号跨天连续，group 保留天号，供分天连线用 */
  static fromDays(days: TripDay[]): MapStop[] {
    const out: MapStop[] = [];
    for (const day of days) {
      for (const stop of MapStops.fromDay(day)) {
        out.push({
          index: out.length + 1,
          group: stop.group,
          latitude: stop.latitude,
          longitude: stop.longitude,
          title: stop.title,
          subtitle: stop.subtitle,
          mode: stop.mode ?? ''
        });
      }
    }
    return out;
  }

  static fromSpots(spots: Spot[]): MapStop[] {
    const out: MapStop[] = [];
    for (const spot of spots) {
      if (!MapStops.usable(spot.latitude, spot.longitude)) {
        continue;
      }
      out.push({
        index: out.length + 1,
        group: 0,
        latitude: spot.latitude,
        longitude: spot.longitude,
        title: spot.name,
        subtitle: spot.district
      });
    }
    return out;
  }

  static fromAreas(areas: Area[]): MapStop[] {
    const out: MapStop[] = [];
    for (const area of areas) {
      if (!MapStops.usable(area.latitude, area.longitude)) {
        continue;
      }
      out.push({
        index: out.length + 1,
        group: 0,
        latitude: area.latitude,
        longitude: area.longitude,
        title: area.name,
        subtitle: area.anchorStations.length > 0 ? `近 ${area.anchorStations[0]}` : area.group
      });
    }
    return out;
  }

  static bounds(stops: MapStop[]): MapBounds | null {
    if (stops.length === 0) {
      return null;
    }
    const box: MapBounds = {
      minLat: stops[0].latitude, maxLat: stops[0].latitude,
      minLng: stops[0].longitude, maxLng: stops[0].longitude
    };
    for (const s of stops) {
      box.minLat = Math.min(box.minLat, s.latitude);
      box.maxLat = Math.max(box.maxLat, s.latitude);
      box.minLng = Math.min(box.minLng, s.longitude);
      box.maxLng = Math.max(box.maxLng, s.longitude);
    }
    return box;
  }

  /** 按 group 切成连续段：段内才连线，段之间不画线 */
  static runs(stops: MapStop[]): MapStop[][] {
    const out: MapStop[][] = [];
    let current: MapStop[] = [];
    for (const s of stops) {
      if (current.length > 0 && current[0].group !== s.group) {
        out.push(current);
        current = [];
      }
      current.push(s);
    }
    if (current.length > 0) {
      out.push(current);
    }
    return out;
  }

  /** 「全程 / Day N」切换条标签：页面只负责渲染，标签口径收在这里，离线可断言 */
  static dayLabels(days: TripDay[]): string[] {
    const out: string[] = ['全程'];
    for (const day of days) {
      out.push(`Day ${day.dayIndex}`);
    }
    return out;
  }

  /** 传给子组件的标量键：内容没变就不必重铺 overlay */
  static signature(stops: MapStop[]): string {
    return stops.map((s: MapStop): string => `${s.index}:${s.latitude.toFixed(4)},${s.longitude.toFixed(4)}`)
      .join('|');
  }
}
