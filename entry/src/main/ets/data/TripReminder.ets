/**
 * 系统级主动提醒（reminderAgentManager）。与日历写入是两条独立通路：
 * 不进 CalendarSync、不经过导出付费墙，退后台/锁屏后由系统代理按时弹出。
 *
 * 三类提醒（与开发清单 P4 对齐）：
 * 1. 出发前 TIMER —— 出发前一天 20:00，倒数计时由系统代理持有；
 * 2. 预约提前 CALENDAR —— 按 Activity.advanceDays 逐条，在游玩日 09:00 之前 N 天；
 * 3. 当日晨间播报 CALENDAR —— 每天 07:30，报当日站数与首末站。
 *
 * 为什么晨间播报不用 ALARM：ReminderRequestAlarm 的 daysOfWeek 语义是「每周重复」，
 * 一趟行程的多天会在同一时刻叠成一组、之后每周再响；只有 CALENDAR 能钉住具体日期。
 *
 * 幂等：发布前按 tripId 撤销上一批 reminderId（只撤自己发布的），
 * 清单存 preferences 分片 youjing_reminder。
 *
 * ⚠️ 真机闸门（2026-11 实测）：手机/平板对代理提醒有管控，publishReminder 返回
 * `ungranted capability: com.huawei.service.notification.agentreminder`。
 * 需在 AGC「开放能力管理 → 代理提醒」申请（8 个工作日），通过后重新生成 Profile
 * 并手动签名；开通前本类会如实返回 failed，页面提示发布失败，锁屏提醒无法验收。
 * 详见 Docs/围栏与后台唤醒开通清单.md §五。
 */

import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { preferences } from '@kit.ArkData';
import { Trip } from '../model/Trip';
import { ReminderKind, ReminderPlan, ReminderPlanItem } from '../utils/ReminderPlan';
import { Logger } from '../common/logger/Logger';

const TAG: string = 'Data.TripReminder';
const PREFS: string = 'youjing_reminder';
const KEY_PREFIX: string = 'reminder_ids_';
const PKG_NAME: string = 'com.youjing.app';
const ABILITY_NAME: string = 'EntryAbility';

export interface ReminderSyncResult {
  scheduled: number;
  cancelled: number;
  failed: number;
  /** 系统通知开关；false 时提醒即使发布也可能不响，页面据此如实告知 */
  notificationsEnabled: boolean;
  /** 代理提醒能力未开通（AGC 管控）；页面据此给可行动提示，而不是泛泛的「失败」 */
  blockedByCapability: boolean;
  /** 本 App 提醒数量确实达到系统上限（与管控伪装成 1700002 的情况区分） */
  blockedByLimit: boolean;
}

function toLocalDateTime(ms: number): reminderAgentManager.LocalDateTime {
  const d: Date = new Date(ms);
  return {
    year: d.getFullYear(),
    month: d.getMonth() + 1,
    day: d.getDate(),
    hour: d.getHours(),
    minute: d.getMinutes(),
    second: 0
  };
}

export class TripReminder {
  /** 发布整趟行程的提醒：先撤旧批次，再把未来窗口逐条交给系统代理 */
  static async syncTrip(context: common.UIAbilityContext, trip: Trip): Promise<ReminderSyncResult> {
    const cancelled: number = await TripReminder.cancelTrip(context, trip.id);
    const enabled: boolean = await TripReminder.ensureNotification(context);
    const items: ReminderPlanItem[] = ReminderPlan.plan(trip, Date.now());
    const ids: number[] = [];
    let failed: number = 0;
    let blockedByCapability: boolean = false;
    let blockedByLimit: boolean = false;
    // 管控设备上 VerifyCloudCapability 失败也会报 1700002（数量超限）。
    // 发布前记下本 App 的有效提醒数：0 条却「超限」= 能力未开通，不是我们堆满的。
    let existingCount: number = 0;
    try {
      const existing: reminderAgentManager.ReminderInfo[] =
        await reminderAgentManager.getAllValidReminders();
      existingCount = existing.length;
    } catch (err) {
      Logger.warn(TAG, `读取有效提醒数失败: ${(err as Error).message}`);
    }
    for (let i = 0; i < items.length; i++) {
      try {
        const id: number = await TripReminder.publish(trip.id, i, items[i]);
        ids.push(id);
      } catch (err) {
        failed++;
        const be: BusinessError = err as BusinessError;
        const message: string = be.message;
        // 201 = 权限被拒；管控设备上即使声明了 normal 权限也会因 capability 未开通被拒
        if (be.code === 201 || message.indexOf('agentreminder') >= 0 ||
          message.indexOf('ungranted capability') >= 0) {
          blockedByCapability = true;
        } else if (be.code === 1700002) {
          if (existingCount === 0) {
            blockedByCapability = true;
          } else {
            blockedByLimit = true;
          }
        }
        Logger.warn(TAG, `发布失败 ${items[i].kind} ${items[i].title}: code=${be.code} ${message}`);
      }
    }
    await TripReminder.writeIds(context, trip.id, ids);
    Logger.info(TAG, `提醒写入 trip=${trip.id} 计划=${items.length} 成功=${ids.length} ` +
      `失败=${failed} 清理=${cancelled} 通知开关=${enabled} 能力未开通=${blockedByCapability} ` +
      `数量超限=${blockedByLimit} 发布前有效=${existingCount}`);
    return {
      scheduled: ids.length, cancelled: cancelled, failed: failed,
      notificationsEnabled: enabled, blockedByCapability: blockedByCapability,
      blockedByLimit: blockedByLimit
    };
  }

  /** 撤销本机此前为该行程发布的提醒；返回撤销条数 */
  static async cancelTrip(context: common.Context, tripId: string): Promise<number> {
    const ids: number[] = await TripReminder.readIds(context, tripId);
    if (ids.length === 0) {
      return 0;
    }
    let removed: number = 0;
    for (const id of ids) {
      try {
        await reminderAgentManager.cancelReminder(id);
        removed++;
      } catch (err) {
        Logger.warn(TAG, `撤销提醒 ${id} 失败: ${(err as Error).message}`);
      }
    }
    await TripReminder.writeIds(context, tripId, []);
    return removed;
  }

  private static async publish(tripId: string, index: number, item: ReminderPlanItem): Promise<number> {
    const notificationId: number = TripReminder.notificationId(tripId, index);
    const wantAgent: reminderAgentManager.WantAgent = {
      pkgName: PKG_NAME,
      abilityName: ABILITY_NAME
    };
    if (item.kind === ReminderKind.DEPARTURE) {
      const seconds: number = Math.max(1, Math.floor((item.at - Date.now()) / 1000));
      const timer: reminderAgentManager.ReminderRequestTimer = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_TIMER,
        triggerTimeInSeconds: seconds,
        title: item.title,
        content: item.content,
        expiredContent: item.content,
        notificationId: notificationId,
        groupId: `youjing_${tripId}`,
        wantAgent: wantAgent
      };
      return await reminderAgentManager.publishReminder(timer);
    }
    const calendar: reminderAgentManager.ReminderRequestCalendar = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
      dateTime: toLocalDateTime(item.at),
      title: item.title,
      content: item.content,
      expiredContent: item.content,
      notificationId: notificationId,
      groupId: `youjing_${tripId}`,
      wantAgent: wantAgent
    };
    return await reminderAgentManager.publishReminder(calendar);
  }

  /**
   * 调试探针（只有 debug 版 EntryAbility 在显式 `--ps remindprobe N` 时调用）：
   * N 秒后弹一条系统提醒，用于真机验收「退后台/锁屏后提醒真的响」——
   * 这是 P4 唯一无法靠静态代码证明的部分，真实行程的提醒窗口动辄几小时，等不起。
   */
  static async publishProbe(context: common.UIAbilityContext, seconds: number): Promise<number> {
    const enabled: boolean = await TripReminder.ensureNotification(context);
    const timer: reminderAgentManager.ReminderRequestTimer = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_TIMER,
      triggerTimeInSeconds: Math.max(1, Math.floor(seconds)),
      title: '有径提醒自检',
      content: `锁屏提醒通路正常（${Math.floor(seconds)} 秒）`,
      expiredContent: '有径提醒自检',
      notificationId: Math.floor(Date.now() % 100000000),
      groupId: 'youjing_probe',
      wantAgent: {
        pkgName: PKG_NAME,
        abilityName: ABILITY_NAME
      }
    };
    try {
      const existing: reminderAgentManager.ReminderInfo[] = await reminderAgentManager.getAllValidReminders();
      Logger.info(TAG, `提醒探针前有效提醒=${existing.length}`);
      const id: number = await reminderAgentManager.publishReminder(timer);
      Logger.info(TAG, `提醒探针已发布 id=${id} seconds=${seconds} 通知开关=${enabled}`);
      return id;
    } catch (err) {
      // 探针只用于 debug 验收：撞上限时清掉本 App 的旧提醒再发一次。
      // 正常用户路径（syncTrip）不做这个动作，避免误删真实提醒。
      Logger.warn(TAG, `提醒探针首次发布失败: ${(err as Error).message}，清理本 App 旧提醒后重试`);
      await reminderAgentManager.cancelAllReminders();
      // 取消是异步落库的，立刻重发仍可能读到旧计数，等一轮再试
      await TripReminder.delay(3000);
      const id: number = await reminderAgentManager.publishReminder(timer);
      Logger.info(TAG, `提醒探针清理后已发布 id=${id} seconds=${seconds} 通知开关=${enabled}`);
      return id;
    }
  }

  /**
   * 调试探针专用：清空本 App 的有效提醒并返回清理前条数。
   * 真机反复跑探针会把 64 条配额堆满（1700002），清理后才能看到真正的能力闸门。
   */
  static async clearAllForProbe(): Promise<number> {
    try {
      const existing: reminderAgentManager.ReminderInfo[] =
        await reminderAgentManager.getAllValidReminders();
      await reminderAgentManager.cancelAllReminders();
      Logger.info(TAG, `探针清理有效提醒=${existing.length}`);
      return existing.length;
    } catch (err) {
      Logger.warn(TAG, `探针清理提醒失败: ${(err as Error).message}`);
      return -1;
    }
  }

  private static delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, ms);
    });
  }

  /** 通知被关时提醒不会响；这里只在用户开启提醒的当下请求一次授权 */
  private static async ensureNotification(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const enabled: boolean = await notificationManager.isNotificationEnabled();
      if (enabled) {
        return true;
      }
      await notificationManager.requestEnableNotification(context);
      // 授权弹窗可能被拒绝；以系统真实开关为准，避免把「拒绝」当成「已开启」
      return await notificationManager.isNotificationEnabled();
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      Logger.warn(TAG, `通知开关不可用 code=${be.code} ${be.message}`);
      return false;
    }
  }

  /** 同一行程内的 notificationId 必须唯一，否则后发的会覆盖先发的 */
  private static notificationId(tripId: string, index: number): number {
    let hash: number = 0;
    for (let i = 0; i < tripId.length; i++) {
      hash = (hash * 31 + tripId.charCodeAt(i)) % 1000000;
    }
    return hash * 100 + (index % 100);
  }

  private static async prefsOf(context: common.Context): Promise<preferences.Preferences> {
    return await preferences.getPreferences(context, PREFS);
  }

  private static async readIds(context: common.Context, tripId: string): Promise<number[]> {
    const prefs: preferences.Preferences = await TripReminder.prefsOf(context);
    const raw: string = prefs.getSync(`${KEY_PREFIX}${tripId}`, '') as string;
    if (raw.length === 0) {
      return [];
    }
    try {
      return JSON.parse(raw) as number[];
    } catch (err) {
      return [];
    }
  }

  private static async writeIds(context: common.Context, tripId: string, ids: number[]): Promise<void> {
    const prefs: preferences.Preferences = await TripReminder.prefsOf(context);
    prefs.putSync(`${KEY_PREFIX}${tripId}`, JSON.stringify(ids));
    await prefs.flush();
  }
}
