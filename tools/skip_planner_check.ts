/**
 * SkipPlanner 离线断言：被 tools/verify_replan_logic.sh 拷进临时目录后
 * 用 bundled tsc --strict 编译、bundled node 运行。不依赖 @kit / 设备。
 */

import {
  Activity, ActivityCategory, ActivityStatus, IntensityLevel, Meal, MealType, TransportInfo, Trip, TripDay
} from '../model/Trip';
import { FreeBlock, KeepStop, ReplanDecision } from '../model/Replan';
import { SkipPlanner } from '../data/SkipPlanner';
import { GeofencePlan } from '../utils/GeofencePlan';
import { ReminderKind, ReminderPlan, ReminderPlanItem } from '../utils/ReminderPlan';
import { DateUtils } from '../utils/DateUtils';

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

// ---- 时间原语 ----
eq(DateUtils.minutesOf('00:00'), 0, 'minutesOf 00:00');
eq(DateUtils.minutesOf('23:59'), 1439, 'minutesOf 23:59');
eq(DateUtils.minutesOf('24:00'), -1, 'minutesOf 拒绝 24:00');
eq(DateUtils.minutesOf('9:00'), -1, 'minutesOf 拒绝非两位小时');
eq(DateUtils.hhmmOf(1439), '23:59', 'hhmmOf 23:59');
eq(DateUtils.hhmmOf(1440), '23:59', 'hhmmOf 上界夹紧');

// ---- 可跳过判定 ----
ok(SkipPlanner.isSkippable(ActivityCategory.SIGHT, ActivityStatus.NOT_BOOKED), '景点未预约可跳过');
ok(!SkipPlanner.isSkippable(ActivityCategory.SIGHT, ActivityStatus.BOOKED), '已预约不可跳过');
ok(!SkipPlanner.isSkippable(ActivityCategory.TRANSPORT, ActivityStatus.NO_NEED), '交通不可跳过');
ok(!SkipPlanner.isSkippable(ActivityCategory.HOTEL, ActivityStatus.NO_NEED), '住宿不可跳过');
ok(!SkipPlanner.isSkippable(ActivityCategory.REST, ActivityStatus.NO_NEED), '空闲不可跳过');
ok(!SkipPlanner.isSkippable(null, ActivityStatus.NO_NEED), '餐次（null）不可跳过');

// ---- 剩余站点：REST 仍是站点，只有被跳过的那个 id 排除 ----
eq(SkipPlanner.remainingIds(mainDay(), 'a2', 845).join(','), 'a3,a4',
  '剩余 = 非交通/住宿 + 非 BOOKED + 未发生 + 非 skippedId');
const restDay = dayOf([
  act('a2', '14:00', '15:00', '可跳过'),
  act('r1', '15:10', '15:40', '休息', ActivityCategory.REST, ActivityStatus.NO_NEED)
], []);
eq(SkipPlanner.remainingIds(restDay, 'a2', 845).join(','), 'r1', 'REST 不是锚点，仍在剩余里');

// ---- 合法决策：顺序可换、通勤归到达站、锚点不动 ----
const base = mainDay();
const outcome = SkipPlanner.plan(base, 'a2', 845,
  decisionOf([keepOf('a4', 40), keepOf('a3', 60)], [], '下午节奏放缓'));
ok(!outcome.usedFallback, '合法决策不走兜底');
const out = outcome.day;
eq(find(out, 'a2').category, ActivityCategory.REST, '被跳过项改为 REST');
eq(find(out, 'a2').title, '空闲', '被跳过项标题');
eq(find(out, 'a2').status, ActivityStatus.NO_NEED, '被跳过项状态');
eq(find(out, 'a2').note ?? '', '已跳过：清水寺', '被跳过项保留来源');
eq(find(out, 'a2').time, '14:00', '被跳过项保留开始时刻');
eq(find(out, 'a2').endTime, '15:00', '被跳过项保留结束时刻');
eq(find(out, 'a4').time, '15:05', '第一项也吃通勤 5 分钟');
eq(find(out, 'a4').endTime, '15:45', '第一项按 dwell 落位');
eq(find(out, 'a3').time, '15:55', '第二项吃自身通勤 10 分钟');
eq(find(out, 'a3').endTime, '16:55', '第二项按 dwell 落位');
eq(find(out, 'a5').time, '19:00', '已预约锚点不动');
eq(out.activities.map((a: Activity): string => a.id).join(','), 'a1,a2,a3,a4,a5', '活动顺序不变');
ok(outcome.note.indexOf('下午节奏放缓') >= 0, '页面提示带决策备注');

// ---- 空档：afterId 当前结束时刻被游标越过才消费；过去的空档忽略 ----
// keep 必须覆盖全部剩余站点（a3、a4），少一项就会被守卫判非法走兜底
const f1 = SkipPlanner.plan(mainDay(), 'a2', 845,
  decisionOf([keepOf('a3', 60), keepOf('a4', 40)], [blockOf('a2', 30)], ''));
eq(find(f1.day, 'a3').time, '15:40', '跳过段后的空档先加 30 分钟');
ok(!f1.usedFallback, '空档路径不触发兜底');

const f2 = SkipPlanner.plan(mainDay(), 'a2', 845,
  decisionOf([keepOf('a3', 60), keepOf('a4', 40)], [blockOf('a1', 30)], ''));
eq(find(f2.day, 'a3').time, '15:10', '已过去的 afterId 空档忽略');

const f3 = SkipPlanner.plan(mainDay(), 'a2', 845,
  decisionOf([keepOf('a3', 60), keepOf('a4', 40)], [blockOf('a3', 20)], ''));
eq(find(f3.day, 'a3').time, '15:10', '保留项先落位');
eq(find(f3.day, 'a4').time, '16:35', '保留项之后的空档在下一项前消费');
ok(!f3.usedFallback, '保留项空档路径不触发兜底');

// ---- 跨锚点：落位会跨过晚餐则移到锚点结束 ----
const crossDay = dayOf([
  act('a2', '17:00', '17:30', '可跳过'),
  act('a3', '18:30', '19:30', '下一站')
], [meal(MealType.DINNER, '18:00')]);
const cross = SkipPlanner.plan(crossDay, 'a2', 1020, decisionOf([keepOf('a3', 120)], [], ''));
eq(find(cross.day, 'a3').time, '19:00', '跨晚餐锚点时移到 19:00');

// ---- 23:59 溢出：该项及之后保留原时间 + 待调整 ----
const lateDay = dayOf([
  act('a2', '21:30', '22:00', '夜游'),
  act('a3', '22:10', '22:40', '塔'),
  act('a4', '22:50', '23:20', '桥')
], []);
const late = SkipPlanner.plan(lateDay, 'a2', 1320,
  decisionOf([keepOf('a3', 60), keepOf('a4', 60)], [], ''));
ok(!late.usedFallback, '溢出不是兜底，是决策路径的降级');
eq(find(late.day, 'a3').time, '22:00', '溢出前的站点正常落位');
eq(find(late.day, 'a4').time, '22:50', '溢出项保留原时间');
ok((find(late.day, 'a4').note ?? '').indexOf('待调整') >= 0, '溢出项 note 追加待调整');
ok(late.note.indexOf('部分站点待调整') >= 0, '页面提示带溢出后缀');

// ---- 守卫：缺项/多项/重复/越界/未知 afterId/超长 note/schema 不符 ----
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
  const r = SkipPlanner.plan(mainDay(), 'a2', 845, rejects[i]);
  ok(r.usedFallback, `非法决策 #${i} 必须走兜底`);
  eq(find(r.day, 'a2').title, '空闲', `非法决策 #${i} 仍完成跳过改写`);
}
const schema2: ReplanDecision = {
  schemaVersion: 2, keep: [keepOf('a3', 60), keepOf('a4', 40)], freeBlocks: [], note: ''
};
ok(SkipPlanner.plan(mainDay(), 'a2', 845, schema2).usedFallback, 'schemaVersion 不符走兜底');

// ---- 本地兜底：整体后移 + 锚点冲突整体再顺延 ----
const fb = SkipPlanner.plan(mainDay(), 'a2', 845, null);
ok(fb.usedFallback, '无决策走本地兜底');
eq(find(fb.day, 'a3').time, '20:00', '兜底后移并避开晚餐/已预约锚点');
eq(find(fb.day, 'a4').time, '21:15', '兜底保持相对顺序');
ok(fb.note.indexOf('离线重排') >= 0, '兜底提示文案');

const lateFb = SkipPlanner.plan(dayOf([
  act('a2', '22:30', '23:00', '夜游'),
  act('a3', '23:10', '23:40', '塔'),
  act('a4', '23:45', '23:59', '桥')
], []), 'a2', 1380, null);
ok(lateFb.usedFallback, '兜底溢出仍是兜底');
eq(find(lateFb.day, 'a3').time, '23:10', '兜底溢出项保留原时间');
ok((find(lateFb.day, 'a3').note ?? '').indexOf('待调整') >= 0, '兜底溢出项追加待调整');
ok(lateFb.note.indexOf('部分站点待调整') >= 0, '兜底溢出提示带后缀');

// ---- 请求体：发送重写前的整日，不信任客户端剩余列表 ----
const req = SkipPlanner.buildRequest(mainDay(), 'a2', 845);
eq(req.schemaVersion, 1, '请求 schemaVersion');
eq(req.now, '14:05', '请求 now');
eq(req.day.activities.length, 5, '请求含整日全部活动（含被跳过项）');
eq(req.day.meals.length, 2, '请求含全部餐次');
eq(req.day.activities[2].transport?.duration ?? -1, 10, '通勤时长随请求上传');
eq(req.day.meals[0].time ?? '', '12:00', '餐次时刻随请求上传');
const rawFirst = req.day.activities[0] as unknown as Record<string, Object>;
ok(rawFirst['note'] === undefined && rawFirst['reason'] === undefined, '请求不携带 note/reason');

// ---- 深拷贝：改 clone 不能回写原日 ----
const original = mainDay();
const clone = SkipPlanner.cloneDay(original);
clone.activities[2].title = '改名';
if (clone.activities[2].transport !== undefined) {
  clone.activities[2].transport.duration = 99;
}
eq(find(original, 'a3').title, '二年坂', 'cloneDay 活动标题深拷贝');
eq(find(original, 'a3').transport?.duration ?? -1, 10, 'cloneDay 通勤深拷贝');

// ---- 加一站：云函数决策重排 + 480min 预算 ----
const addStop = act('n1', '16:00', '17:00', '教稼园');
const addReq = SkipPlanner.buildAddRequest(mainDay(), addStop, 845);
eq(addReq.addStopId ?? '', 'n1', '加站请求带 addStopId');
eq(addReq.skippedId ?? '', '', '加站请求不带 skippedId');
eq(addReq.day.activities.length, 6, '加站请求把新站放进整日');
eq(addReq.day.activities[5].time >= '14:05', true, '新站带未来临时时刻');

const addCloud = SkipPlanner.planWithAddition(mainDay(), addStop, 845,
  decisionOf([keepOf('n1', 60), keepOf('a3', 60), keepOf('a4', 40)], [], '先看新站'));
ok(addCloud.changed === true, '加站决策生效');
ok(!addCloud.usedFallback, '加站决策不走兜底');
eq(find(addCloud.day, 'n1').time, '15:00', '新站接在当前站结束之后');
eq(find(addCloud.day, 'a3').time, '16:10', '既有站按决策顺序后移');
eq(find(addCloud.day, 'a5').time, '19:00', '已预约锚点不动');

const addLocal = SkipPlanner.planWithAddition(mainDay(), addStop, 845, null);
ok(addLocal.changed === true, '无决策时本地追加生效');
ok(addLocal.usedFallback, '本地追加标记为兜底');
eq(find(addLocal.day, 'n1').time, '20:15', '本地追加到当日最后节点之后');

// 已排满的一天：加站必须被 480min 预算拒绝，且不改原日
const fullDay = dayOf([
  act('b1', '09:00', '13:00', '长线一'),
  act('b2', '14:00', '18:00', '长线二')
], []);
const fullAdd = SkipPlanner.planWithAddition(fullDay, act('n2', '18:15', '19:15', '再加一站'), 1080, null);
ok(fullAdd.changed === false, '超 480min 预算不加站');
ok(fullAdd.note.indexOf('超过') >= 0, '超预算提示说明原因');
eq(fullAdd.day.activities.length, 2, '拒绝时原日不变');

// ---- 换一站：保留原槽时间与通勤 ----
const replaced = SkipPlanner.planWithReplacement(mainDay(), 'a3',
  act('n3', '18:00', '19:00', '新景点'));
ok(replaced.changed === true, '换站生效');
eq(find(replaced.day, 'n3').time, '15:30', '换站保留原开始时刻');
eq(find(replaced.day, 'n3').endTime, '16:30', '换站保留原结束时刻');
eq(find(replaced.day, 'n3').transport?.duration ?? -1, 10, '换站保留原通勤');
eq(find(replaced.day, 'n3').title, '新景点', '换站换掉节点内容');

// 已排满的一天也能换：换节点不换槽，日负载不增加，不该被 480min 加站预算误拦
const fullReplace = SkipPlanner.planWithReplacement(fullDay, 'b2',
  act('n4', '14:00', '18:00', '室内替代'));
ok(fullReplace.changed === true, '满负载日换站不被 480min 预算误拦');
eq(find(fullReplace.day, 'n4').time, '14:00', '满负载日换站保留原槽');

// ---- P5 到站围栏规划：只围未结束、有坐标、非锚点的站 ----
const fences = GeofencePlan.of(mainDay(), 845);
eq(fences.length, 4, '围栏只含未结束且有坐标的站（a1 已结束）');
eq(fences[0].activityId, 'a2', '正在进行的一站也注册围栏');
eq(fences[0].radiusM, 300, '默认到站半径 300m');
ok(fences.every((f): boolean => f.title.length > 0), '围栏带站点标题');
const noGeoDay = dayOf([act('x', '15:00', '16:00', '无坐标')], []);
noGeoDay.activities[0].latitude = 0;
noGeoDay.activities[0].longitude = 0;
eq(GeofencePlan.of(noGeoDay, 845).length, 0, '无坐标的站不注册围栏');
const pastDay = dayOf([act('p', '09:00', '10:00', '已结束')], []);
eq(GeofencePlan.of(pastDay, 845).length, 0, '已结束的站不注册围栏');

// ---- P4 提醒排程：出发前 / 预约提前 / 晨间播报，已过窗口不补发 ----
function dayAt(date: string, acts: Activity[]): TripDay {
  return {
    dayIndex: 1, date: date, theme: '杨凌一日', intensity: IntensityLevel.LOW,
    dailyCost: 0, activities: acts, meals: []
  };
}

const reminderDay1 = dayAt('2026-11-20', [(() => {
  const a = act('r1', '09:00', '10:00', '博览园', ActivityCategory.SIGHT, ActivityStatus.NOT_BOOKED);
  a.advanceDays = 7;
  return a;
})()]);
const reminderDay2 = dayAt('2026-11-21', [
  act('r2', '09:00', '10:00', '已约', ActivityCategory.SIGHT, ActivityStatus.BOOKED),
  act('r3', '10:00', '11:00', '无需预约', ActivityCategory.SIGHT, ActivityStatus.NO_NEED),
  act('r4', '11:00', '12:00', '待定', ActivityCategory.SIGHT, ActivityStatus.PENDING)
]);
const reminderTrip: Trip = {
  id: 't-reminder', destination: '杨凌', startDate: '2026-11-20', endDate: '2026-11-21',
  people: 1, budget: 0, style: 'leisure',
  overview: { totalCost: 0, highlights: [], summary: '' },
  days: [reminderDay1, reminderDay2], tips: []
};
const reminderNow = new Date(2026, 10, 9, 0, 0, 0).getTime();
const reminderItems: ReminderPlanItem[] = ReminderPlan.plan(reminderTrip, reminderNow);
eq(reminderItems.length, 5, '三类提醒共 5 条（出发 1 + 晨间 2 + 预约 2）');
const departureItems = reminderItems.filter((i): boolean => i.kind === ReminderKind.DEPARTURE);
const morningItems = reminderItems.filter((i): boolean => i.kind === ReminderKind.MORNING);
const bookingItems = reminderItems.filter((i): boolean => i.kind === ReminderKind.BOOKING);
eq(departureItems.length, 1, '出发前提醒 1 条');
eq(morningItems.length, 2, '两天各一条晨间播报');
eq(bookingItems.length, 2, '只提醒未约上的节点（已约/无需预约不催）');
eq(departureItems[0].at, new Date(2026, 10, 19, 20, 0, 0).getTime(), '出发前一天 20:00');
eq(morningItems[0].at, new Date(2026, 10, 20, 7, 30, 0).getTime(), '首日 07:30 晨间播报');
eq(bookingItems[0].at, new Date(2026, 10, 13, 9, 0, 0).getTime(), 'advanceDays=7 → 11-13 09:00');
eq(bookingItems[1].at, new Date(2026, 10, 20, 9, 0, 0).getTime(), '无 advanceDays → 提前 1 天兜底');
ok(departureItems[0].content.indexOf('博览园') >= 0, '出发前文案带首站');
ok(bookingItems[0].content.indexOf('提前 7 天') >= 0, '预约文案带真实提前量');
const pastTrip: Trip = {
  id: 't-past', destination: '杨凌', startDate: '2026-11-01', endDate: '2026-11-01',
  people: 1, budget: 0, style: 'leisure',
  overview: { totalCost: 0, highlights: [], summary: '' },
  days: [dayAt('2026-11-01', [act('p1', '09:00', '10:00', '过去', ActivityCategory.SIGHT, ActivityStatus.NOT_BOOKED)])],
  tips: []
};
eq(ReminderPlan.plan(pastTrip, reminderNow).length, 0, '已过窗口不补发');

console.log(`SKIP_PLANNER_OK cases=${cases}`);
