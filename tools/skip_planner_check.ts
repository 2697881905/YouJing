/**
 * SkipPlanner 离线断言：被 tools/verify_replan_logic.sh 拷进临时目录后
 * 用 bundled tsc --strict 编译、bundled node 运行。不依赖 @kit / 设备。
 */

import {
  Activity, ActivityCategory, ActivityStatus, IntensityLevel, Meal, MealType, TransportInfo, TripDay
} from '../model/Trip';
import { FreeBlock, KeepStop, ReplanDecision } from '../model/Replan';
import { SkipPlanner } from '../data/SkipPlanner';
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

console.log(`SKIP_PLANNER_OK cases=${cases}`);
