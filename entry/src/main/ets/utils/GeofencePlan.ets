/**
 * 到站围栏的纯规划逻辑（不引 @kit，可离线断言）。
 *
 * 只回答「今天该给哪几站注册围栏」：已结束的站不注册、没有可用坐标的站不注册、
 * 交通/住宿/空闲占位不注册；半径与上限是常量，方便和 P5 的审核口径对齐。
 */

import { ActivityCategory, TripDay } from '../model/Trip';
import { DateUtils } from './DateUtils';

export interface FenceSpec {
  activityId: string;
  title: string;
  latitude: number;
  longitude: number;
  radiusM: number;
}

export class GeofencePlan {
  /** 与 Geo.ARRIVE_RADIUS_M 同口径：300m */
  static readonly DEFAULT_RADIUS_M: number = 300;
  /** 系统围栏数量有限，取当日最靠前的 10 站即可覆盖行中场景 */
  static readonly MAX_FENCES: number = 10;

  static of(day: TripDay, nowMin: number, radiusM: number = GeofencePlan.DEFAULT_RADIUS_M): FenceSpec[] {
    const out: FenceSpec[] = [];
    const radius: number = radiusM > 0 ? radiusM : GeofencePlan.DEFAULT_RADIUS_M;
    for (const a of day.activities) {
      if (a.category === ActivityCategory.TRANSPORT || a.category === ActivityCategory.HOTEL ||
        a.category === ActivityCategory.REST) {
        continue;
      }
      const start: number = DateUtils.minutesOf(a.time);
      const end: number = DateUtils.minutesOf(a.endTime);
      if (start < 0) {
        continue;
      }
      // 已经结束的站不再提醒；正在进行的站保留（用户可能刚到）
      if (end > 0 && end < nowMin) {
        continue;
      }
      if (!GeofencePlan.usable(a.latitude, a.longitude)) {
        continue;
      }
      out.push({
        activityId: a.id,
        title: a.title,
        latitude: a.latitude,
        longitude: a.longitude,
        radiusM: radius
      });
      if (out.length >= GeofencePlan.MAX_FENCES) {
        break;
      }
    }
    return out;
  }

  private static usable(lat: number, lng: number): boolean {
    return Number.isFinite(lat) && Number.isFinite(lng) &&
      Math.abs(lat) > 0.0001 && Math.abs(lng) > 0.0001;
  }
}
