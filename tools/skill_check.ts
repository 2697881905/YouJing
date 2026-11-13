/**
 * 小艺 Skill 契约离线断言：打**真实生产代码**（PlanTripSkill + SkillPrefill）。
 *
 * 与 tools/trip_intent_check.ts 同源思路，但打的是 entry/skills/ 下那份真脚本，
 * 不是复制逻辑重写——断言钉的是真行为。
 *
 * 为什么能离线跑：Skill 脚本只依赖 @kit.AbilityKit（scriptManager 回调）、
 * @kit.BasicServicesKit（BusinessError）、@kit.ArkData（preferences）、
 * @kit.PerformanceAnalysisKit（hilog）。verify_skill_logic.sh 给这四个 kit
 * 喂最小替身，脚本本体一字不改地拷进来编译。
 *
 * 覆盖：
 *   1. 四城白名单 + 四参映射（destination/startDate/days/people/route）
 *   2. 非四城 → ERR_INVALID_PARAMS + suggestion 列出支持城市
 *   3. 非法日期（2026-02-30 / 13 月 / 空 / 非 ISO）→ ERR_INVALID_PARAMS
 *   4. 天数 / 人数越界（0 / 31 / 负数 / 小数 / 非数字）→ ERR_INVALID_PARAMS
 *   5. 省略天数人数 → 默认 3 天 2 人
 *   6. 过去日期被脚本拒绝（2026-11-13 修缺陷 A）：ERR_INVALID_PARAMS + suggestion 追问将来的日期；
 *      当天与将来的日期照常接受
 *   7. message 文案含四要素 + 手机上 launched=false
 *   8. SkillPrefill 取后即删
 *   9. 超过 2 小时的预填被拒
 *  10. 非法字段的预填被拒（空城市 / 假日期 / days 与 people 越界）
 *  11. clear 后为空
 */

import PlanTripSkill from './PlanTripSkill';
import { SkillPrefill, SkillPrefillRecord } from './SkillPrefill';
import { common, scriptManager } from './kit/AbilityKit';
import { DateUtils } from './DateUtils';

/**
 * 日期用例一律相对「今天」生成。
 * 写死 2026-12-01 的话，过了那天它就集体变成过去日期，
 * 用例会从「应成功」变成「应失败」而集体误报（这正是缺陷 A 的判据本身）。
 */
const TODAY: string = DateUtils.todayIso();
const FUTURE: string = DateUtils.addDays(TODAY, 30);
const YESTERDAY: string = DateUtils.addDays(TODAY, -1);

/** ISO → 「M月D日」，与屏2 的日期文案同形 */
function md(iso: string): string {
  const parts: string[] = iso.split('-');
  return `${Number(parts[1])}月${Number(parts[2])}日`;
}

let cases = 0;

function ok(cond: boolean, msg: string): void {
  cases += 1;
  if (!cond) {
    throw new Error('FAIL: ' + msg);
  }
}

function eq(actual: string | number | boolean, expected: string | number | boolean, msg: string): void {
  cases += 1;
  if (actual !== expected) {
    throw new Error('FAIL: ' + msg +
      '（actual=' + String(actual) + ' expected=' + String(expected) + '）');
  }
}

interface Captured {
  code: number;
  payload: Record<string, Object>;
}

const stubInfo: scriptManager.ArkTSScriptInfo = {
  context: {} as common.Context,
  requestCode: 1
};

/** 调真脚本，从 kit 替身回包里取结果 */
async function run(argv: string[]): Promise<Captured> {
  const g: Record<string, Object> = globalThis as unknown as Record<string, Object>;
  const arr: Object[] = (g['__captured'] as Object[]) ?? [];
  arr.length = 0;
  g['__captured'] = arr;
  const skill: PlanTripSkill = new PlanTripSkill();
  await skill.planTrip(stubInfo, ...argv);
  const last: Object | undefined = arr[arr.length - 1];
  if (last === undefined) {
    return { code: -1, payload: {} };
  }
  const res: scriptManager.ExecuteResult = last as scriptManager.ExecuteResult;
  const payload: Record<string, Object> = res.result as Record<string, Object>;
  return { code: res.code, payload: payload };
}

function expectSuccess(argv: string[], label: string): Record<string, Object> {
  return { argv: argv, label: label };
}

// ── 1. 四城白名单 + 四参映射 ────────────────────────────────
async function testCities(): Promise<void> {
  const cities: string[] = ['北京', '上海', '广州', '深圳'];
  for (const c of cities) {
    const r: Captured = await run([c, FUTURE, '4', '3']);
    eq(r.payload['status'] as string, 'success', '四城之一应成功：' + c);
    const data: Record<string, Object> = r.payload['data'] as Record<string, Object>;
    eq(data['destination'] as string, c, 'destination 应原样回传：' + c);
    eq(data['startDate'] as string, FUTURE, 'startDate 应回传');
    eq(data['days'] as number, 4, 'days 应回传');
    eq(data['people'] as number, 3, 'people 应回传');
    eq(data['route'] as string, 'TripInput', 'route 应为 TripInput');
  }
}

// ── 2. 非四城 → 拒绝 + 可执行 suggestion ────────────────────
async function testUnsupportedCity(): Promise<void> {
  const bad: string[] = ['成都', '杭州', '西安', '厦门', ''];
  for (const c of bad) {
    const r: Captured = await run([c, FUTURE, '3', '2']);
    eq(r.payload['status'] as string, 'failed', '非四城应失败：' + (c.length === 0 ? '(空)' : c));
    eq(r.payload['errCode'] as string, 'ERR_INVALID_PARAMS', '错误码应为 ERR_INVALID_PARAMS');
    const sug: string = r.payload['suggestion'] as string;
    ok(sug.indexOf('北京') >= 0 && sug.indexOf('上海') >= 0 &&
      sug.indexOf('广州') >= 0 && sug.indexOf('深圳') >= 0,
      'suggestion 应列出全部四个支持城市：' + sug);
  }
}

// ── 3. 非法日期 → 拒绝 ─────────────────────────────────────
async function testInvalidDate(): Promise<void> {
  const bad: string[] = ['2026-02-30', '2026-13-01', '2026-12-32', 'not-a-date', '', '2026-1-1'];
  for (const d of bad) {
    const r: Captured = await run(['上海', d, '3', '2']);
    eq(r.payload['status'] as string, 'failed', '非法日期应失败：' + (d.length === 0 ? '(空)' : d));
    eq(r.payload['errCode'] as string, 'ERR_INVALID_PARAMS', '错误码应为 ERR_INVALID_PARAMS');
    ok((r.payload['suggestion'] as string).length > 0, '失败应带 suggestion');
  }
}

// ── 4. 天数 / 人数越界 → 拒绝 ──────────────────────────────
async function testOutOfRange(): Promise<void> {
  const badDays: string[] = ['0', '31', '100', '-1', '3.5', 'abc'];
  for (const d of badDays) {
    const r: Captured = await run(['上海', FUTURE, d, '2']);
    eq(r.payload['status'] as string, 'failed', '天数越界应失败：' + d);
    eq(r.payload['errCode'] as string, 'ERR_INVALID_PARAMS', '错误码应为 ERR_INVALID_PARAMS');
  }
  const badPeople: string[] = ['0', '31', '100', '-2', '2.5', 'x'];
  for (const p of badPeople) {
    const r: Captured = await run(['上海', FUTURE, '3', p]);
    eq(r.payload['status'] as string, 'failed', '人数越界应失败：' + p);
    eq(r.payload['errCode'] as string, 'ERR_INVALID_PARAMS', '错误码应为 ERR_INVALID_PARAMS');
  }
}

// ── 5. 省略天数人数 → 默认 3 天 2 人 ────────────────────────
async function testDefaults(): Promise<void> {
  const r: Captured = await run(['上海', FUTURE]);
  eq(r.payload['status'] as string, 'success', '省略天数人数应成功');
  const data: Record<string, Object> = r.payload['data'] as Record<string, Object>;
  eq(data['days'] as number, 3, '默认天数应为 3');
  eq(data['people'] as number, 2, '默认人数应为 2');
}

// ── 6. 过去日期：拒绝（2026-11-13 修缺陷 A）────────────────────
// 拒绝的理由：屏2 的日期选择器不允许选过去，过去日期进了预填会被屏2 改写，
// 于是小艺说「已记下 X 日」而界面显示别的日期，两边对不上。
async function testPastDateRejected(): Promise<void> {
  const r: Captured = await run(['上海', YESTERDAY, '3', '2']);
  eq(r.payload['status'] as string, 'failed', '过去日期应被拒绝');
  eq(r.payload['errCode'] as string, 'ERR_INVALID_PARAMS', '错误码应为 ERR_INVALID_PARAMS');
  const sug: string = r.payload['suggestion'] as string;
  ok(sug.indexOf('过去') >= 0, 'suggestion 应说明日期已过去：' + sug);
  ok(r.payload['data'] === undefined, '失败不应带 data');
}

// ── 6b. 当天与将来的日期照常接受 ────────────────────────────
async function testTodayAndFutureAccepted(): Promise<void> {
  const todayRun: Captured = await run(['上海', TODAY, '3', '2']);
  eq(todayRun.payload['status'] as string, 'success', '当天出发应成功');
  const futureRun: Captured = await run(['上海', FUTURE, '3', '2']);
  eq(futureRun.payload['status'] as string, 'success', '将来的日期应成功');
}

// ── 6c. 天数 1 就是 1 天（缺陷 B 的 Skill 侧：脚本不许把它当默认值）──
async function testOneDay(): Promise<void> {
  const r: Captured = await run(['上海', FUTURE, '1', '2']);
  eq(r.payload['status'] as string, 'success', '1 天应成功');
  const data: Record<string, Object> = r.payload['data'] as Record<string, Object>;
  eq(data['days'] as number, 1, 'days 应为 1（不是默认 3）');
}

// ── 7. message 文案 + launched 语义 ────────────────────────
async function testMessage(): Promise<void> {
  const r: Captured = await run(['上海', FUTURE, '4', '3']);
  const data: Record<string, Object> = r.payload['data'] as Record<string, Object>;
  const msg: string = data['message'] as string;
  ok(msg.indexOf('上海') >= 0, 'message 应含目的地：' + msg);
  ok(msg.indexOf(md(FUTURE)) >= 0, 'message 应含出发日：' + msg);
  ok(msg.indexOf('4天') >= 0, 'message 应含天数：' + msg);
  ok(msg.indexOf('3人') >= 0, 'message 应含人数：' + msg);
  // 手机上 startAbility 必报 201（后台拉起限制），launched 应为 false
  eq(data['launched'] as boolean, false, '手机路径 launched 应为 false');
}

// ── 8. SkillPrefill 取后即删 ───────────────────────────────
function testPrefillTakeOnce(): void {
  const rec: SkillPrefillRecord = {
    destination: '上海', start: FUTURE, days: 4, people: 3, savedAt: Date.now()
  };
  ok(SkillPrefill.save({} as common.Context, rec), '预填应写入成功');
  const got: SkillPrefillRecord | null = SkillPrefill.take({} as common.Context);
  ok(got !== null, '预填应能取出');
  if (got !== null) {
    eq(got.destination, '上海', 'destination 应一致');
    eq(got.start, FUTURE, 'start 应一致');
    eq(got.days, 4, 'days 应一致');
    eq(got.people, 3, 'people 应一致');
  }
  ok(SkillPrefill.take({} as common.Context) === null, '取后即删，第二次应为空');
}

// ── 9. 过期预填被拒 ────────────────────────────────────────
function testPrefillExpiry(): void {
  const stale: SkillPrefillRecord = {
    destination: '上海', start: FUTURE, days: 4, people: 3,
    savedAt: Date.now() - 3 * 60 * 60 * 1000
  };
  ok(SkillPrefill.save({} as common.Context, stale), '写入应成功（写入不判龄）');
  ok(SkillPrefill.take({} as common.Context) === null, '超过 2 小时的预填应被拒');
}

// ── 10. 非法字段预填被拒 ───────────────────────────────────
function testPrefillInvalid(): void {
  const bads: SkillPrefillRecord[] = [
    { destination: '', start: FUTURE, days: 4, people: 3, savedAt: Date.now() },
    { destination: '上海', start: '2026-02-30', days: 4, people: 3, savedAt: Date.now() },
    { destination: '上海', start: FUTURE, days: 0, people: 3, savedAt: Date.now() },
    { destination: '上海', start: FUTURE, days: 31, people: 3, savedAt: Date.now() },
    { destination: '上海', start: FUTURE, days: 4, people: 0, savedAt: Date.now() },
    { destination: '上海', start: FUTURE, days: 4, people: 31, savedAt: Date.now() }
  ];
  for (const b of bads) {
    ok(SkillPrefill.save({} as common.Context, b), '写入应成功');
    ok(SkillPrefill.take({} as common.Context) === null, '非法预填应被拒：' + JSON.stringify(b));
  }
}

// ── 11. clear 后为空 ───────────────────────────────────────
function testPrefillClear(): void {
  const rec: SkillPrefillRecord = {
    destination: '北京', start: FUTURE, days: 3, people: 2, savedAt: Date.now()
  };
  ok(SkillPrefill.save({} as common.Context, rec), '写入应成功');
  SkillPrefill.clear({} as common.Context);
  ok(SkillPrefill.take({} as common.Context) === null, 'clear 后应为空');
}

export async function runAll(): Promise<void> {
  await testCities();
  await testUnsupportedCity();
  await testInvalidDate();
  await testOutOfRange();
  await testDefaults();
  await testPastDateRejected();
  await testTodayAndFutureAccepted();
  await testOneDay();
  await testMessage();
  testPrefillTakeOnce();
  testPrefillExpiry();
  testPrefillInvalid();
  testPrefillClear();
  console.log('SKILL_ASSERTIONS_OK cases=' + cases);
}
