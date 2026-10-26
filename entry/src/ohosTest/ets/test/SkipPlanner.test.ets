/**
 * 跳过/重排纯逻辑回归（方案 §3.3 / §3.5）。
 * 与 tools/skip_planner_check.ts 同源；这里跑真机 hypium 侧，不碰 @kit / RDB。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import {
  Activity, ActivityCategory, ActivityStatus, IntensityLevel, Meal, MealType, TransportInfo, TripDay
} from '../../../main/ets/model/Trip';
import {
  FreeBlock, KeepStop, ReplanDecision, ReplanOutcome, ReplanRequest
} from '../../../main/ets/model/Replan';
import { SkipPlanner } from '../../../main/ets/data/SkipPlanner';
import { DateUtils } from '../../../main/ets/utils/DateUtils';

function act(id: string, time: string, endTime: string, title: string,
  category: ActivityCategory = ActivityCategory.SIGHT,
  status: ActivityStatus = ActivityStatus.NOT_BOOKED,
  transportMin: number = 0): Activity {
  const a: Activity = {
    id: id, time: time, endTime: endTime, title: title, location: 'loc', address: 'addr',
    longitude: 1, latitude: 2, status: status, category: category
  };
  if (transportMin > 0) {
    const t: TransportInfo = { mode: '步行', duration: transportMin, detail: '' };
    a.transport = t;
  }
  return a;
}

function meal(type: MealType, time?: string): Meal {
  const m: Meal = { type: type, name: 'meal', location: 'loc', estimatedCost: 0 };
  if (time !== undefined) {
    m.time = time;
  }
  return m;
}

function dayOf(acts: Activity[], meals: Meal[]): TripDay {
  const d: TripDay = {
    dayIndex: 1, date: '2026-10-26', theme: 't', intensity: IntensityLevel.LOW,
    dailyCost: 0, activities: acts, meals: meals
  };
  return d;
}

function keepOf(id: string, dwellMin: number): KeepStop {
  const k: KeepStop = { id: id, dwellMin: dwellMin };
  return k;
}

function blockOf(afterId: string, minutes: number): FreeBlock {
  const b: FreeBlock = { afterId: afterId, minutes: minutes };
  return b;
}

function decisionOf(keep: KeepStop[], blocks: FreeBlock[], note: string): ReplanDecision {
  const d: ReplanDecision = { schemaVersion: 1, keep: keep, freeBlocks: blocks, note: note };
  return d;
}

function find(day: TripDay, id: string): Activity {
  for (const a of day.activities) {
    if (a.id === id) {
      return a;
    }
  }
  throw new Error(`missing activity ${id}`);
}

/** now=14:05；a2 是可跳过的下一站；a5 是已预约锚点；两餐是餐次锚点 */
function mainDay(): TripDay {
  return dayOf([
    act('a1', '09:00', '10:00', '早饭散步'),
    act('a2', '14:00', '15:00', '清水寺'),
    act('a3', '15:30', '16:30', '二年坂', ActivityCategory.SIGHT, ActivityStatus.NOT_BOOKED, 10),
    act('a4', '16:45', '17:30', '锦市场', ActivityCategory.SHOP, ActivityStatus.NO_NEED, 5),
    act('a5', '19:00', '20:00', '夜景', ActivityCategory.SIGHT, ActivityStatus.BOOKED)
  ], [meal(MealType.LUNCH, '12:00'), meal(MealType.DINNER, '18:00')]);
}

export default function skipPlannerTest(): void {
  describe('SkipPlanner', () => {
    it('date_time_primitives', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(DateUtils.minutesOf('00:00')).assertEqual(0);
      expect(DateUtils.minutesOf('23:59')).assertEqual(1439);
      expect(DateUtils.minutesOf('24:00')).assertEqual(-1);
      expect(DateUtils.minutesOf('9:00')).assertEqual(-1);
      expect(DateUtils.hhmmOf(1439)).assertEqual('23:59');
      expect(DateUtils.hhmmOf(1440)).assertEqual('23:59');
    });

    it('skippable_gate', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(SkipPlanner.isSkippable(ActivityCategory.SIGHT, ActivityStatus.NOT_BOOKED)).assertTrue();
      expect(SkipPlanner.isSkippable(ActivityCategory.SIGHT, ActivityStatus.BOOKED)).assertFalse();
      expect(SkipPlanner.isSkippable(ActivityCategory.TRANSPORT, ActivityStatus.NO_NEED)).assertFalse();
      expect(SkipPlanner.isSkippable(ActivityCategory.HOTEL, ActivityStatus.NO_NEED)).assertFalse();
      expect(SkipPlanner.isSkippable(ActivityCategory.REST, ActivityStatus.NO_NEED)).assertFalse();
      expect(SkipPlanner.isSkippable(null, ActivityStatus.NO_NEED)).assertFalse();
    });

    it('remaining_includes_rest', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(SkipPlanner.remainingIds(mainDay(), 'a2', 845).join(',')).assertEqual('a3,a4');
      const restDay: TripDay = dayOf([
        act('a2', '14:00', '15:00', '可跳过'),
        act('r1', '15:10', '15:40', '休息', ActivityCategory.REST, ActivityStatus.NO_NEED)
      ], []);
      expect(SkipPlanner.remainingIds(restDay, 'a2', 845).join(',')).assertEqual('r1');
    });

    it('valid_decision_reorders_and_keeps_anchors',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
        const outcome: ReplanOutcome = SkipPlanner.plan(mainDay(), 'a2', 845,
          decisionOf([keepOf('a4', 40), keepOf('a3', 60)], [], '下午节奏放缓'));
        expect(outcome.usedFallback).assertFalse();
        const out: TripDay = outcome.day;
        expect(find(out, 'a2').category).assertEqual(ActivityCategory.REST);
        expect(find(out, 'a2').title).assertEqual('空闲');
        expect(find(out, 'a2').status).assertEqual(ActivityStatus.NO_NEED);
        expect(find(out, 'a2').note ?? '').assertEqual('已跳过：清水寺');
        expect(find(out, 'a2').time).assertEqual('14:00');
        expect(find(out, 'a2').endTime).assertEqual('15:00');
        expect(find(out, 'a4').time).assertEqual('15:05');
        expect(find(out, 'a4').endTime).assertEqual('15:45');
        expect(find(out, 'a3').time).assertEqual('15:55');
        expect(find(out, 'a3').endTime).assertEqual('16:55');
        expect(find(out, 'a5').time).assertEqual('19:00');
        expect(out.activities.map((a: Activity): string => a.id).join(',')).assertEqual('a1,a2,a3,a4,a5');
        expect(outcome.note.indexOf('下午节奏放缓') >= 0).assertTrue();
      });

    // keep 必须覆盖全部剩余站点（a3、a4），少一项会被守卫判非法走兜底
    it('free_block_after_skipped_applies', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const r: ReplanOutcome = SkipPlanner.plan(mainDay(), 'a2', 845,
        decisionOf([keepOf('a3', 60), keepOf('a4', 40)], [blockOf('a2', 30)], ''));
      expect(r.usedFallback).assertFalse();
      expect(find(r.day, 'a3').time).assertEqual('15:40');
    });

    it('free_block_already_passed_ignored', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const r: ReplanOutcome = SkipPlanner.plan(mainDay(), 'a2', 845,
        decisionOf([keepOf('a3', 60), keepOf('a4', 40)], [blockOf('a1', 30)], ''));
      expect(find(r.day, 'a3').time).assertEqual('15:10');
    });

    it('free_block_after_kept_stop_applies', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const r: ReplanOutcome = SkipPlanner.plan(mainDay(), 'a2', 845,
        decisionOf([keepOf('a3', 60), keepOf('a4', 40)], [blockOf('a3', 20)], ''));
      expect(r.usedFallback).assertFalse();
      expect(find(r.day, 'a3').time).assertEqual('15:10');
      expect(find(r.day, 'a4').time).assertEqual('16:35');
    });

    it('anchor_crossing_moves_to_anchor_end', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const crossDay: TripDay = dayOf([
        act('a2', '17:00', '17:30', '可跳过'),
        act('a3', '18:30', '19:30', '下一站')
      ], [meal(MealType.DINNER, '18:00')]);
      const r: ReplanOutcome = SkipPlanner.plan(crossDay, 'a2', 1020,
        decisionOf([keepOf('a3', 120)], [], ''));
      expect(find(r.day, 'a3').time).assertEqual('19:00');
    });

    it('overflow_marks_carry_stops', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const lateDay: TripDay = dayOf([
        act('a2', '21:30', '22:00', '夜游'),
        act('a3', '22:10', '22:40', '塔'),
        act('a4', '22:50', '23:20', '桥')
      ], []);
      const r: ReplanOutcome = SkipPlanner.plan(lateDay, 'a2', 1320,
        decisionOf([keepOf('a3', 60), keepOf('a4', 60)], [], ''));
      expect(r.usedFallback).assertFalse();
      expect(find(r.day, 'a3').time).assertEqual('22:00');
      expect(find(r.day, 'a4').time).assertEqual('22:50');
      expect((find(r.day, 'a4').note ?? '').indexOf('待调整') >= 0).assertTrue();
      expect(r.note.indexOf('部分站点待调整') >= 0).assertTrue();
    });

    it('invalid_decision_falls_back', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const rejects: ReplanDecision[] = [
        decisionOf([keepOf('a3', 60)], [], ''),
        decisionOf([keepOf('a3', 60), keepOf('a4', 40), keepOf('a1', 30)], [], ''),
        decisionOf([keepOf('a3', 60), keepOf('a3', 60)], [], ''),
        decisionOf([keepOf('a3', 10), keepOf('a4', 40)], [], ''),
        decisionOf([keepOf('a3', 241), keepOf('a4', 40)], [], ''),
        decisionOf([keepOf('a3', 60), keepOf('a4', 40)], [blockOf('a3', 10)], ''),
        decisionOf([keepOf('a3', 60), keepOf('a4', 40)], [blockOf('zz', 30)], ''),
        decisionOf([keepOf('a3', 60), keepOf('a4', 40)], [], 'x'.repeat(201))
      ];
      for (let i = 0; i < rejects.length; i++) {
        const r: ReplanOutcome = SkipPlanner.plan(mainDay(), 'a2', 845, rejects[i]);
        expect(r.usedFallback).assertTrue();
        expect(find(r.day, 'a2').title).assertEqual('空闲');
      }
      const schema2: ReplanDecision = {
        schemaVersion: 2, keep: [keepOf('a3', 60), keepOf('a4', 40)], freeBlocks: [], note: ''
      };
      expect(SkipPlanner.plan(mainDay(), 'a2', 845, schema2).usedFallback).assertTrue();
    });

    it('local_fallback_shifts_past_anchors', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const r: ReplanOutcome = SkipPlanner.plan(mainDay(), 'a2', 845, null);
      expect(r.usedFallback).assertTrue();
      expect(find(r.day, 'a3').time).assertEqual('20:00');
      expect(find(r.day, 'a4').time).assertEqual('21:15');
      expect(r.note.indexOf('离线重排') >= 0).assertTrue();

      const lateFb: ReplanOutcome = SkipPlanner.plan(dayOf([
        act('a2', '22:30', '23:00', '夜游'),
        act('a3', '23:10', '23:40', '塔'),
        act('a4', '23:45', '23:59', '桥')
      ], []), 'a2', 1380, null);
      expect(lateFb.usedFallback).assertTrue();
      expect(find(lateFb.day, 'a3').time).assertEqual('23:10');
      expect((find(lateFb.day, 'a3').note ?? '').indexOf('待调整') >= 0).assertTrue();
      expect(lateFb.note.indexOf('部分站点待调整') >= 0).assertTrue();
    });

    it('request_whole_day_and_clone_deep', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const req: ReplanRequest = SkipPlanner.buildRequest(mainDay(), 'a2', 845);
      expect(req.schemaVersion).assertEqual(1);
      expect(req.now).assertEqual('14:05');
      expect(req.day.activities.length).assertEqual(5);
      expect(req.day.meals.length).assertEqual(2);
      expect(req.day.activities[2].transport?.duration ?? -1).assertEqual(10);
      expect(req.day.meals[0].time ?? '').assertEqual('12:00');
      const rawFirst: string = JSON.stringify(req.day.activities[0]);
      expect(rawFirst.indexOf('"note"') < 0 && rawFirst.indexOf('"reason"') < 0).assertTrue();

      const original: TripDay = mainDay();
      const clone: TripDay = SkipPlanner.cloneDay(original);
      clone.activities[2].title = '改名';
      if (clone.activities[2].transport !== undefined) {
        clone.activities[2].transport.duration = 99;
      }
      expect(find(original, 'a3').title).assertEqual('二年坂');
      expect(find(original, 'a3').transport?.duration ?? -1).assertEqual(10);
    });
  });
}
