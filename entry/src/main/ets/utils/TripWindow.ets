/**
 * 「今天是不是在这趟行程里」的唯一实现。
 *
 * 之前这一句在两个页面各内联一份（`YoujingStartPage` 给最近行程打「旅行中」徽章、
 * `TripsPage` 算三态与进度），dock 五格化之后「地图」根页也要按这个口径挑行程，
 * 就是第三份了 —— 收在这里。
 *
 * 为什么不能用 `DateUtils.spanDays` 的差值判：它含首尾且下限为 1，
 * 「还没出发」的未来行程会被算成旅行中（TripsPage 原注释记过这条，一并搬过来）。
 */

import { DateUtils } from './DateUtils';

export class TripWindow {
  /** 给定"今天"判断行程区间是否覆盖它。ISO 串可直接比大小 */
  static isActiveOn(startDate: string, endDate: string, today: string): boolean {
    return today >= startDate && today <= endDate;
  }

  /** 用系统当天判断 */
  static isActive(startDate: string, endDate: string): boolean {
    return TripWindow.isActiveOn(startDate, endDate, DateUtils.todayIso());
  }
}
