/**
 * 规划草稿（跨页共享态，pages→data 单向依赖）。
 * 屏2/3/4/5 逐步写入，屏6 组装 PlanParams 消费；重置入口在生成完成或用户回首页新建。
 */

import { PaceOption, SelectedSpot, SelectedArea, TransitPreference, TravelStyle, TripBasicInput } from '../model/PlanParams';

export class PlanDraft {
  private static instance: PlanDraft | null = null;

  basic: TripBasicInput = {
    destination: '北京', startDate: '2026-07-01', endDate: '2026-07-03', people: 2, budget: 8000
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

  reset(): void {
    this.selectedSpots = [];
    this.selectedArea = { areaId: '' };
    this.paces = [PaceOption.STANDARD];
  }
}
