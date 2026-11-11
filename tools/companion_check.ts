/**
 * 伴随助手核心逻辑离线断言：偏好降级 + 规划外到访请示引擎。
 * 被 tools/verify_companion_logic.sh 拷进临时目录后用 bundled tsc --strict 编译、
 * bundled node 运行，不依赖 @kit / 设备。
 */

import { Activity, ActivityCategory, ActivityStatus, IntensityLevel, Trip, TripDay, TripOverview } from '../model/Trip';
import { Spot } from '../model/Spot';
import { GeoPoint } from '../utils/Geo';
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

// —— 规划外地点识别 ——
function spot(id: string, name: string, lat: number, lng: number, dur: number): Spot {
  const s: Spot = {
    id: id, name: name, city: '北京', tags: [], brief: '', suggestedDuration: dur,
    popularity: 0, nearbySpotIds: [], longitude: lng, latitude: lat,
    district: '', nearestMetro: '', booking: { requiresBooking: false },
    provenance: { source: 'test', updatedAt: '2026-11-11' }
  };
  return s;
}
function pt(lat: number, lng: number): GeoPoint {
  const p: GeoPoint = { latitude: lat, longitude: lng };
  return p;
}
const farDay = dayOf([act('plan', '11:00', '12:00', ActivityCategory.SIGHT)]);
farDay.activities[0].latitude = 34.5;
farDay.activities[0].longitude = 108.5;
const spots: Spot[] = [spot('s1', '什刹海', 34.27, 108.07, 90)];

const det = CompanionEngine.detectUnplanned(pt(34.27, 108.07), farDay, spots, 600, 5);
ok(det !== null, '停够识别规划外景点');
eq(det!.placeName, '什刹海', '识别地点名');
eq(det!.estVisitMin, 90, '游览时长取自景点');
ok(CompanionEngine.detectUnplanned(pt(34.27, 108.07), farDay, spots, 600, 1) === null, '路过不算');
ok(CompanionEngine.detectUnplanned(pt(35.0, 109.0), farDay, spots, 600, 5) === null, '无已知景点不报');

const planDay = dayOf([act('plan', '11:00', '12:00', ActivityCategory.SIGHT)]);
planDay.activities[0].latitude = 34.27;
planDay.activities[0].longitude = 108.07;
ok(CompanionEngine.detectUnplanned(pt(34.27, 108.07), planDay, spots, 600, 5) === null, '计划内到站不报');

// —— 跨天挪移 ——
function tripOf(days: TripDay[]): Trip {
  const ov: TripOverview = { totalCost: 0, highlights: [], summary: '' };
  const t: Trip = {
    id: 't1', destination: '北京', startDate: '2026-11-11', endDate: '2026-11-12',
    people: 2, budget: 5000, style: 'leisure', overview: ov, days: days, tips: []
  };
  return t;
}
const md1 = dayOf([act('a', '09:00', '10:00', ActivityCategory.SIGHT), act('b', '11:00', '12:00', ActivityCategory.SIGHT)]);
const md2 = dayOf([act('c', '09:00', '10:00', ActivityCategory.SIGHT)]);
md2.dayIndex = 2;
const mtrip = tripOf([md1, md2]);
const moved = CompanionEngine.moveToTomorrow(mtrip, 0, 'b');
ok(moved !== null, '挪移成功');
eq(moved!.days[0].activities.length, 1, '今日剩 1');
eq(moved!.days[1].activities.length, 2, '明日变 2');
eq(moved!.days[1].activities[1].id, 'b', 'b 挪到明日');
eq(mtrip.days[0].activities.length, 2, '原对象不变');
ok(CompanionEngine.moveToTomorrow(tripOf([md1]), 0, 'a') === null, '无明天返回 null');

console.log(`COMPANION_CHECK_OK cases=${cases}`);