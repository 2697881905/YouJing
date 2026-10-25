/**
 * 卡片数据映射回归：TodayCard 的 emptyCardData / toCardData 是纯 Record 映射，
 * 14 个键必须与 TodayTripCard 的 13+1 个 @LocalStorageProp 严格对齐——
 * 错一个键卡片静默不刷新（此前无任何测试在守）。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { DIM_KEY_2X2, DIM_KEY_2X4, emptyCardData, toCardData } from '../../../main/ets/widget/TodayCard';
import { TodayPlanData } from '../../../main/ets/data/TodayPlan';

/** TodayTripCard 的 @LocalStorageProp 键全集（漏一个这里就红） */
const CARD_KEYS: string[] = [
  'dayTitle', 'meta', 'footer', 'dimension',
  'r1t', 'r1n', 'r1c', 'r2t', 'r2n', 'r2c', 'r3t', 'r3n', 'r3c',
  'r4t', 'r4n', 'r4c', 'stopTotal', 'stopCurrent', 'stopBooking', 'tripId'
];

const PLAN: TodayPlanData = {
  tripId: 'trip-1',
  dayTitle: 'Day 1 · 6月11日',
  meta: '还剩 2 站 · 共 3 站',
  footer: '还有 1 个需预约节点 · 14:00 前',
  stopTotal: 3,
  stopCurrent: 1,
  stopBooking: 3,
  rows: [
    { time: '09:00', name: '故宫', dot: 'primary' },
    { time: '13:15', name: '午饭', dot: 'bookmark' }
  ]
};

/** 五站、四行都占满的行程：用来验 2×4 用满四行、2×2 只截三行且不画站点条 */
const PLAN4: TodayPlanData = {
  tripId: 'trip-4',
  dayTitle: 'Day 2 · 6月12日',
  meta: '还剩 4 站 · 共 5 站',
  footer: '还有 2 个需预约节点 · 18:00 前',
  stopTotal: 5,
  stopCurrent: 2,
  stopBooking: 4,
  rows: [
    { time: '09:00', name: 'A', dot: 'primary' },
    { time: '11:00', name: 'B', dot: 'primary' },
    { time: '13:00', name: 'C', dot: 'bookmark' },
    { time: '15:00', name: 'D', dot: 'accent_mention' }
  ]
};

export default function todayCardTest(): void {
  describe('TodayCard 映射', () => {
    it('empty_card_keys_match_widget', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const data: Record<string, string> = emptyCardData(DIM_KEY_2X2);
      expect(Object.keys(data).length).assertEqual(CARD_KEYS.length);
      for (const k of CARD_KEYS) {
        expect(data[k] === undefined).assertFalse();
      }
      expect(data['dayTitle']).assertEqual('今天没有行程安排');
      expect(data['tripId']).assertEqual('');
      expect(data['dimension']).assertEqual('2*2');
    });

    it('to_card_fills_rows_and_meta', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const data: Record<string, string> = toCardData(PLAN, DIM_KEY_2X4);
      expect(Object.keys(data).length).assertEqual(CARD_KEYS.length);
      expect(data['dayTitle']).assertEqual('Day 1 · 6月11日');
      expect(data['meta']).assertEqual('还剩 2 站 · 共 3 站');
      expect(data['footer']).assertEqual('还有 1 个需预约节点 · 14:00 前');
      expect(data['r1t']).assertEqual('09:00');
      expect(data['r1n']).assertEqual('故宫');
      expect(data['r1c']).assertEqual('primary');
      expect(data['r2n']).assertEqual('午饭');
      // 第三行没有数据：留空槽，不占行
      expect(data['r3n']).assertEqual('');
      expect(data['tripId']).assertEqual('trip-1');
      expect(data['dimension']).assertEqual('2*4');
    });

    it('wide_card_carries_fourth_row_and_strip', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const data: Record<string, string> = toCardData(PLAN4, DIM_KEY_2X4);
      expect(data['r4t']).assertEqual('15:00');
      expect(data['r4n']).assertEqual('D');
      expect(data['r4c']).assertEqual('accent_mention');
      expect(data['stopTotal']).assertEqual('5');
      expect(data['stopCurrent']).assertEqual('2');
      expect(data['stopBooking']).assertEqual('4');
    });

    it('small_card_truncates_to_three_rows_and_hides_strip', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // 帧 Widget A 只有三行、没有站点条：第四行与三个站点键必须留空串而不是不写，
      // 否则切档时卡片会留着上一档（2×4）的旧值
      const data: Record<string, string> = toCardData(PLAN4, DIM_KEY_2X2);
      expect(data['r3n']).assertEqual('C');
      expect(data['r4t']).assertEqual('');
      expect(data['r4n']).assertEqual('');
      expect(data['stopTotal']).assertEqual('');
      expect(data['stopCurrent']).assertEqual('');
      expect(data['stopBooking']).assertEqual('');
      expect(Object.keys(data).length).assertEqual(CARD_KEYS.length);
    });
  });
}
