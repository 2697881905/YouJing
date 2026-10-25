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
  'r1t', 'r1n', 'r1c', 'r2t', 'r2n', 'r2c', 'r3t', 'r3n', 'r3c', 'tripId'
];

const PLAN: TodayPlanData = {
  tripId: 'trip-1',
  dayTitle: 'Day 1 · 6月11日',
  meta: '还剩 2 站 · 共 3 站',
  footer: '还有 1 个需预约节点 · 14:00 前',
  rows: [
    { time: '09:00', name: '故宫', dot: 'primary' },
    { time: '13:15', name: '午饭', dot: 'bookmark' }
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
  });
}
