/**
 * 今日行程万能卡片 FormExtensionAbility（屏13，帧 7fc1cb85）。
 * 契约：卡片实色填充、永不模糊（DESIGN.md L593，widget 本就不支持 backdrop-filter）。
 *
 * 数据通路：卡片进程直接读同一份 RDB，但它是独立进程，必须先 AccountStore.init
 * 从 preferences 恢复 UnionID 分区，否则登录用户的数据会被游客分区挡住。
 * onAddForm 先回空态、异步取到今日行程后 formProvider.updateForm 回灌；
 * 定时刷新由 form_config.json 的 updateDuration=1（30 分钟，系统最小粒度）驱动 onUpdateForm，
 * 主应用侧在落库/归户后由 WidgetSync.refreshAll 主动回灌，不等定时。
 */

import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { Logger } from '../common/logger/Logger';
import { AccountStore } from '../data/AccountStore';
import { TripDao } from '../data/TripDao';
import { TodayPlanData } from '../data/TodayPlan';
import { DIM_KEY_2X2, DIM_KEY_2X4, emptyCardData, toCardData, WIDGET_DIM_PREFS } from './TodayCard';

const TAG: string = 'Widget.TodayTrip';

export default class TodayTripFormAbility extends FormExtensionAbility {
  private dimPrefs: preferences.Preferences | null = null;

  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId: string = TodayTripFormAbility.formIdOf(want);
    const dimension: string = TodayTripFormAbility.dimensionOf(want);
    Logger.info(TAG, `onAddForm ${formId} ${dimension}`);
    this.saveDimension(formId, dimension);
    this.refresh(formId);
    return formBindingData.createFormBindingData(emptyCardData(dimension));
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
        this.dimPrefs = preferences.getPreferencesSync(this.context, { name: WIDGET_DIM_PREFS });
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

  /** 卡片进程独立于主应用：先恢复登录态，再把今日行程喂给卡片 */
  private async loadPlan(): Promise<TodayPlanData | null> {
    try {
      await AccountStore.init(this.context);
    } catch (err) {
      Logger.warn(TAG, `登录态恢复失败，按游客分区读卡片: ${(err as Error).message}`);
    }
    return TripDao.todayPlan(this.context);
  }

  private refresh(formId: string): void {
    if (formId.length === 0) {
      return;
    }
    const dimension: string = this.storedDimension(formId);
    this.loadPlan().then((plan: TodayPlanData | null) => {
      const data: Record<string, string> = plan === null ? emptyCardData(dimension) : toCardData(plan, dimension);
      return formProvider.updateForm(formId, formBindingData.createFormBindingData(data));
    }).then((): void => {
      Logger.info(TAG, `回灌卡片 ${formId} ${dimension}`);
    }).catch((err: Error) => {
      Logger.warn(TAG, `卡片刷新失败: ${err.message}`);
    });
  }
}
