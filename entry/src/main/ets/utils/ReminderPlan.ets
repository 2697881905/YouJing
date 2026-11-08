/**
 * P4 三类提醒的纯计划逻辑（不引 @kit，可离线断言）。
 *
 * 1. 出发前：出发前一天 20:00；
 * 2. 预约提前：游玩日 09:00 往前推 advanceDays 天（没带提前量按 1 天兜底）；
 * 3. 晨间播报：每天 07:30，报站数与首末站。
 *
 * 只产出未来窗口；已过的窗口不补发。发布/撤销由 data/TripReminder 负责。
 */

import { Activity, ActivityStatus, Trip, TripDay } from '../model/Trip';

const DAY_MS: number = 86400000;
const DEPARTURE_HHMM: string = '20:00';
const MORNING_HHMM: string = '07:30';
const BOOKING_HHMM: string = '09:00';

export enum ReminderKind {
  DEPARTURE = 'departure',
  MORNING = 'morning',
  BOOKING = 'booking'
}

/** 一条待发布的提醒（纯数据，plan() 可离线断言） */
export interface ReminderPlanItem {
  kind: ReminderKind;
  /** 触发时刻，毫秒时间戳 */
  at: number;
  title: string;
  content: string;
}

function toMillis(date: string, time: string): number {
  const parts: string[] = date.split('-');
  const hm: string[] = time.split(':');
  if (parts.length < 3 || hm.length < 2) {
    return 0;
  }
  return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]),
    Number(hm[0]), Number(hm[1])).getTime();
}

/** 还没约上的节点才需要「该去预约了」的提醒；已约/无需预约不再催 */
function needsBooking(act: Activity): boolean {
  return act.status === ActivityStatus.NOT_BOOKED || act.status === ActivityStatus.PENDING ||
    act.status === ActivityStatus.FULL;
}

/** 库里没有提前量时按 1 天兜底，与日历提醒的旧口径一致 */
function advanceOf(act: Activity): number {
  return act.advanceDays !== undefined && act.advanceDays > 0 ? Math.floor(act.advanceDays) : 1;
}

export class ReminderPlan {
  /** 纯计划：只产出「未来」的提醒，已过窗口直接丢弃（不补发） */
  static plan(trip: Trip, now: number): ReminderPlanItem[] {
    const items: ReminderPlanItem[] = [];
    const departure: number = toMillis(trip.startDate, DEPARTURE_HHMM) - DAY_MS;
    if (departure > now) {
      items.push({
        kind: ReminderKind.DEPARTURE,
        at: departure,
        title: `明天出发去${trip.destination}`,
        content: ReminderPlan.departureText(trip)
      });
    }
    for (const day of trip.days) {
      const morning: number = toMillis(day.date, MORNING_HHMM);
      if (morning > now && day.activities.length > 0) {
        items.push({
          kind: ReminderKind.MORNING,
          at: morning,
          title: `Day ${day.dayIndex} · ${day.theme}`,
          content: ReminderPlan.morningText(day)
        });
      }
      for (const act of day.activities) {
        if (!needsBooking(act)) {
          continue;
        }
        const advance: number = advanceOf(act);
        const at: number = toMillis(day.date, BOOKING_HHMM) - advance * DAY_MS;
        if (at <= now) {
          continue;
        }
        items.push({
          kind: ReminderKind.BOOKING,
          at: at,
          title: `预约提醒 · ${act.title}`,
          content: ReminderPlan.bookingText(act, advance)
        });
      }
    }
    return items;
  }

  private static departureText(trip: Trip): string {
    const head: string = `明天出发去${trip.destination}，共 ${trip.days.length} 天。`;
    if (trip.days.length === 0 || trip.days[0].activities.length === 0) {
      return head;
    }
    const first: Activity = trip.days[0].activities[0];
    return `${head}首日 ${first.time} ${first.title} 出发。`;
  }

  private static morningText(day: TripDay): string {
    const list: Activity[] = day.activities;
    const first: Activity = list[0];
    if (list.length === 1) {
      return `今天 ${list.length} 站：${first.time} ${first.title}`;
    }
    const last: Activity = list[list.length - 1];
    return `今天 ${list.length} 站：${first.time} ${first.title} → ${last.time} ${last.title}`;
  }

  private static bookingText(act: Activity, advance: number): string {
    const hint: string = act.note !== undefined && act.note.length > 0 ? ` · ${act.note}` : '';
    return `需提前 ${advance} 天预约${hint}，以官方为准`;
  }
}
