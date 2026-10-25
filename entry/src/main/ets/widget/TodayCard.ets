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
import { CardRowData, TodayPlanData } from '../data/TodayPlan';

const TAG: string = 'Widget.TodayCard';
export const WIDGET_DIM_PREFS: string = 'widget_form_dims';
export const DIM_KEY_2X2: string = '2*2';
export const DIM_KEY_2X4: string = '2*4';

/**
 * 卡片键集 = 帧屏13 的两块形态所需：抬头/标题/meta/三行（2×2）或四行 + 编号站点条（2×4）/footer。
 * 2×2 时 r4* 与站点条两个键一律给空串，卡片按空串不渲染——不是留白，是这条形态帧里就没有。
 */
export function emptyCardData(dimension: string): Record<string, string> {
  const data: Record<string, string> = {
    'dayTitle': '今天没有行程安排', 'meta': '', 'footer': '生成行程后自动出现在这里',
    'r1t': '', 'r1n': '', 'r1c': '', 'r2t': '', 'r2n': '', 'r2c': '', 'r3t': '', 'r3n': '', 'r3c': '',
    'r4t': '', 'r4n': '', 'r4c': '',
    'stopTotal': '', 'stopCurrent': '', 'stopBooking': '',
    'tripId': '',
    'dimension': dimension
  };
  return data;
}

/** 2×2 只放得下三行（帧 Widget A 就是三行），2×4 用满四行并带编号站点条 */
const SMALL_ROWS: number = 3;

function rowKeys(rows: CardRowData[], data: Record<string, string>): void {
  for (let i = 0; i < 4; i++) {
    const n: string = `${i + 1}`;
    const has: boolean = i < rows.length;
    data[`r${n}t`] = has ? rows[i].time : '';
    data[`r${n}n`] = has ? rows[i].name : '';
    data[`r${n}c`] = has ? rows[i].dot : '';
  }
}

export function toCardData(plan: TodayPlanData, dimension: string): Record<string, string> {
  const wide: boolean = dimension === DIM_KEY_2X4;
  const rows: CardRowData[] = wide ? plan.rows : plan.rows.slice(0, SMALL_ROWS);
  const data: Record<string, string> = {
    'dayTitle': plan.dayTitle, 'meta': plan.meta, 'footer': plan.footer,
    'r1t': '', 'r1n': '', 'r1c': '', 'r2t': '', 'r2n': '', 'r2c': '', 'r3t': '', 'r3n': '', 'r3c': '',
    'r4t': '', 'r4n': '', 'r4c': '',
    'stopTotal': wide ? `${plan.stopTotal}` : '',
    'stopCurrent': wide ? `${plan.stopCurrent}` : '',
    'stopBooking': wide ? `${plan.stopBooking}` : '',
    'tripId': plan.tripId,
    'dimension': dimension
  };
  rowKeys(rows, data);
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
