/**
 * 系统日历写入（开发文档 §6 阶段 9：Calendar Kit 日程写入 + 提前提醒）。
 *
 * 屏14「同意并写入」是唯一入口，未授权/未同意不写任何数据：
 * - 需预约节点 → 一条定时日程，标题带「需预约」，开提醒时按 booking.advanceDays 提前量给 reminderTime；
 * - 每日 → 一条全天日程（Day N 主题 + 首末站），保证日历上能看到整段行程。
 *
 * 幂等：每次写入前按 tripId 删除本机上次写入的事件 id（只删自己写的，绝不动用户自建日程），
 * 事件 id 清单存 preferences 分片 youjing_access。
 */

import { calendarManager } from '@kit.CalendarKit';
import { abilityAccessCtrl, common, PermissionRequestResult } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { Activity, ActivityStatus, Trip, TripDay } from '../model/Trip';
import { Logger } from '../common/logger/Logger';

const TAG: string = 'Data.CalendarSync';
const CAL_ACCOUNT_NAME: string = 'com.youjing.app';
const ACCESS_PREFS: string = 'youjing_access';
const KEY_EVENT_PREFIX: string = 'cal_events_';
const DAY_MS: number = 86400000;

/** 屏14 三条开关 */
export interface AccessFlags {
  calendar: boolean;
  card: boolean;
  remind: boolean;
}

/** 写入结果（屏14 回执与日志用） */
export interface SyncResult {
  bookingEvents: number;
  dayEvents: number;
  removed: number;
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

function hhmm(time: string): string {
  return time.length >= 5 ? time.substring(0, 5) : time;
}

export class CalendarSync {
  /** 需预约节点条数（屏14 文案「写入 N 个预约节点 + M 天行程」按真值渲染） */
  static bookingCount(trip: Trip): number {
    let n: number = 0;
    for (const day of trip.days) {
      for (const act of day.activities) {
        if (CalendarSync.isBookingNode(act)) {
          n++;
        }
      }
    }
    return n;
  }

  /** 预约节点 = 状态标注为需预约/未约/约满/待定的活动 */
  static isBookingNode(act: Activity): boolean {
    return act.status === ActivityStatus.NOT_BOOKED || act.status === ActivityStatus.PENDING ||
      act.status === ActivityStatus.FULL || act.status === ActivityStatus.BOOKED;
  }

  static async syncTrip(context: common.UIAbilityContext, trip: Trip,
    flags: AccessFlags): Promise<SyncResult> {
    const manager: calendarManager.CalendarManager = calendarManager.getCalendarManager(context);
    const calendar: calendarManager.Calendar = await CalendarSync.ensureCalendar(manager);
    const result: SyncResult = { bookingEvents: 0, dayEvents: 0, removed: 0 };

    result.removed = await CalendarSync.clearPrevious(context, manager, trip.id);

    for (const day of trip.days) {
      for (const act of day.activities) {
        if (!CalendarSync.isBookingNode(act)) {
          continue;
        }
        const start: number = toMillis(day.date, act.time);
        const end: number = toMillis(day.date, act.endTime);
        if (start === 0) {
          Logger.warn(TAG, `跳过非法时间 ${day.date} ${act.time} ${act.title}`);
          continue;
        }
        const event: calendarManager.Event = {
          type: calendarManager.EventType.NORMAL,
          title: `${act.title} · 需预约`,
          startTime: start,
          endTime: end > start ? end : start + 3600000,
          description: act.reason === undefined ? act.location : `${act.location}\n${act.reason}`,
          location: { location: act.address.length > 0 ? act.address : act.location },
          reminderTime: flags.remind ? [1440] : undefined
        };
        const id: number = await calendar.addEvent(event);
        result.bookingEvents++;
        await CalendarSync.rememberEvent(context, trip.id, id);
      }
      await CalendarSync.addDayEvent(context, calendar, trip.id, day);
      result.dayEvents++;
    }
    Logger.info(TAG, `写入日历 trip=${trip.id} 预约=${result.bookingEvents} 全天=${result.dayEvents} 清理=${result.removed}`);
    return result;
  }

  private static async addDayEvent(context: common.UIAbilityContext, calendar: calendarManager.Calendar,
    tripId: string, day: TripDay): Promise<void> {
    const start: number = toMillis(day.date, '00:00');
    if (start === 0 || day.activities.length === 0) {
      return;
    }
    const last: Activity = day.activities[day.activities.length - 1];
    const event: calendarManager.Event = {
      type: calendarManager.EventType.NORMAL,
      title: `Day ${day.dayIndex} ${day.theme}`,
      startTime: start,
      endTime: start + DAY_MS - 1,
      isAllDay: true,
      description: `首站 ${day.activities[0].time} ${day.activities[0].title} · 末站 ${last.time} ${last.title}`
    };
    const id: number = await calendar.addEvent(event);
    await CalendarSync.rememberEvent(context, tripId, id);
  }

  private static async ensureCalendar(manager: calendarManager.CalendarManager): Promise<calendarManager.Calendar> {
    const account: calendarManager.CalendarAccount = {
      name: CAL_ACCOUNT_NAME,
      type: calendarManager.CalendarType.LOCAL,
      displayName: '有径行程'
    };
    try {
      return await manager.getCalendar(account);
    } catch (err) {
      Logger.info(TAG, '本机日历不存在，创建：' + (err as Error).message);
      return await manager.createCalendar(account);
    }
  }

  /** 只删本机此前为该行程写入的事件 */
  private static async clearPrevious(context: common.UIAbilityContext, manager: calendarManager.CalendarManager,
    tripId: string): Promise<number> {
    const ids: number[] = await CalendarSync.readEvents(context, tripId);
    if (ids.length === 0) {
      return 0;
    }
    const calendar: calendarManager.Calendar = await CalendarSync.ensureCalendar(manager);
    let removed: number = 0;
    for (const id of ids) {
      try {
        await calendar.deleteEvent(id);
        removed++;
      } catch (err) {
        Logger.warn(TAG, `删除旧事件 ${id} 失败: ${(err as Error).message}`);
      }
    }
    await CalendarSync.writeEvents(context, tripId, []);
    return removed;
  }

  /** 触达开关持久化（屏14 三条开关，重启后保持） */
  static async loadFlags(context: common.UIAbilityContext): Promise<AccessFlags> {
    const prefs: preferences.Preferences = await CalendarSync.prefsOf(context);
    const flags: AccessFlags = {
      calendar: prefs.getSync('flag_calendar', true) as boolean,
      card: prefs.getSync('flag_card', true) as boolean,
      remind: prefs.getSync('flag_remind', true) as boolean
    };
    return flags;
  }

  static async saveFlags(context: common.UIAbilityContext, flags: AccessFlags): Promise<void> {
    const prefs: preferences.Preferences = await CalendarSync.prefsOf(context);
    prefs.putSync('flag_calendar', flags.calendar);
    prefs.putSync('flag_card', flags.card);
    prefs.putSync('flag_remind', flags.remind);
    await prefs.flush();
  }

  /**
   * 屏14「行程卡片」开关的消费方：关掉后主应用不再向桌面卡片投喂行程数据（卡片回到空态）。
   * 卡片本身由用户从桌面添加，App 无权摘除，所以这条开关能做的是停止供数。
   * 读不到偏好（如卡片进程尚未初始化）时按开启处理，避免默认把用户的卡片清空。
   */
  static async cardFeedEnabled(context: common.Context): Promise<boolean> {
    try {
      const prefs: preferences.Preferences = await CalendarSync.prefsOf(context);
      return prefs.getSync('flag_card', true) as boolean;
    } catch (err) {
      Logger.warn(TAG, `卡片开关读取失败，按开启处理: ${(err as Error).message}`);
      return true;
    }
  }

  /** 申请日历读写权限（用户级授权；拒绝或异常返回 false，调用方据此不写任何数据） */
  static async requestPermission(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const result: PermissionRequestResult = await atManager.requestPermissionsFromUser(
        context, ['ohos.permission.READ_CALENDAR', 'ohos.permission.WRITE_CALENDAR']);
      let granted: boolean = true;
      for (const code of result.authResults) {
        if (code !== 0) {
          granted = false;
        }
      }
      Logger.info(TAG, `日历权限授权结果 granted=${granted}`);
      return granted;
    } catch (err) {
      Logger.warn(TAG, `日历权限申请异常: ${(err as Error).message}`);
      return false;
    }
  }

  private static async prefsOf(context: common.Context): Promise<preferences.Preferences> {
    return await preferences.getPreferences(context, ACCESS_PREFS);
  }

  private static async readEvents(context: common.UIAbilityContext, tripId: string): Promise<number[]> {
    const prefs: preferences.Preferences = await CalendarSync.prefsOf(context);
    const raw: string = prefs.getSync(`${KEY_EVENT_PREFIX}${tripId}`, '') as string;
    if (raw.length === 0) {
      return [];
    }
    try {
      const ids: number[] = JSON.parse(raw) as number[];
      return ids;
    } catch (err) {
      return [];
    }
  }

  private static async rememberEvent(context: common.UIAbilityContext, tripId: string, id: number): Promise<void> {
    const ids: number[] = await CalendarSync.readEvents(context, tripId);
    ids.push(id);
    await CalendarSync.writeEvents(context, tripId, ids);
  }

  private static async writeEvents(context: common.UIAbilityContext, tripId: string,
    ids: number[]): Promise<void> {
    const prefs: preferences.Preferences = await CalendarSync.prefsOf(context);
    prefs.putSync(`${KEY_EVENT_PREFIX}${tripId}`, JSON.stringify(ids));
    await prefs.flush();
  }
}
