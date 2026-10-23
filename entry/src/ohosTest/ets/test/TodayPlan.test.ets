/**
 * 阶段 9 卡片数据回归：TodayPlan 纯函数 + DateUtils。
 * 纯逻辑不碰 @kit，可在 hypium 内跑（区别于 RDB/preferences 类断言只能真机验收）。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { TodayPlan, TodayPlanData } from '../../../main/ets/data/TodayPlan';
import { DateUtils } from '../../../main/ets/utils/DateUtils';
import { Activity, ActivityCategory, ActivityStatus, IntensityLevel, Trip, TripDay } from '../../../main/ets/model/Trip';

function act(id: string, time: string, title: string, status: ActivityStatus): Activity {
  const a: Activity = { id, time, endTime: time, title, location: 'L', address: 'A',
    longitude: 0, latitude: 0, status, category: ActivityCategory.SIGHT };
  return a;
}

function actCat(id: string, time: string, title: string, cat: ActivityCategory): Activity {
  const a: Activity = { id, time, endTime: time, title, location: 'L', address: 'A',
    longitude: 0, latitude: 0, status: ActivityStatus.NO_NEED, category: cat };
  return a;
}

function day(idx: number, date: string, acts: Activity[]): TripDay {
  const d: TripDay = { dayIndex: idx, date, theme: `主题${idx}`, intensity: IntensityLevel.MEDIUM,
    dailyCost: 0, activities: acts, meals: [] };
  return d;
}

function tripOf(days: TripDay[]): Trip {
  const t: Trip = { id: 't-1', destination: '北京', startDate: '2026-06-10', endDate: '2026-06-12',
    people: 2, budget: 8000, style: 'leisure',
    overview: { totalCost: 0, highlights: [], summary: '' }, days, tips: [] };
  return t;
}

function planOf(acts: Activity[], now: string): TodayPlanData | null {
  return TodayPlan.of(tripOf([day(1, '2026-06-11', acts)]), '2026-06-11', now);
}

export default function todayPlanTest(): void {
  describe('TodayPlan', () => {
    it('hit_today_title', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const p: TodayPlanData | null = planOf([act('a', '09:00', '故宫', ActivityStatus.NOT_BOOKED)], '08:00');
      expect(p !== null).assertTrue();
      expect(p === null ? '' : p.dayTitle).assertEqual('Day 1 · 6月11日');
      expect(p === null ? '' : p.tripId).assertEqual('t-1');
    });

    it('miss_or_empty_returns_null', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(TodayPlan.of(tripOf([day(1, '2026-06-10', [])]), '2026-06-11', '08:00') === null).assertTrue();
      expect(planOf([], '08:00') === null).assertTrue();
    });

    it('meta_counts_remaining_and_total', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const p: TodayPlanData | null = planOf([
        act('a', '09:00', 'A', ActivityStatus.NO_NEED), act('b', '11:00', 'B', ActivityStatus.NO_NEED),
        act('c', '15:00', 'C', ActivityStatus.NO_NEED)], '10:00');
      expect(p === null ? '' : p.meta).assertEqual('还剩 2 站 · 共 3 站');
    });

    it('rows_prefer_upcoming_max_three', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const p: TodayPlanData | null = planOf([
        act('a0', '09:00', 'A', ActivityStatus.NO_NEED), act('a1', '11:00', 'B', ActivityStatus.NO_NEED),
        act('a2', '13:00', 'C', ActivityStatus.NO_NEED), act('a3', '15:00', 'D', ActivityStatus.NO_NEED),
        act('a4', '17:00', 'E', ActivityStatus.NO_NEED)], '08:30');
      expect(p === null ? 0 : p.rows.length).assertEqual(3);
      expect(p === null ? '' : p.rows[2].time).assertEqual('13:00');
    });

    it('row_dot_follows_category_not_position', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      // 底稿屏13 那三行是按「景点 / 餐饮 / 住宿」着色的，实现原来按行序给色：
      // 第 2 行永远金色、第 3 行永远紫色，三个景点会被画成三种颜色
      const p: TodayPlanData | null = planOf([
        actCat('a', '09:00', '故宫', ActivityCategory.SIGHT),
        actCat('b', '12:30', '老通城', ActivityCategory.FOOD),
        actCat('c', '18:00', '住宿片区', ActivityCategory.HOTEL)], '08:00');
      expect(p === null ? 0 : p.rows.length).assertEqual(3);
      expect(p === null ? '' : p.rows[0].dot).assertEqual('primary');
      expect(p === null ? '' : p.rows[1].dot).assertEqual('bookmark');
      expect(p === null ? '' : p.rows[2].dot).assertEqual('accent_mention');
      const all: TodayPlanData | null = planOf([
        actCat('a', '09:00', '故宫', ActivityCategory.SIGHT),
        actCat('b', '11:00', '天坛', ActivityCategory.SIGHT)], '08:00');
      expect(all === null ? '' : all.rows[1].dot).assertEqual('primary');
    });

    it('rows_fallback_when_fewer_upcoming', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const p: TodayPlanData | null = planOf([
        act('a0', '09:00', 'A', ActivityStatus.NO_NEED), act('a1', '18:00', 'B', ActivityStatus.NO_NEED),
        act('a2', '19:00', 'C', ActivityStatus.NO_NEED), act('a3', '20:00', 'D', ActivityStatus.NO_NEED)], '18:30');
      expect(p === null ? 0 : p.rows.length).assertEqual(3);
      expect(p === null ? '' : p.rows[0].name).assertEqual('A');
    });

    it('footer_latest_pending_booking_time', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const p: TodayPlanData | null = planOf([
        act('a', '09:00', 'A', ActivityStatus.NOT_BOOKED), act('b', '10:00', 'B', ActivityStatus.NO_NEED),
        act('c', '16:20', 'C', ActivityStatus.PENDING), act('d', '14:00', 'D', ActivityStatus.FULL)], '13:00');
      expect(p === null ? '' : p.footer).assertEqual('还有 2 个需预约节点 · 16:20 前');
    });

    it('footer_all_bookings_started', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const p: TodayPlanData | null = planOf([
        act('a', '09:00', 'A', ActivityStatus.NOT_BOOKED), act('b', '10:00', 'B', ActivityStatus.PENDING)], '13:00');
      expect(p === null ? '' : p.footer).assertEqual('2 个预约节点已全部开始');
    });

    it('footer_booked_excluded_from_todo_tally', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const p: TodayPlanData | null = planOf([
        act('a', '09:00', 'A', ActivityStatus.BOOKED), act('b', '14:00', 'B', ActivityStatus.NOT_BOOKED)], '13:00');
      expect(p === null ? '' : p.footer).assertEqual('还有 1 个需预约节点 · 14:00 前');
    });

    it('footer_no_booking_needed', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const p: TodayPlanData | null = planOf([act('a', '09:00', 'A', ActivityStatus.NO_NEED)], '08:00');
      expect(p === null ? '' : p.footer).assertEqual('今日无需预约节点');
    });

    it('date_utils_iso_helpers', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(DateUtils.isValidIsoDate('2026-02-30')).assertTrue();
      expect(DateUtils.isValidIsoDate('2026-2-30')).assertFalse();
      expect(DateUtils.addDays('2026-01-30', 3)).assertEqual('2026-02-02');
      expect(DateUtils.addDays('bad', 3)).assertEqual('');
      expect(DateUtils.spanDays('2026-06-11', '2026-06-15')).assertEqual(5);
      expect(DateUtils.spanDays('x', 'y')).assertEqual(1);
    });
  });
}
