/**
 * 伴随助手核心逻辑离线断言：偏好降级 + 规划外到访请示引擎。
 * 被 tools/verify_companion_logic.sh 拷进临时目录后用 bundled tsc --strict 编译、
 * bundled node 运行，不依赖 @kit / 设备。
 */

import { Activity, ActivityCategory, ActivityStatus, IntensityLevel, TripDay } from '../model/Trip';
import { CompanionPrefs } from '../companion/CompanionPrefs';
import { CompanionEngine } from '../companion/CompanionEngine';
import { CompanionPrompt, UnplannedInput } from '../companion/CompanionTypes';

let cases = 0;

function ok(cond: boolean, msg: string): void {
  cases += 1;
  if (!cond) {
    throw new Error(`FAIL: ${msg}`);
  }
}

function eq(actual: string | number | boolean, expected: string | number | boolean, msg: string): void {
  cases += 1;
  if (actual !== expected) {
    throw new Error(`FAIL: ${msg}（actual=${actual} expected=${expected}）`);
  }
}

function act(id: string, time: string, endTime: string, cat: ActivityCategory): Activity {
  const a: Activity = {
    id: id, time: time, endTime: endTime, title: id, location: id, address: '',
    longitude: 0, latitude: 0, status: ActivityStatus.NO_NEED, category: cat
  };
  return a;
}

function dayOf(acts: Activity[]): TripDay {
  const d: TripDay = {
    dayIndex: 1, date: '2026-11-11', theme: '测试', intensity: IntensityLevel.MEDIUM,
    dailyCost: 0, activities: acts, meals: []
  };
  return d;
}

function input(recognized: boolean, estVisitMin: number, day: TripDay, nowMin: number): UnplannedInput {
  const u: UnplannedInput = {
    recognized: recognized, placeName: recognized ? '什刹海' : '', estVisitMin: estVisitMin,
    day: day, nowMin: nowMin
  };
  return u;
}

// —— 偏好降级 ——
const p1 = new CompanionPrefs();
eq(p1.modeFor('k'), 'ask', '初始请示');
p1.recordChoice('k', 'rec', 'rec');
p1.recordChoice('k', 'rec', 'rec');
eq(p1.modeFor('k'), 'ask', '两次仍请示');
p1.recordChoice('k', 'rec', 'rec');
eq(p1.modeFor('k'), 'notify', '三次降通知');
p1.correct('k');
eq(p1.modeFor('k'), 'ask', '纠正回请示');

const p2 = new CompanionPrefs();
p2.recordChoice('k', 'rec', 'rec');
p2.recordChoice('k', 'rec', 'rec');
p2.recordChoice('k', 'other', 'rec');
p2.recordChoice('k', 'rec', 'rec');
eq(p2.modeFor('k'), 'ask', '非推荐重置连续计数');

// —— 规划外到访 ——
const day = dayOf([act('next', '11:00', '12:00', ActivityCategory.SIGHT)]);

const unknown: CompanionPrompt | null = CompanionEngine.unplannedArrival(input(false, 60, day, 600), new CompanionPrefs());
ok(unknown !== null, '未识别应出轻问卡');
eq(unknown!.kind, 'unknown_place', '未识别种类');
eq(unknown!.stake, 'low', '未识别低风险');
ok(unknown!.options.length >= 2, '未识别至少两选项');

const silent: CompanionPrompt | null = CompanionEngine.unplannedArrival(input(true, 30, day, 600), new CompanionPrefs());
ok(silent === null, '无后果安静吸收');

const conflict: CompanionPrompt | null = CompanionEngine.unplannedArrival(input(true, 90, day, 600), new CompanionPrefs());
ok(conflict !== null, '有后果应出请示卡');
eq(conflict!.kind, 'unplanned_arrival', '到访种类');
eq(conflict!.options.length, 3, '三选项');
eq(conflict!.recommendedIndex, 0, '推荐第一项');
eq(conflict!.stake, 'low', '低风险');
eq(conflict!.options[0].action.kind, 'move_tomorrow', '推荐挪明天');
eq(conflict!.options[0].action.targetId, 'next', '挪明天目标节点');

const legDay = dayOf([
  act('leg', '10:30', '11:00', ActivityCategory.TRANSPORT),
  act('sight', '12:00', '13:00', ActivityCategory.SIGHT)
]);
const skipLeg: CompanionPrompt | null = CompanionEngine.unplannedArrival(input(true, 90, legDay, 600), new CompanionPrefs());
ok(skipLeg === null, '剔除交通腿后无后果');

const prefs3 = new CompanionPrefs();
prefs3.recordChoice('unplanned_move_tomorrow', 'move_tomorrow', 'move_tomorrow');
prefs3.recordChoice('unplanned_move_tomorrow', 'move_tomorrow', 'move_tomorrow');
prefs3.recordChoice('unplanned_move_tomorrow', 'move_tomorrow', 'move_tomorrow');
const degraded: CompanionPrompt | null = CompanionEngine.unplannedArrival(input(true, 90, day, 600), prefs3);
ok(degraded !== null, '降级后仍出卡');
eq(degraded!.mode, 'notify', '偏好降级为通知');

console.log(`COMPANION_CHECK_OK cases=${cases}`);