/**
 * 行中被动信号（切片 3 T2）：只产出「一条建议」，不直接改行程。
 *
 * 三个信号（优先级从高到低）：
 *   偏离：有前台定位、距当前站 >1km、已过开始 10 分钟、当前站未打卡 → 跳过当前站
 *   落后：最后一次打卡之后的第一个未打卡站已晚 ≥30 分钟 → 顺延（无可顺延站时改跳过）
 *   有雨：前方第一处可跳过的室外站在其时段内降水概率 ≥60% → 跳过该站
 *
 * 全是确定性规则：判断只需要时间/距离/降水三个标量，交给 LLM 既贵又慢，
 * 还会把「建议」变成不可复现的输出。
 */

import { DurationCn } from '../utils/DurationCn';
import { Activity, ActivityCategory, TripDay } from '../model/Trip';
import { WeatherDay } from '../model/Weather';
import { DateUtils } from '../utils/DateUtils';
import { Geo, GeoPoint } from '../utils/Geo';
import { SkipPlanner } from './SkipPlanner';
import { WeatherAdvisor } from './WeatherAdvisor';

export enum SignalKind {
  OFF_ROUTE = 'off_route',
  BEHIND = 'behind',
  RAIN = 'rain'
}

export enum SignalAction {
  SKIP = 'skip',
  SHIFT = 'shift'
}

export interface SignalContext {
  isToday: boolean;
  /** 当日分钟数 */
  nowMin: number;
  /** 前台定位；无权限/未启动为 null */
  fix: GeoPoint | null;
  /** 当日已打卡的活动/餐次 key；餐次 key 在这里不会命中活动 */
  checkedIds: string[];
  /**
   * 屏15 判定好的「当前节点」id（`utils/NodeOwe` 的答复，见 OnTripPage.reload）。
   * 空串 = 这一屏没有当前节点。
   *
   * 本模块**不再自己扫"现在是哪一站"**。之前它内部有一套（落后信号取
   * 「最后一个已打卡之后第一个没打卡的站」），而 hero 与「完成打卡」取另一套
   * （「时刻已到的最后一站」），用户一落后两者就分叉 —— 同一屏两颗主按钮
   * 瞄着两个不同的站。现在判定只有一处，信号跟着它走。
   */
  currentKey: string;
  /** 今日天气；取不到为 null */
  weather: WeatherDay | null;
}

export interface TripSuggestion {
  /** 稳定 key：同类去重/忽略用 */
  key: string;
  kind: SignalKind;
  title: string;
  detail: string;
  action: SignalAction;
  /** 跳过/顺延的目标活动 id */
  targetId: string;
  /** 顺延分钟数；SKIP 为 0 */
  deltaMin: number;
  actionLabel: string;
}

const OFF_ROUTE_MIN_M: number = 1000;
const OFF_ROUTE_GRACE_MIN: number = 10;
const BEHIND_MIN: number = 30;
const SHIFT_MIN: number = 15;
const SHIFT_MAX: number = 120;
const DAY_END: number = 1439;
const DEFAULT_DWELL_MIN: number = 60;

export class TripSignals {
  static readonly OFF_ROUTE_MIN_M: number = OFF_ROUTE_MIN_M;
  static readonly OFF_ROUTE_GRACE_MIN: number = OFF_ROUTE_GRACE_MIN;
  static readonly BEHIND_MIN: number = BEHIND_MIN;
  static readonly SHIFT_MIN: number = SHIFT_MIN;
  static readonly SHIFT_MAX: number = SHIFT_MAX;

  static suggest(day: TripDay, ctx: SignalContext): TripSuggestion | null {
    if (!ctx.isToday || ctx.nowMin < 0) {
      return null;
    }
    const stops: Activity[] = TripSignals.timeline(day);
    if (stops.length === 0) {
      return null;
    }
    // 当前节点由屏15 一处判定后传进来。找不到就不出「偏离」与「落后」两条：
    // 宁可这一屏安静，也不能建议条说的是 A 站、hero 和「完成打卡」瞄的是 B 站。
    // （餐次与无时刻项不在 timeline 口径里，所以当前节点是餐次时这里天然不命中。）
    const current: Activity | null = TripSignals.findByKey(stops, ctx.currentKey);
    if (current === null) {
      return TripSignals.rain(stops, ctx);
    }

    const offRoute: TripSuggestion | null = TripSignals.offRoute(current, ctx);
    if (offRoute !== null) {
      return offRoute;
    }

    if (!TripSignals.checked(current, ctx.checkedIds)) {
      const lag: number = ctx.nowMin - TripSignals.startOf(current);
      if (lag >= BEHIND_MIN) {
        const behind: TripSuggestion | null = TripSignals.behind(current, lag, stops, ctx);
        if (behind !== null) {
          return behind;
        }
      }
    }

    return TripSignals.rain(stops, ctx);
  }

  private static findByKey(stops: Activity[], key: string): Activity | null {
    if (key.length === 0) {
      return null;
    }
    for (const a of stops) {
      if (a.id === key) {
        return a;
      }
    }
    return null;
  }

  /** 参与信号判定的一天：剔除交通/住宿/跳过占位/无时刻项，按开始时间排序 */
  private static timeline(day: TripDay): Activity[] {
    const list: Activity[] = [];
    for (const a of day.activities) {
      if (a.category === ActivityCategory.TRANSPORT || a.category === ActivityCategory.HOTEL) {
        continue;
      }
      if (SkipPlanner.isSkippedMarker(a)) {
        continue;
      }
      if (DateUtils.minutesOf(a.time) < 0) {
        continue;
      }
      list.push(a);
    }
    list.sort((x: Activity, y: Activity): number => TripSignals.startOf(x) - TripSignals.startOf(y));
    return list;
  }

  private static offRoute(current: Activity, ctx: SignalContext): TripSuggestion | null {
    if (TripSignals.checked(current, ctx.checkedIds)) {
      return null;
    }
    if (!SkipPlanner.isSkippable(current.category, current.status)) {
      return null;
    }
    if (ctx.fix === null) {
      return null;
    }
    const start: number = TripSignals.startOf(current);
    if (ctx.nowMin - start < OFF_ROUTE_GRACE_MIN) {
      return null;
    }
    const distance: number = Geo.distanceM(ctx.fix, TripSignals.pointOf(current));
    if (distance <= OFF_ROUTE_MIN_M) {
      return null;
    }
    const s: TripSuggestion = {
      key: `off_route:${current.id}`,
      kind: SignalKind.OFF_ROUTE,
      title: `离「${current.title}」${Geo.distanceText(distance)}`,
      detail: `已过开始时间 ${DurationCn.text(ctx.nowMin - start)}，看样子赶不上了`,
      action: SignalAction.SKIP,
      targetId: current.id,
      deltaMin: 0,
      actionLabel: '跳过这一站'
    };
    return s;
  }

  private static behind(owed: Activity, lag: number, stops: Activity[],
    ctx: SignalContext): TripSuggestion | null {
    if (TripSignals.hasShiftTargets(stops, ctx.nowMin)) {
      const delta: number = TripSignals.shiftDelta(lag);
      const shifted: TripSuggestion = {
        key: `behind:${owed.id}`,
        kind: SignalKind.BEHIND,
        title: `比计划晚 ${DurationCn.text(lag)}`,
        detail: `「${owed.title}」还没打卡，后续按原时间排`,
        action: SignalAction.SHIFT,
        targetId: owed.id,
        deltaMin: delta,
        actionLabel: `顺延 ${DurationCn.text(delta)}`
      };
      return shifted;
    }
    if (!SkipPlanner.isSkippable(owed.category, owed.status)) {
      return null;
    }
    const skipped: TripSuggestion = {
      key: `behind:${owed.id}`,
      kind: SignalKind.BEHIND,
      title: `比计划晚 ${DurationCn.text(lag)}`,
      detail: `「${owed.title}」还没打卡，今天没有可顺延的站`,
      action: SignalAction.SKIP,
      targetId: owed.id,
      deltaMin: 0,
      actionLabel: '跳过这一站'
    };
    return skipped;
  }

  private static rain(stops: Activity[], ctx: SignalContext): TripSuggestion | null {
    const weather: WeatherDay | null = ctx.weather;
    if (weather === null) {
      return null;
    }
    let target: Activity | null = null;
    for (const a of stops) {
      if (TripSignals.startOf(a) < ctx.nowMin) {
        continue;
      }
      if (!TripSignals.outdoor(a) || !SkipPlanner.isSkippable(a.category, a.status)) {
        continue;
      }
      target = a;
      break;
    }
    if (target === null) {
      return null;
    }
    const start: number = TripSignals.startOf(target);
    const end: number = TripSignals.endOf(target, start);
    const prob: number = WeatherAdvisor.rainIn(weather, start, end);
    if (prob < WeatherAdvisor.RAIN_MIN_PROB) {
      return null;
    }
    const s: TripSuggestion = {
      key: `rain:${target.id}`,
      kind: SignalKind.RAIN,
      title: '前方室外站有雨',
      detail: `「${target.title}」${DateUtils.hhmmOf(start)}–${DateUtils.hhmmOf(end)}`
        + ` 降水 ${Math.round(prob)}%，可跳过`,
      action: SignalAction.SKIP,
      targetId: target.id,
      deltaMin: 0,
      actionLabel: '跳过这一站'
    };
    return s;
  }

  private static hasShiftTargets(stops: Activity[], nowMin: number): boolean {
    for (const a of stops) {
      if (SkipPlanner.isShiftTarget(a, nowMin)) {
        return true;
      }
    }
    return false;
  }

  private static outdoor(a: Activity): boolean {
    return a.category === ActivityCategory.SIGHT || a.category === ActivityCategory.SHOP ||
      a.category === ActivityCategory.OTHER;
  }

  private static checked(a: Activity, checkedIds: string[]): boolean {
    return checkedIds.indexOf(a.id) >= 0;
  }

  private static pointOf(a: Activity): GeoPoint {
    const p: GeoPoint = { latitude: a.latitude, longitude: a.longitude };
    return p;
  }

  private static startOf(a: Activity): number {
    return Math.max(0, DateUtils.minutesOf(a.time));
  }

  private static endOf(a: Activity, startMin: number): number {
    const end: number = DateUtils.minutesOf(a.endTime);
    const candidate: number = end > startMin ? end : startMin + DEFAULT_DWELL_MIN;
    return Math.min(DAY_END, candidate);
  }

  /** 落后分钟向上取 15 的倍数，夹到 [15, 120] */
  private static shiftDelta(lag: number): number {
    const rounded: number = Math.ceil(lag / SHIFT_MIN) * SHIFT_MIN;
    return Math.min(SHIFT_MAX, Math.max(SHIFT_MIN, rounded));
  }
}
