/**
 * 规划草稿状态机回归（data/PlanDraft）。
 * 这里守的是真机复现过的缺陷：原来只有实例方法 reset() 且从未被调用，
 * 连着规划第二段行程时上一段的 selectedSpots / selectedArea / 节奏会静默带进来。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { PlanDraft } from '../../../main/ets/data/PlanDraft';
import { BudgetConfig } from '../../../main/ets/common/constants/BudgetConfig';
import { PaceOption, SelectedSpot, SpotPriority, TravelStyle, TransitPreference } from '../../../main/ets/model/PlanParams';

export default function planDraftTest(): void {
  describe('PlanDraft 草稿', () => {
    it('is_a_single_shared_instance', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      PlanDraft.fresh();
      const a: PlanDraft = PlanDraft.get();
      const b: PlanDraft = PlanDraft.get();
      // 跨页共享靠的就是同一个实例：这里必须比引用而不是比字段
      expect(a === b).assertTrue();
    });

    it('defaults_are_honest_placeholders', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      PlanDraft.fresh();
      const d: PlanDraft = PlanDraft.get();
      expect(d.basic.destination).assertEqual('北京');
      expect(d.basic.people).assertEqual(2);
      expect(d.basic.budget).assertEqual(BudgetConfig.DEFAULT);
      // 日期必须留空：写死字面量会让新装用户几个月后看到出发日在过去
      expect(d.basic.startDate).assertEqual('');
      expect(d.basic.endDate).assertEqual('');
      expect(d.style).assertEqual(TravelStyle.LEISURE);
      expect(d.transit).assertEqual(TransitPreference.PUBLIC);
      expect(d.paces.length).assertEqual(1);
      expect(d.paces[0]).assertEqual(PaceOption.STANDARD);
      expect(d.selectedSpots.length).assertEqual(0);
      expect(d.selectedArea.areaId).assertEqual('');
    });

    it('fresh_actually_clears_mutations', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      PlanDraft.fresh();
      const d: PlanDraft = PlanDraft.get();
      d.basic.destination = '京都';
      d.basic.startDate = '2026-07-01';
      d.paces = [PaceOption.RELAXED, PaceOption.PACKED];
      const pick: SelectedSpot = { spotId: 'spot-1', priority: SpotPriority.MUST };
      d.selectedSpots.push(pick);
      d.selectedArea.areaId = 'area-9';
      expect(PlanDraft.get().selectedSpots.length).assertEqual(1);

      PlanDraft.fresh();
      const after: PlanDraft = PlanDraft.get();
      expect(after.basic.destination).assertEqual('北京');
      expect(after.basic.startDate).assertEqual('');
      expect(after.paces.length).assertEqual(1);
      expect(after.selectedSpots.length).assertEqual(0);
      expect(after.selectedArea.areaId).assertEqual('');
    });
  });
}
