/**
 * 规划草稿状态机回归（data/PlanDraft）。
 * 这里守的是真机复现过的缺陷：原来只有实例方法 reset() 且从未被调用，
 * 连着规划第二段行程时上一段的 selectedSpots / selectedArea / 节奏会静默带进来。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { PlanDraft, PlanDraftSnapshot } from '../../../main/ets/data/PlanDraft';
import { BudgetConfig } from '../../../main/ets/common/constants/BudgetConfig';
import { PaceOption, SelectedSpot, SpotPriority, TravelStyle, TransitPreference, TripBasicInput } from '../../../main/ets/model/PlanParams';

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

    it('days_of_unfilled_pair_uses_screen_two_default', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      // 空日期不是「1 天」：屏2 显示的是「今天起算 3 天」，屏5 的名额必须同一个口径
      // （2026-11-05 真机实拍到屏2 写 3天2晚、屏5 按 1 天只给 4 个名额）
      PlanDraft.fresh();
      const d: PlanDraft = PlanDraft.get();
      expect(d.basic.startDate).assertEqual('');
      expect(PlanDraft.days(d.basic)).assertEqual(PlanDraft.DEFAULT_DAYS);
      expect(PlanDraft.days(d.basic)).assertEqual(3);
    });

    it('inverted_pair_is_repaired_to_same_day', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      // 深链逐字段写入会留下 end < start；反向区间不是一种用户意图，读出来必须是同日
      PlanDraft.fresh();
      const d: PlanDraft = PlanDraft.get();
      const bad: TripBasicInput = {
        destination: d.basic.destination, startDate: '2026-12-20',
        endDate: '2026-10-22', people: d.basic.people, budget: d.basic.budget
      };
      d.basic = bad;
      const back: TripBasicInput = PlanDraft.get().basic;
      expect(back.startDate).assertEqual('2026-12-20');
      expect(back.endDate).assertEqual('2026-12-20');
      expect(PlanDraft.days(back)).assertEqual(1);
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

    it('snapshot_json_roundtrip_keeps_all_seven_fields', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // IMP-01 落盘形态：JSON 往返后七字段逐一不变，水合校验必须放行
      PlanDraft.fresh();
      const d: PlanDraft = PlanDraft.get();
      const basic: TripBasicInput = {
        destination: '杨凌', startDate: '2026-11-11', endDate: '2026-11-13', people: 3, budget: 4000
      };
      d.basic = basic;
      d.style = TravelStyle.FOODIE;
      d.stayTier = 'budget';
      d.transit = TransitPreference.TAXI_MAIN;
      d.paces = [PaceOption.RELAXED];
      const pick: SelectedSpot = { spotId: 'spot-9', priority: SpotPriority.WANT };
      d.selectedSpots = [pick];
      d.selectedArea = { areaId: 'area-3' };

      const back: PlanDraftSnapshot =
        JSON.parse(JSON.stringify(PlanDraft.toSnapshot(d))) as PlanDraftSnapshot;
      expect(PlanDraft.validSnapshot(back)).assertTrue();
      expect(back.basic.destination).assertEqual('杨凌');
      expect(back.basic.startDate).assertEqual('2026-11-11');
      expect(back.basic.endDate).assertEqual('2026-11-13');
      expect(back.basic.people).assertEqual(3);
      expect(back.basic.budget).assertEqual(4000);
      expect(back.style).assertEqual(TravelStyle.FOODIE);
      expect(back.stayTier).assertEqual('budget');
      expect(back.transit).assertEqual(TransitPreference.TAXI_MAIN);
      expect(back.paces[0]).assertEqual(PaceOption.RELAXED);
      expect(back.selectedSpots[0].spotId).assertEqual('spot-9');
      expect(back.selectedArea.areaId).assertEqual('area-3');
    });

    it('snapshot_validation_rejects_broken_shapes', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // 盘上旧版/坏 JSON 一律拒收，按默认档起（fail-closed，不能拿半个草稿进生成链）
      const noBasic: PlanDraftSnapshot = JSON.parse('{"stayTier":"comfort"}') as PlanDraftSnapshot;
      expect(PlanDraft.validSnapshot(noBasic)).assertFalse();
      const badCity: PlanDraftSnapshot =
        JSON.parse('{"basic":{"destination":1,"startDate":"","endDate":"","people":2,"budget":3000},' +
          '"stayTier":"comfort","paces":[],"selectedSpots":[],"selectedArea":{"areaId":""}}') as PlanDraftSnapshot;
      expect(PlanDraft.validSnapshot(badCity)).assertFalse();
    });
  });
}
