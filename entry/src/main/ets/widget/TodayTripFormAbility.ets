/**
 * 今日行程万能卡片 FormExtensionAbility（屏13，帧 7fc1cb85）。
 * 契约：卡片实色填充、永不模糊（DESIGN.md L593，widget 本就不支持 backdrop-filter）。
 *
 * 数据通路：卡片进程直接读同一份 RDB（分区键走 AccountStore 默认游客分区），
 * onAddForm 先回空态、异步取到今日行程后 formProvider.updateForm 回灌；
 * 定时刷新由 form_config.json 的 updateDuration=1（30 分钟，系统最小粒度）驱动 onUpdateForm。
 */

import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { Logger } from '../common/logger/Logger';
import { TripDao } from '../data/TripDao';
import { TodayPlanData } from '../data/TodayPlan';

const TAG: string = 'Widget.TodayTrip';
/** 卡片尺寸不入库，落在 preferences：onUpdateForm 只有 formId，进程重启后要靠它还原 2×4 的 16 内缩 */
const DIM_PREFS: string = 'widget_form_dims';
const DIM_KEY_2X2: string = '2*2';
const DIM_KEY_2X4: string = '2*4';

function emptyData(dimension: string): Record<string, string> {
  const data: Record<string, string> = {
    'dayTitle': '今天没有行程安排', 'meta': '打开有径规划一段', 'footer': '生成行程后自动出现在这里',
    'r1t': '', 'r1n': '', 'r2t': '', 'r2n': '', 'r3t': '', 'r3n': '', 'tripId': '',
    'dimension': dimension
  };
  return data;
}

function toData(plan: TodayPlanData, dimension: string): Record<string, string> {
  const data: Record<string, string> = {
    'dayTitle': plan.dayTitle, 'meta': plan.meta, 'footer': plan.footer,
    'r1t': plan.rows.length > 0 ? plan.rows[0].time : '',
    'r1n': plan.rows.length > 0 ? plan.rows[0].name : '',
    'r2t': plan.rows.length > 1 ? plan.rows[1].time : '',
    'r2n': plan.rows.length > 1 ? plan.rows[1].name : '',
    'r3t': plan.rows.length > 2 ? plan.rows[2].time : '',
    'r3n': plan.rows.length > 2 ? plan.rows[2].name : '',
    'tripId': plan.tripId,
    'dimension': dimension
  };
  return data;
}

export default class TodayTripFormAbility extends FormExtensionAbility {
  private dimPrefs: preferences.Preferences | null = null;

  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId: string = TodayTripFormAbility.formIdOf(want);
    const dimension: string = TodayTripFormAbility.dimensionOf(want);
    Logger.info(TAG, `onAddForm ${formId} ${dimension}`);
    this.saveDimension(formId, dimension);
    this.refresh(formId);
    return formBindingData.createFormBindingData(emptyData(dimension));
  }

  onCastToNormalForm(formId: string): void {
    Logger.info(TAG, `onCastToNormalForm ${formId}`);
  }

  onUpdateForm(formId: string): void {
    this.refresh(formId);
  }

  onFormEvent(formId: string, message: string): void {
    Logger.info(TAG, `onFormEvent ${formId} ${message}`);
    this.refresh(formId);
  }

  onRemoveForm(formId: string): void {
    Logger.info(TAG, `onRemoveForm ${formId}`);
    const prefs: preferences.Preferences | null = this.prefs();
    if (prefs === null) {
      return;
    }
    try {
      prefs.deleteSync(formId);
      prefs.flush().catch((err: Error): void => {
        Logger.warn(TAG, `尺寸偏好落盘失败: ${err.message}`);
      });
    } catch (err) {
      Logger.warn(TAG, `尺寸偏好清理失败: ${(err as Error).message}`);
    }
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }

  private static formIdOf(want: Want): string {
    const params: Record<string, Object> | undefined = want.parameters;
    if (params === undefined) {
      return '';
    }
    const raw: Object | undefined = params[formInfo.FormParam.IDENTITY_KEY];
    return typeof raw === 'string' ? raw as string : '';
  }

  /** FormDimension：1=1*2 / 2=2*2 / 3=2*4；只声明了 2*2、2*4，其余按 2*2 兜底 */
  private static dimensionOf(want: Want): string {
    const params: Record<string, Object> | undefined = want.parameters;
    if (params === undefined) {
      return DIM_KEY_2X2;
    }
    const raw: Object | undefined = params[formInfo.FormParam.DIMENSION_KEY];
    if (raw === undefined) {
      return DIM_KEY_2X2;
    }
    let dimension: number = 2;
    if (typeof raw === 'number') {
      dimension = raw as number;
    } else if (typeof raw === 'string') {
      dimension = Number(raw as string);
    }
    return dimension === 3 ? DIM_KEY_2X4 : DIM_KEY_2X2;
  }

  private prefs(): preferences.Preferences | null {
    if (this.dimPrefs === null) {
      try {
        this.dimPrefs = preferences.getPreferencesSync(this.context, { name: DIM_PREFS });
      } catch (err) {
        Logger.warn(TAG, `尺寸偏好打开失败: ${(err as Error).message}`);
        return null;
      }
    }
    return this.dimPrefs;
  }

  private saveDimension(formId: string, dimension: string): void {
    if (formId.length === 0) {
      return;
    }
    const prefs: preferences.Preferences | null = this.prefs();
    if (prefs === null) {
      return;
    }
    try {
      prefs.putSync(formId, dimension);
      prefs.flush().catch((err: Error): void => {
        Logger.warn(TAG, `尺寸偏好落盘失败: ${err.message}`);
      });
    } catch (err) {
      Logger.warn(TAG, `尺寸偏好写入失败: ${(err as Error).message}`);
    }
  }

  private storedDimension(formId: string): string {
    const prefs: preferences.Preferences | null = this.prefs();
    if (prefs === null) {
      return DIM_KEY_2X2;
    }
    try {
      const raw: preferences.ValueType = prefs.getSync(formId, DIM_KEY_2X2);
      return typeof raw === 'string' ? raw as string : DIM_KEY_2X2;
    } catch (err) {
      Logger.warn(TAG, `尺寸偏好读取失败: ${(err as Error).message}`);
      return DIM_KEY_2X2;
    }
  }

  private refresh(formId: string): void {
    if (formId.length === 0) {
      return;
    }
    const dimension: string = this.storedDimension(formId);
    TripDao.todayPlan(this.context).then((plan: TodayPlanData | null) => {
      const data: Record<string, string> = plan === null ? emptyData(dimension) : toData(plan, dimension);
      return formProvider.updateForm(formId, formBindingData.createFormBindingData(data));
    }).then((): void => {
      Logger.info(TAG, `回灌卡片 ${formId} ${dimension}`);
    }).catch((err: Error) => {
      Logger.warn(TAG, `卡片刷新失败: ${err.message}`);
    });
  }
}
