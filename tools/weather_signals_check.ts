/**
 * 切片 3 离线断言：天气解析/简报 + 三信号阈值与优先级 + 顺延排程。
 * 被 tools/verify_weather_logic.sh 拷进临时目录后用 bundled tsc --strict 编译、
 * bundled node 运行，不依赖 @kit / 设备。
 */

import {
  Activity, ActivityCategory, ActivityStatus, IntensityLevel, Meal, MealType, TripDay
} from '../model/Trip';
import { WeatherDay, WeatherHour } from '../model/Weather';
import { WeatherParser } from '../common/weather/WeatherParser';
import { AppError } from '../common/error/AppError';
import { ErrorCode } from '../common/error/ErrorCode';
import { WeatherAdvisor } from '../data/WeatherAdvisor';
import { SignalAction, SignalContext, SignalKind, TripSignals, TripSuggestion } from '../data/TripSignals';
import { SkipPlanner } from '../data/SkipPlanner';
import { DateUtils } from '../utils/DateUtils';
import { Geo, GeoPoint } from '../utils/Geo';
import { NodeOwe, OweItem } from '../utils/NodeOwe';

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

function act(id: string, time: string, endTime: string, title: string,
  category: ActivityCategory = ActivityCategory.SIGHT,
  status: ActivityStatus = ActivityStatus.NOT_BOOKED,
  lat: number = 34.27, lng: number = 108.07): Activity {
  const a: Activity = {
    id: id, time: time, endTime: endTime, title: title, location: 'loc', address: 'addr',
    longitude: lng, latitude: lat, status: status, category: category
  };
  return a;
}

function marker(id: string, time: string, endTime: string): Activity {
  const a: Activity = act(id, time, endTime, '空闲', ActivityCategory.REST, ActivityStatus.NO_NEED);
  a.note = '已跳过：某站';
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
    dayIndex: 1, date: '2026-10-30', theme: 't', intensity: IntensityLevel.LOW,
    dailyCost: 0, activities: acts, meals: meals
  };
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

function hoursOf(specs: number[][]): WeatherHour[] {
  const out: WeatherHour[] = [];
  for (const s of specs) {
    const h: WeatherHour = { startMin: s[0], code: s[1], tempC: s[2], rainProb: s[3] };
    out.push(h);
  }
  return out;
}

function weatherOf(rainProb: number): WeatherDay {
  const d: WeatherDay = {
    date: '2026-10-30', code: 61, tempMax: 21, tempMin: 12, rainMax: rainProb,
    hours: hoursOf([
      [0, 61, 16, rainProb],
      [900, 61, 18, rainProb],
      [960, 61, 17, rainProb]
    ])
  };
  return d;
}

/**
 * 三张信号用日程表的公共前缀（a0 09:00 / a2 14:00 / a3 15:30 / a4 19:00）。
 * ctxOf 用屏15 同一套 NodeOwe.indexOf 反推「你欠着哪一站」再传给信号，
 * 测试侧不再自己猜节点。
 */
const FIXTURE_ITEMS: OweItem[] = [
  item('a0', 540), item('a2', 840), item('a3', 930), item('a4', 1140)
];

function ctxOf(nowMin: number, fix: GeoPoint | null, checked: string[],
  weather: WeatherDay | null): SignalContext {
  const i: number = NodeOwe.indexOf(FIXTURE_ITEMS, checked, nowMin);
  const c: SignalContext = {
    isToday: true, nowMin: nowMin, fix: fix, checkedIds: checked,
    currentKey: i >= 0 ? FIXTURE_ITEMS[i].key : '', weather: weather
  };
  return c;
}

// ---------------- 天气简报 ----------------

eq(WeatherAdvisor.label(0), '晴', 'WMO 0 晴');
eq(WeatherAdvisor.label(1), '晴间多云', 'WMO 1 晴间多云');
eq(WeatherAdvisor.label(3), '阴', 'WMO 3 阴');
eq(WeatherAdvisor.label(45), '雾', 'WMO 45 雾');
eq(WeatherAdvisor.label(51), '毛毛雨', 'WMO 51 毛毛雨');
eq(WeatherAdvisor.label(61), '雨', 'WMO 61 雨');
eq(WeatherAdvisor.label(66), '冻雨', 'WMO 66 冻雨');
eq(WeatherAdvisor.label(71), '雪', 'WMO 71 雪');
eq(WeatherAdvisor.label(80), '阵雨', 'WMO 80 阵雨');
eq(WeatherAdvisor.label(85), '阵雪', 'WMO 85 阵雪');
eq(WeatherAdvisor.label(95), '雷阵雨', 'WMO 95 雷阵雨');
eq(WeatherAdvisor.label(4), '多云', 'WMO 未知码回退多云');

const wd: WeatherDay = {
  date: '2026-10-30', code: 61, tempMax: 21, tempMin: 12, rainMax: 70,
  hours: hoursOf([[0, 61, 16, 0], [900, 61, 18, 65], [960, 61, 17, 70]])
};
const brief = WeatherAdvisor.brief(wd);
eq(brief.text, '今日 21°/12° 雨 · 降水 70%', '天气简报主行');
eq(brief.advice, '15:00 后降水 65%', '有雨时给降水窗口');
eq(WeatherAdvisor.firstRain(wd, 0)?.startMin ?? -1, 900, '首个达标降水小时');
eq(WeatherAdvisor.firstRain(wd, 960)?.startMin ?? -1, 960, '从 16:00 起第一个达标小时');
eq(WeatherAdvisor.rainIn(wd, 930, 990), 70, '窗口跨 15/16 点取最大值');
eq(WeatherAdvisor.rainIn(wd, 0, 60), 0, '窗口覆盖 0 点取 0 点值');
eq(WeatherAdvisor.rainIn(wd, 60, 120), -1, '窗口无覆盖返回 -1');

const dry: WeatherDay = {
  date: '2026-10-30', code: 0, tempMax: 35, tempMin: 20, rainMax: 5,
  hours: hoursOf([[0, 0, 30, 5]])
};
eq(WeatherAdvisor.brief(dry).advice, '高温 35°，午间少排室外', '无雨高温给高温提示');
const cold: WeatherDay = {
  date: '2026-10-30', code: 0, tempMax: 4, tempMin: -2, rainMax: 0,
  hours: hoursOf([[0, 0, 0, 0]])
};
eq(WeatherAdvisor.brief(cold).advice, '最低 -2°，注意保暖', '无雨低温给保暖提示');
eq(WeatherAdvisor.brief(cold).text, '今日 4°/-2° 晴 · 降水 0%', '低温简报主行');

// ---------------- 天气解析 ----------------

const weatherJson: string = JSON.stringify({
  daily: {
    time: ['2026-10-29', '2026-10-30'],
    weather_code: [3, 61],
    temperature_2m_max: [19, 21],
    temperature_2m_min: [10, 12],
    precipitation_probability_max: [10, 70]
  },
  hourly: {
    time: ['2026-10-29T15:00', '2026-10-30T15:00', '2026-10-30T16:00', '2026-10-30T17:00',
      '2026-10-31T00:00'],
    weather_code: [3, 61, 61, 61, 3],
    temperature_2m: [17, 18, 17, 16, 15],
    precipitation_probability: [5, 65, 70, null, 80]
  }
});

const parsed: WeatherDay = WeatherParser.parse(weatherJson, '2026-10-30');
eq(parsed.date, '2026-10-30', '解析按 todayIso 选当日');
eq(parsed.code, 61, '解析当日天气码');
eq(parsed.tempMax, 21, '解析当日最高温');
eq(parsed.tempMin, 12, '解析当日最低温');
eq(parsed.rainMax, 70, '解析当日最大降水概率');
eq(parsed.hours.length, 3, '小时序列只留当日');
eq(parsed.hours[0].startMin, 900, '小时序列起始分钟');
eq(parsed.hours[1].rainProb, 70, '小时降水概率');
eq(parsed.hours[2].rainProb, -1, '缺测降水记 -1 而不是 0');

const fallbackDay: WeatherDay = WeatherParser.parse(weatherJson, '2026-01-01');
eq(fallbackDay.date, '2026-10-29', 'todayIso 不在 daily 时退回第一条');
eq(fallbackDay.hours.length, 1, '退回第一条后同样过滤小时');

function codeOf(fn: () => Object): number {
  try {
    fn();
  } catch (e) {
    return (e as AppError).code;
  }
  return -1;
}

eq(codeOf((): Object => WeatherParser.parse('not json', '')), ErrorCode.JSON_PARSE_FAILED,
  '非 JSON → 2001');
eq(codeOf((): Object => WeatherParser.parse('{}', '')), ErrorCode.TYPE_GUARD_FAILED,
  '缺 daily → 2003');
eq(codeOf((): Object => WeatherParser.parse('{"daily":{"time":[]},"hourly":{}}', '')),
  ErrorCode.SCHEMA_VALIDATION_FAILED, 'daily.time 为空 → 2002');
eq(codeOf((): Object => WeatherParser.parse(
  '{"daily":{"time":["2026-10-30"],"weather_code":[1],"temperature_2m_max":[20],'
  + '"temperature_2m_min":[10],"precipitation_probability_max":[0]},'
  + '"hourly":{"time":["2026-10-31T00:00"],"weather_code":[1],'
  + '"temperature_2m":[15],"precipitation_probability":[0]}}', '2026-10-30')),
  ErrorCode.SCHEMA_VALIDATION_FAILED, '当日无小时数据 → 2002');

// ---------------- 信号：阈值与优先级 ----------------

function signalDay(): TripDay {
  return dayOf([
    act('a0', '09:00', '10:00', '早饭散步', ActivityCategory.SIGHT, ActivityStatus.NOT_BOOKED,
      34.30, 108.10),
    act('a2', '14:00', '15:00', '博物馆', ActivityCategory.SIGHT, ActivityStatus.NOT_BOOKED,
      34.27, 108.07),
    act('a3', '15:30', '16:30', '城墙', ActivityCategory.SIGHT, ActivityStatus.NOT_BOOKED,
      34.26, 108.08),
    act('a4', '19:00', '20:00', '夜景', ActivityCategory.SIGHT, ActivityStatus.BOOKED,
      34.25, 108.09)
  ], [meal(MealType.LUNCH, '12:00'), meal(MealType.DINNER, '18:00')]);
}

const farFix: GeoPoint = { latitude: 34.29, longitude: 108.07 };
const nearFix: GeoPoint = { latitude: 34.275, longitude: 108.07 };
const targetPoint: GeoPoint = { latitude: 34.27, longitude: 108.07 };
ok(Geo.distanceM(farFix, targetPoint) > 1000, '远点构造 >1km');
ok(Geo.distanceM(nearFix, targetPoint) < 1000, '近点构造 <1km');

const notToday: SignalContext = {
  isToday: false, nowMin: 870, fix: farFix, checkedIds: [], currentKey: 'a2', weather: null
};
ok(TripSignals.suggest(signalDay(), notToday) === null, '非今天不出建议');
ok(TripSignals.suggest(signalDay(), ctxOf(-1, farFix, [], null)) === null, 'nowMin 非法不出建议');

const offRoute: TripSuggestion | null = TripSignals.suggest(signalDay(),
  ctxOf(870, farFix, ['a0'], null));
ok(offRoute !== null, '远距 + 已过开始 30 分钟出建议');
eq(offRoute !== null ? offRoute.kind : '', SignalKind.OFF_ROUTE, '偏离优先级高于落后');
eq(offRoute !== null ? offRoute.targetId : '', 'a2', '偏离目标是当前站');
eq(offRoute !== null ? offRoute.action : '', SignalAction.SKIP, '偏离动作=跳过');
eq(offRoute !== null ? offRoute.actionLabel : '', '跳过这一站', '偏离按钮文案');
ok(offRoute !== null && offRoute.title.indexOf('离「博物馆」') === 0, '偏离标题带站名与距离');
ok(offRoute !== null && offRoute.title.indexOf('km') > 0, '偏离标题距离走公里档');

const nearSuggestion: TripSuggestion | null = TripSignals.suggest(signalDay(),
  ctxOf(870, nearFix, ['a0'], null));
eq(nearSuggestion !== null ? nearSuggestion.kind : '', SignalKind.BEHIND, '在 1km 内落到落后信号');
eq(nearSuggestion !== null ? nearSuggestion.deltaMin : -1, 30, '落后 30 分钟顺延 30');
eq(nearSuggestion !== null ? nearSuggestion.actionLabel : '', '顺延 30 分钟', '落后按钮文案');
eq(nearSuggestion !== null ? nearSuggestion.detail : '',
  '「博物馆」还没打卡，后续按原时间排', '落后说明文案');

ok(TripSignals.suggest(signalDay(), ctxOf(845, farFix, ['a0'], null)) === null,
  '偏离需已过开始 ≥10 分钟');
ok(TripSignals.suggest(signalDay(), ctxOf(880, null, ['a0', 'a2'], null)) === null,
  '当前站已打卡且无后续已开始站时不出落后');
ok(TripSignals.suggest(signalDay(), ctxOf(870, farFix, ['a0', 'a2'], null)) === null,
  '已打卡站不报偏离');

const round: TripSuggestion | null = TripSignals.suggest(signalDay(),
  ctxOf(871, null, ['a0'], null));
eq(round !== null ? round.deltaMin : -1, 45, '落后 31 分钟向上取到 45');

const lateOnlyBooked: TripDay = dayOf([
  act('a0', '09:00', '10:00', '早饭散步'),
  act('a2', '14:00', '15:00', '博物馆'),
  act('a3', '15:30', '16:30', '城墙', ActivityCategory.SIGHT, ActivityStatus.BOOKED)
], []);
const skipInstead: TripSuggestion | null = TripSignals.suggest(lateOnlyBooked,
  ctxOf(870, null, ['a0'], null));
eq(skipInstead !== null ? skipInstead.kind : '', SignalKind.BEHIND, '无可顺延站仍是落后信号');
eq(skipInstead !== null ? skipInstead.action : '', SignalAction.SKIP, '无可顺延站改跳过');
ok(skipInstead !== null && skipInstead.detail.indexOf('今天没有可顺延的站') > 0,
  '无可顺延站说明文案');

const rain: TripSuggestion | null = TripSignals.suggest(signalDay(),
  ctxOf(850, null, ['a0'], weatherOf(70)));
eq(rain !== null ? rain.kind : '', SignalKind.RAIN, '未来室外站降水 ≥60% 出有雨建议');
eq(rain !== null ? rain.targetId : '', 'a3', '有雨目标是前方第一处室外站');
eq(rain !== null ? rain.title : '', '前方室外站有雨', '有雨标题');
ok(rain !== null && rain.detail.indexOf('15:30–16:30') > 0, '有雨说明带站点时段');
ok(rain !== null && rain.detail.indexOf('降水 70%') > 0, '有雨说明带降水概率');

ok(TripSignals.suggest(signalDay(), ctxOf(850, null, ['a0'], weatherOf(50))) === null,
  '降水 50% 不触发有雨');

const indoorDay: TripDay = dayOf([
  act('a0', '09:00', '10:00', '早饭散步'),
  act('a2', '14:00', '15:00', '博物馆'),
  act('a3', '15:30', '16:30', '餐馆', ActivityCategory.FOOD, ActivityStatus.NO_NEED)
], []);
ok(TripSignals.suggest(indoorDay, ctxOf(850, null, ['a0'], weatherOf(70))) === null,
  '室内站不报有雨');

// ---------------- 顺延排程 ----------------

function shiftDay(): TripDay {
  return dayOf([
    act('a1', '09:00', '10:00', '早饭散步'),
    act('a2', '14:00', '15:00', '博物馆'),
    act('a3', '15:30', '16:30', '城墙'),
    act('a4', '16:45', '17:30', '小店', ActivityCategory.SHOP, ActivityStatus.NO_NEED),
    act('a5', '19:00', '20:00', '夜景', ActivityCategory.SIGHT, ActivityStatus.BOOKED)
  ], [meal(MealType.LUNCH, '12:00'), meal(MealType.DINNER, '18:00')]);
}

ok(SkipPlanner.isShiftTarget(find(shiftDay(), 'a3'), 845), '未开始的普通站可顺延');
ok(SkipPlanner.isShiftTarget(find(shiftDay(), 'a3'), 930), '开始时刻当分钟仍算未开始');
ok(!SkipPlanner.isShiftTarget(find(shiftDay(), 'a3'), 931), '已开始的站不是顺延目标');
ok(!SkipPlanner.isShiftTarget(find(shiftDay(), 'a5'), 845), '预约站不是顺延目标');
ok(!SkipPlanner.isShiftTarget(find(shiftDay(), 'a1'), 845), '已过去的站不是顺延目标');
ok(!SkipPlanner.isShiftTarget(act('t1', '15:00', '15:30', '地铁',
  ActivityCategory.TRANSPORT, ActivityStatus.NO_NEED), 845), '交通不是顺延目标');
ok(!SkipPlanner.isShiftTarget(act('h1', '21:00', '22:00', '酒店',
  ActivityCategory.HOTEL, ActivityStatus.NO_NEED), 845), '住宿不是顺延目标');
ok(!SkipPlanner.isShiftTarget(marker('m1', '15:00', '15:30'), 845), '跳过占位不是顺延目标');

const shifted = SkipPlanner.shiftRemaining(shiftDay(), 845, 45);
ok(shifted.changed === true, '顺延标记 changed');
eq(find(shifted.day, 'a3').time, '16:15', '顺延 +45 后首站落位');
eq(find(shifted.day, 'a3').endTime, '17:15', '顺延后首站时长不变');
eq(find(shifted.day, 'a4').time, '20:00', '撞晚餐/预约锚点后继续后移');
eq(find(shifted.day, 'a4').endTime, '20:45', '后移后时长不变');
eq(find(shifted.day, 'a2').time, '14:00', '当前站不动');
eq(find(shifted.day, 'a5').time, '19:00', '预约锚点不动');
eq(find(shifted.day, 'a1').time, '09:00', '已过去的站不动');
eq(shifted.day.activities.map((a: Activity): string => a.id).join(','), 'a1,a2,a3,a4,a5',
  '顺延不增删不改序');
eq(shifted.day.meals[1].time ?? '', '18:00', '餐次时刻不变');
ok(shifted.note.indexOf('已顺延 45 分钟') === 0, '顺延提示文案');
ok(shifted.note.indexOf('待调整') < 0, '无溢出时不带待调整后缀');

// 当前站的剩余时段是锚点：下一站不能插进当前站还没走完的时间里
const curDay: TripDay = dayOf([
  act('c1', '09:00', '10:00', '早饭'),
  act('c2', '14:00', '16:30', '排长队'),
  act('c3', '15:00', '15:30', '下一站')
], []);
const curShift = SkipPlanner.shiftRemaining(curDay, 845, 15);
eq(find(curShift.day, 'c3').time, '16:30', '下一站被当前站剩余时段推到其结束');

// 溢出：越过 23:59 的项及其后保持原时间并标待调整
const lateShift = SkipPlanner.shiftRemaining(dayOf([
  act('s1', '18:30', '19:30', '夜游'),
  act('s2', '23:10', '23:50', '塔')
], []), 1100, 40);
eq(find(lateShift.day, 's1').time, '19:10', '溢出前的站正常后移');
eq(find(lateShift.day, 's2').time, '23:10', '溢出项保留原时间');
ok((find(lateShift.day, 's2').note ?? '').indexOf('待调整') >= 0, '溢出项 note 追加待调整');
ok(lateShift.note.indexOf('部分站点待调整') > 0, '溢出提示带后缀');
ok(lateShift.changed === true, '溢出也标记 changed');

// 无目标 / 非正 delta：不改行程
const noTargetDay: TripDay = dayOf([
  act('a1', '09:00', '10:00', '早饭'),
  act('a5', '19:00', '20:00', '夜景', ActivityCategory.SIGHT, ActivityStatus.BOOKED)
], []);
const noTarget = SkipPlanner.shiftRemaining(noTargetDay, 845, 45);
ok(noTarget.changed === false, '无可顺延站 changed=false');
eq(noTarget.note, '没有需要顺延的站点', '无可顺延站提示');
eq(find(noTarget.day, 'a5').time, '19:00', '无可顺延站行程不变');
const zeroDelta = SkipPlanner.shiftRemaining(shiftDay(), 845, 0);
ok(zeroDelta.changed === false, 'delta=0 不改行程');
const negDelta = SkipPlanner.shiftRemaining(shiftDay(), 845, -30);
ok(negDelta.changed === false, 'delta<0 不改行程');
eq(find(negDelta.day, 'a3').time, '15:30', 'delta<0 时刻不变');

// 顺延不把跳过占位当站点也不改它
const markerDay: TripDay = dayOf([
  act('a1', '09:00', '10:00', '早饭'),
  marker('m1', '14:30', '15:00'),
  act('a3', '15:30', '16:30', '城墙')
], []);
const markerShift = SkipPlanner.shiftRemaining(markerDay, 780, 30);
eq(find(markerShift.day, 'm1').time, '14:30', '跳过占位原地不动');
eq(find(markerShift.day, 'a3').time, '16:00', '其余站正常顺延');

// 通勤不是顺延目标，但也不被改写
const transportDay: TripDay = dayOf([
  act('a1', '09:00', '10:00', '早饭'),
  act('t1', '15:00', '15:30', '地铁', ActivityCategory.TRANSPORT, ActivityStatus.NO_NEED),
  act('a3', '15:40', '16:30', '城墙')
], []);
const transportShift = SkipPlanner.shiftRemaining(transportDay, 845, 30);
eq(find(transportShift.day, 't1').time, '15:00', '交通段不被顺延');
eq(find(transportShift.day, 'a3').time, '16:10', '交通之后的活动照常顺延');

// ── NodeOwe：屏15「你欠着的那一站」的唯一规则 ────────────────────────────
// 喂打卡列表的「进行中」行与建议条。hero 的「现在该在哪」是另一个问题，在页面里另算。
function item(key: string, startMin: number): OweItem {
  const i: OweItem = { key: key, startMin: startMin };
  return i;
}

const owedList: OweItem[] = [item('a1', 540), item('a2', 600), item('a3', 660)];
eq(NodeOwe.indexOf(owedList, [], 630), 0, '全没打卡时欠第一站');
eq(NodeOwe.indexOf(owedList, [], 500), -1, '首站还没开始就不欠（退回时钟规则）');
eq(NodeOwe.indexOf(owedList, ['a1'], 630), 1, '打过 a1 就欠 a2');
eq(NodeOwe.indexOf(owedList, ['a1', 'a2'], 630), -1, '已开始的都打完了不欠');
// 已经走过 a2 再回头说 a1 欠着，会把用户按回过去那一站——a1 不算欠
eq(NodeOwe.indexOf(owedList, ['a2'], 700), 2, '最后一个已打卡之前的漏站不回头追');
eq(NodeOwe.indexOf(owedList, ['a1', 'a2', 'a3'], 1200), -1, '全打完工不欠');
eq(NodeOwe.indexOf(owedList, ['a1'], 700), 1, 'a2 a3 都已开始时仍欠最先那个没打的 a2');
eq(NodeOwe.indexOf([], ['a1'], 630), -1, '空列表不欠');
eq(NodeOwe.indexOf(owedList, ['nope'], 630), 0, '打卡集合里的陌生 key 不影响判定');

// 落后时的落点回归：a2 欠着没打卡、a3 也已开始。
// 钟点规则会说 a3（城墙），建议条必须说「你欠的」a2（博物馆）——
// 两者回答不同问题，但建议条与「跳过这一站」的动作必须落在同一个站上。
const divergeCtx: SignalContext = ctxOf(960, null, ['a0'], null);
eq(divergeCtx.currentKey, 'a2', '落后时欠站是 a2，不是钟点上的 a3');
const diverge: TripSuggestion | null = TripSignals.suggest(signalDay(), divergeCtx);
ok(diverge !== null, '落后要出建议');
if (diverge !== null) {
  eq(diverge.kind, SignalKind.BEHIND, '落后信号');
  eq(diverge.targetId, 'a2', '建议条的动作落在欠着的那一站');
  eq(diverge.detail.indexOf('「博物馆」'), 0, '建议条说的站与 hero 同一站');
}

console.log(`WEATHER_SIGNALS_OK cases=${cases}`);
