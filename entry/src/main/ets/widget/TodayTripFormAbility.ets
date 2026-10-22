/**
 * 今日行程万能卡片 FormExtensionAbility（屏13，帧 7fc1cb85）。
 * 契约：卡片实色填充、永不模糊（DESIGN.md L593，widget 本就不支持 backdrop-filter）。
 *
 * 数据通路：卡片进程直接读同一份 RDB（分区键走 AccountStore 默认游客分区），
 * onAddForm 先回空态、异步取到今日行程后 formProvider.updateForm 回灌；
 * 定时刷新由 form_config.json 的 updateDuration=1（30 分钟，系统最小粒度）驱动 onUpdateForm。
 */

import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { common, Want } from '@kit.AbilityKit';
import { Logger } from '../common/logger/Logger';
import { TripDao } from '../data/TripDao';
import { TodayPlan, TodayPlanData } from '../data/TodayPlan';

const TAG: string = 'Widget.TodayTrip';

function emptyData(): Record<string, string> {
  const data: Record<string, string> = {
    'dayTitle': '今天没有行程安排', 'meta': '打开有径规划一段', 'footer': '生成行程后自动出现在这里',
    'r1t': '', 'r1n': '', 'r2t': '', 'r2n': '', 'r3t': '', 'r3n': '', 'tripId': ''
  };
  return data;
}

function toData(plan: TodayPlanData): Record<string, string> {
  const data: Record<string, string> = {
    'dayTitle': plan.dayTitle, 'meta': plan.meta, 'footer': plan.footer,
    'r1t': plan.rows.length > 0 ? plan.rows[0].time : '',
    'r1n': plan.rows.length > 0 ? plan.rows[0].name : '',
    'r2t': plan.rows.length > 1 ? plan.rows[1].time : '',
    'r2n': plan.rows.length > 1 ? plan.rows[1].name : '',
    'r3t': plan.rows.length > 2 ? plan.rows[2].time : '',
    'r3n': plan.rows.length > 2 ? plan.rows[2].name : '',
    'tripId': plan.tripId
  };
  return data;
}

export default class TodayTripFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    Logger.info(TAG, 'onAddForm');
    this.refresh(TodayTripFormAbility.formIdOf(want));
    return formBindingData.createFormBindingData(emptyData());
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

  private refresh(formId: string): void {
    if (formId.length === 0) {
      return;
    }
    TripDao.todayPlan(this.context).then((plan: TodayPlanData | null) => {
      const data: Record<string, string> = plan === null ? emptyData() : toData(plan);
      return formProvider.updateForm(formId, formBindingData.createFormBindingData(data));
    }).then((): void => {
      Logger.info(TAG, `回灌卡片 ${formId}`);
    }).catch((err: Error) => {
      Logger.warn(TAG, `卡片刷新失败: ${err.message}`);
    });
  }
}
