/**
 * 当日负载回归（纯逻辑）：屏8 吸顶日标题那条三态条的全部判断都在 DayLoadCalc 里，
 * 这里钉死「停留/通勤怎么累加」「三态边界」「小时文案」，避免以后改累加口径把
 * 「今天太挤」的阈值悄悄挪走。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { DayLoad, DayLoadCalc, LoadLevel } from '../../../main/ets/utils/DayLoad';
import { Activity, ActivityCategory, ActivityStatus, IntensityLevel, Meal, MealType,
  TransportInfo, TripDay } from '../../../main/ets/model/Trip';

function act(id: string, start: string, end: string, category: ActivityCategory,
  transport?: TransportInfo): Activity {
  return {
    id: id, time: start, endTime: end, title: id, location: id, address: '',
    longitude: 116.4, latitude: 39.9, status: ActivityStatus.NO_NEED,
    category: category, transport: transport
  };
}

function ride(minutes: number): TransportInfo {
  return { mode: '地铁', duration: minutes, detail: '2 站' };
}

function day(activities: Activity[]): TripDay {
  const meals: Meal[] = [{ type: MealType.LUNCH, name: '午餐', location: '附近', estimatedCost: 80 }];
  return {
    dayIndex: 1, date: '2026-11-01', theme: '主题', intensity: IntensityLevel.MEDIUM,
    dailyCost: 0, activities: activities, meals: meals
  };
}

export default function dayLoadTest(): void {
  describe('DayLoadCalc', () => {
    it('empty_day_is_zero', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const load: DayLoad = DayLoadCalc.of(day([]));
      expect(load.minutes).assertEqual(0);
      expect(load.level).assertEqual(LoadLevel.OK);
      // 没有数据时整行不出：文案给空串，宿主据此不渲染负载条
      expect(DayLoadCalc.label(load)).assertEqual('');
    });

    it('stay_plus_transit', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // 09:00-11:00 停留 120 + 到达该站的通勤 30 = 150 → 2.5h
      const load: DayLoad = DayLoadCalc.of(day([
        act('a', '09:00', '11:00', ActivityCategory.SIGHT, ride(30))
      ]));
      expect(load.stayMinutes).assertEqual(120);
      expect(load.transitMinutes).assertEqual(30);
      expect(load.minutes).assertEqual(150);
      expect(load.level).assertEqual(LoadLevel.OK);
      expect(DayLoadCalc.label(load)).assertEqual('活动 2.5h · 建议 ≤10h');
    });

    it('span_gap_is_not_counted', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // 上午两小时 + 晚上两小时：跨度 11h，但真正被占用的只有 4h——
      // 这正是「不按最后结束减最早开始算」的理由
      const load: DayLoad = DayLoadCalc.of(day([
        act('a', '09:00', '11:00', ActivityCategory.SIGHT),
        act('b', '18:00', '20:00', ActivityCategory.FOOD)
      ]));
      expect(load.minutes).assertEqual(240);
      expect(load.level).assertEqual(LoadLevel.OK);
    });

    it('warn_band_and_over_cap', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // 510 / 600 = 85% → 标黄
      const warn: DayLoad = DayLoadCalc.of(day([
        act('a', '09:00', '13:00', ActivityCategory.SIGHT),
        act('b', '14:00', '18:30', ActivityCategory.SIGHT)
      ]));
      expect(warn.minutes).assertEqual(510);
      expect(warn.level).assertEqual(LoadLevel.WARN);
      // 恰好 600 仍是「建议上限内」，超过 1 分钟才算超
      const edge: DayLoad = DayLoadCalc.of(day([act('c', '08:00', '18:00', ActivityCategory.SIGHT)]));
      expect(edge.minutes).assertEqual(600);
      expect(edge.level).assertEqual(LoadLevel.WARN);
      // 610 → 超载，读数要报「超了多少」
      const over: DayLoad = DayLoadCalc.of(day([
        act('d', '09:00', '12:00', ActivityCategory.SIGHT),
        act('e', '12:30', '18:00', ActivityCategory.SIGHT, ride(100))
      ]));
      expect(over.minutes).assertEqual(610);
      expect(over.level).assertEqual(LoadLevel.OVER);
      expect(DayLoadCalc.label(over)).assertEqual('活动 10.2h · 超建议 0.2h');
    });

    it('transport_node_counts_once', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // 交通节点本身就是一段路：节点时段与自带 duration 只能取其一，不能把同一条腿算两次
      const load: DayLoad = DayLoadCalc.of(day([
        act('t', '08:00', '09:30', ActivityCategory.TRANSPORT)
      ]));
      expect(load.stayMinutes).assertEqual(0);
      expect(load.transitMinutes).assertEqual(90);
      const both: DayLoad = DayLoadCalc.of(day([
        act('t', '08:00', '09:30', ActivityCategory.TRANSPORT, ride(20))
      ]));
      expect(both.transitMinutes).assertEqual(90);
      // 没有时段时才用自带 duration 兜底
      const durationOnly: DayLoad = DayLoadCalc.of(day([
        act('t', '', '', ActivityCategory.TRANSPORT, ride(20))
      ]));
      expect(durationOnly.transitMinutes).assertEqual(20);
    });

    it('bad_time_is_skipped', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // 旧数据里 time/endTime 可能是空串或倒挂：这类节点不能把总数算成负数
      const load: DayLoad = DayLoadCalc.of(day([
        act('a', '', '', ActivityCategory.SIGHT),
        act('b', '18:00', '09:00', ActivityCategory.SIGHT),
        act('c', '10:00', '11:00', ActivityCategory.SIGHT, ride(0))
      ]));
      expect(load.stayMinutes).assertEqual(60);
      expect(load.transitMinutes).assertEqual(0);
      expect(load.minutes).assertEqual(60);
    });

    it('hours_format', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      expect(DayLoadCalc.hours(390)).assertEqual('6.5');
      expect(DayLoadCalc.hours(600)).assertEqual('10');
      expect(DayLoadCalc.hours(642)).assertEqual('10.7');
      expect(DayLoadCalc.hours(0)).assertEqual('0');
      expect(DayLoadCalc.hours(-30)).assertEqual('0');
      // 0.1h = 6 分钟；2 分钟不足半档舍到 0，4 分钟进位到 0.1
      expect(DayLoadCalc.hours(2)).assertEqual('0');
      expect(DayLoadCalc.hours(4)).assertEqual('0.1');
    });
  });
}
