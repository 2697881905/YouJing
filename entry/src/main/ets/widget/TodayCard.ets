/**
 * 今日卡片数据映射与主动刷新通路。
 * 卡片进程与主应用进程共用：主应用落库/归户后调 refreshAll，卡片不必等 30 分钟定时刷新。
 * 卡片进程没有主应用的内存登录态，刷新前必须自行 AccountStore.init 读回 UnionID 分区。
 */

import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { formBindingData, formProvider } from '@kit.FormKit';
import { Logger } from '../common/logger/Logger';
import { TripDao } from '../data/TripDao';
import { CalendarSync } from '../data/CalendarSync';
import { TodayPlanData } from '../data/TodayPlan';

const TAG: string = 'Widget.TodayCard';
export const WIDGET_DIM_PREFS: string = 'widget_form_dims';
export const DIM_KEY_2X2: string = '2*2';
export const DIM_KEY_2X4: string = '2*4';

export function emptyCardData(dimension: string): Record<string, string> {
  const data: Record<string, string> = {
    'dayTitle': '今天没有行程安排', 'meta': '', 'footer': '生成行程后自动出现在这里',
    'r1t': '', 'r1n': '', 'r1c': '', 'r2t': '', 'r2n': '', 'r2c': '', 'r3t': '', 'r3n': '', 'r3c': '',
    'tripId': '',
    'dimension': dimension
  };
  return data;
}

export function toCardData(plan: TodayPlanData, dimension: string): Record<string, string> {
  const data: Record<string, string> = {
    'dayTitle': plan.dayTitle, 'meta': plan.meta, 'footer': plan.footer,
    'r1t': plan.rows.length > 0 ? plan.rows[0].time : '',
    'r1n': plan.rows.length > 0 ? plan.rows[0].name : '',
    'r1c': plan.rows.length > 0 ? plan.rows[0].dot : '',
    'r2t': plan.rows.length > 1 ? plan.rows[1].time : '',
    'r2n': plan.rows.length > 1 ? plan.rows[1].name : '',
    'r2c': plan.rows.length > 1 ? plan.rows[1].dot : '',
    'r3t': plan.rows.length > 2 ? plan.rows[2].time : '',
    'r3n': plan.rows.length > 2 ? plan.rows[2].name : '',
    'r3c': plan.rows.length > 2 ? plan.rows[2].dot : '',
    'tripId': plan.tripId,
    'dimension': dimension
  };
  return data;
}

export class WidgetSync {
  /** 主应用侧：按 onAddForm 落下的 formId 主动回灌全部卡片；没有卡片时静默跳过 */
  static async refreshAll(context: common.Context): Promise<void> {
    let prefs: preferences.Preferences;
    try {
      prefs = await preferences.getPreferences(context, { name: WIDGET_DIM_PREFS });
    } catch (err) {
      Logger.warn(TAG, `卡片偏好打开失败: ${(err as Error).message}`);
      return;
    }
    const all: Record<string, preferences.ValueType> =
      prefs.getAllSync() as Record<string, preferences.ValueType>;
    const formIds: string[] = Object.keys(all);
    if (formIds.length === 0) {
      return;
    }
    let plan: TodayPlanData | null = null;
    try {
      plan = await TripDao.todayPlan(context);
    } catch (err) {
      Logger.warn(TAG, `今日行程读取失败: ${(err as Error).message}`);
      return;
    }
    // 屏14「行程卡片」关掉时不再供数：卡片退回空态，而不是继续显示上次行程
    const feed: boolean = await CalendarSync.cardFeedEnabled(context);
    if (!feed) {
      plan = null;
    }
    for (const formId of formIds) {
      const stored: preferences.ValueType = all[formId];
      const dimension: string = typeof stored === 'string' ? stored as string : DIM_KEY_2X2;
      const data: Record<string, string> =
        plan === null ? emptyCardData(dimension) : toCardData(plan, dimension);
      try {
        await formProvider.updateForm(formId, formBindingData.createFormBindingData(data));
        Logger.info(TAG, `已刷新卡片 ${formId} ${dimension} 供数=${feed}`);
      } catch (err) {
        Logger.warn(TAG, `刷新卡片失败 ${formId}: ${(err as Error).message}`);
      }
    }
  }
}
