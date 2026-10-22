/**
 * 今日行程万能卡片 FormExtensionAbility（屏13，帧 7fc1cb85）。
 * 契约：卡片实色填充、永不模糊（DESIGN.md L593，widget 本就不支持 backdrop-filter）。
 * 骨架期 onAddForm 回灌 mock 数据；阶段 9 接 RDB 真实今日节点 + 15 分钟定时刷新。
 */

import { FormExtensionAbility, formBindingData, formInfo } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { Logger } from '../common/logger/Logger';

export default class TodayTripFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    Logger.info('Widget.TodayTrip', 'onAddForm');
    const data: Record<string, string> = {
      'dayTitle': 'Day 2 · 6月11日',
      'meta': '步行 5.2km · 还剩 2 站',
      'footer': '还有 1 个需预约节点 · 14:20 前'
    };
    return formBindingData.createFormBindingData(data);
  }

  onCastToNormalForm(formId: string): void {
    Logger.info('Widget.TodayTrip', `onCastToNormalForm ${formId}`);
  }

  onUpdateForm(formId: string): void {
    Logger.info('Widget.TodayTrip', `onUpdateForm ${formId}`);
  }

  onFormEvent(formId: string, message: string): void {
    Logger.info('Widget.TodayTrip', `onFormEvent ${formId}`);
  }

  onRemoveForm(formId: string): void {
    Logger.info('Widget.TodayTrip', `onRemoveForm ${formId}`);
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }
}
