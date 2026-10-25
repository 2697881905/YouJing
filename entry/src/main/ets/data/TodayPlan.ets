/**
 * 今日行程卡片数据（屏13 / 桌面 Widget）。
 *
 * 纯函数收口：Trip + 今天日期 + 当前时刻 → 卡片四段文案，便于离线推演与真机比对。
 * 口径全部取行程真值，没有的字段不编：
 * - dayTitle：Day N · M月D日
 * - meta：还剩 N 站 · 共 M 站（按当前时刻与活动开始时间比较）
 * - rows：优先未开始的节点，最多 4 条（2×2 由卡片层截到 3 条，2×4 用满 4 条）
 * - stopTotal / stopCurrent：当日节点总数与「下一站」在整日序列里的 1-based 序号，
 *   供 2×4 的编号站点条使用；全部已开始时 stopCurrent 记 0
 * - footer：剩余需预约节点数 + 最晚一个节点的开始时刻；无则「今日无需预约节点」
 */

import { Activity, ActivityStatus, Trip, TripDay } from '../model/Trip';
import { CategoryStyle } from '../utils/CategoryStyle';
import { DateUtils } from '../utils/DateUtils';

export interface CardRowData {
  time: string;
  name: string;
  /** 色点名（CategoryStyle），卡片按它取 $r，不再按行序给色 */
  dot: string;
}

export interface TodayPlanData {
  tripId: string;
  dayTitle: string;
  meta: string;
  footer: string;
  rows: CardRowData[];
  /** 当日节点总数（2×4 编号站点条的格数） */
  stopTotal: number;
  /** 下一站在整日序列里的 1-based 序号；全部已开始时为 0 */
  stopCurrent: number;
  /** 最近一个「还需预约」节点的 1-based 序号（帧 Widget B 上那圈金色描边）；没有则 0 */
  stopBooking: number;
}

/** 2×4 用满 4 行；2×2 由卡片层截到 3 行（帧 Widget A 只有三行） */
const MAX_ROWS: number = 4;

function cnDate(iso: string): string {
  const parts: string[] = iso.split('-');
  if (parts.length < 3) {
    return iso;
  }
  return `${Number(parts[1])}月${Number(parts[2])}日`;
}

/** 卡片只提醒「还需你处理」的节点：已约(BOOKED) 不进计数（与 CalendarSync 的建日程口径不同） */
function pendingBooking(act: Activity): boolean {
  return act.status === ActivityStatus.NOT_BOOKED || act.status === ActivityStatus.PENDING ||
    act.status === ActivityStatus.FULL;
}

export class TodayPlan {
  /** 命中当日则出卡片数据，否则返回 null（卡片自行显示空态） */
  static of(trip: Trip, todayIso: string, nowHHmm: string): TodayPlanData | null {
    let day: TripDay | null = null;
    for (const d of trip.days) {
      if (d.date === todayIso) {
        day = d;
        break;
      }
    }
    if (day === null || day.activities.length === 0) {
      return null;
    }
    const upcoming: Activity[] = day.activities.filter((a: Activity): boolean => a.time >= nowHHmm);
    const picked: Activity[] = upcoming.length >= MAX_ROWS
      ? upcoming.slice(0, MAX_ROWS)
      : day.activities.slice(0, MAX_ROWS);
    const rows: CardRowData[] = picked.map((a: Activity): CardRowData => {
      const row: CardRowData = {
        time: a.time, name: a.title, dot: CategoryStyle.colorName(a.category)
      };
      return row;
    });
    const bookings: Activity[] = day.activities.filter((a: Activity): boolean => pendingBooking(a));
    const remaining: Activity[] = upcoming.filter((a: Activity): boolean => pendingBooking(a));
    let footer: string = '今日无需预约节点';
    if (remaining.length > 0) {
      let latest: string = remaining[0].time;
      for (const a of remaining) {
        if (a.time > latest) {
          latest = a.time;
        }
      }
      footer = `还有 ${remaining.length} 个需预约节点 · ${latest} 前`;
    } else if (bookings.length > 0) {
      footer = `${bookings.length} 个预约节点已全部开始`;
    }
    const plan: TodayPlanData = {
      tripId: trip.id,
      dayTitle: `Day ${day.dayIndex} · ${cnDate(day.date)}`,
      meta: `还剩 ${upcoming.length} 站 · 共 ${day.activities.length} 站`,
      footer: footer,
      rows: rows,
      stopTotal: day.activities.length,
      stopCurrent: TodayPlan.currentIndexOf(day, (a: Activity): boolean => a.time >= nowHHmm),
      stopBooking: TodayPlan.currentIndexOf(day, (a: Activity): boolean => a.time >= nowHHmm && pendingBooking(a))
    };
    return plan;
  }

  /** 命中条件的首个节点在当日序列里的 1-based 序号；没有命中则返回 0 */
  static currentIndexOf(day: TripDay, hit: (a: Activity) => boolean): number {
    for (let i = 0; i < day.activities.length; i++) {
      if (hit(day.activities[i])) {
        return i + 1;
      }
    }
    return 0;
  }

  static nowHHmm(): string {
    const d: Date = new Date();
    const h: string = `${d.getHours()}`;
    const m: string = `${d.getMinutes()}`;
    return `${h.length < 2 ? `0${h}` : h}:${m.length < 2 ? `0${m}` : m}`;
  }

  static today(): string {
    return DateUtils.todayIso();
  }
}
