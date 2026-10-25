/**
 * 规划草稿（跨页共享态，pages→data 单向依赖）。
 * 屏2/3/4/5 逐步写入，屏6 组装 PlanParams 消费；重置入口在生成完成或用户回首页新建。
 */

import { PaceOption, SelectedSpot, SelectedArea, TransitPreference, TravelStyle, TripBasicInput } from '../model/PlanParams';
import { BudgetConfig } from '../common/constants/BudgetConfig';

export class PlanDraft {
  private static instance: PlanDraft | null = null;

  // 日期默认留空：具体日期由屏2 按「今天起算」填充（写死字面量会让新装用户在
  // 若干个月后看到默认出发日在过去）。屏4/屏6 的静默兜底一律走 DateUtils.spanDays，
  // 空串在那里按 1 天处理，不会产生 NaN。
  basic: TripBasicInput = {
    destination: '北京', startDate: '', endDate: '', people: 2, budget: BudgetConfig.DEFAULT
  };
  style: TravelStyle = TravelStyle.LEISURE;
  stayTier: string = 'comfort';
  transit: TransitPreference = TransitPreference.PUBLIC;
  paces: PaceOption[] = [PaceOption.STANDARD];
  selectedSpots: SelectedSpot[] = [];
  selectedArea: SelectedArea = { areaId: '' };

  static get(): PlanDraft {
    if (PlanDraft.instance === null) {
      PlanDraft.instance = new PlanDraft();
    }
    return PlanDraft.instance;
  }

  /**
   * 开一段新规划时丢弃旧草稿。
   * 之前只有一个实例方法 reset() 且从未被调用：连着规划第二次时，
   * 上一次的 selectedSpots / selectedArea / 节奏会静默带进来（真机连做三条行程时复现）。
   */
  static fresh(): void {
    PlanDraft.instance = null;
  }
}
