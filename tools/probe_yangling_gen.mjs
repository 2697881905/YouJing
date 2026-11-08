/**
 * 杨凌 1 天真模型生成探针（P0/P1 验收购建，默认不跑）。
 *
 * 为什么单独一个工具：`probe_llm_rules.mjs` 用的是西安夹具，只能验提示词结构；
 * 杨凌验收要求「10 站种子 + 1 天 + 选 3 站」。这里直接读 rawfile 种子，
 * 用真实模型走 BFF 同款 buildMessages → proxyLlmRequest → validateTrip，
 * 再按 App 的 DayLoadCalc 口径复核规则 19（交通节点不重复计通勤）。
 *
 * 用法：
 *   node tools/probe_yangling_gen.mjs            # 只打印预算与请求规模，不花钱
 *   node tools/probe_yangling_gen.mjs --yes      # 真模型生成一次，约 ¥0.003
 *
 * 判据：
 *   1) validator 通过（结构/枚举/天数窗口）
 *   2) 午餐、晚餐各至少一条（规则 4/13）
 *   3) 活动时间不重叠
 *   4) accommodation 缺省或包含所选片区（规则 20）
 *   5) DayLoad 按 600min 窗口打印三态；≥480 只 WARN（产品口径：屏8「去减一站」兜底）
 */
import dotenv from '../bff/node_modules/dotenv/lib/main.js';
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { buildMessages, buildResponseFormat } from '../bff/src/prompt/index.js';
import { proxyLlmRequest } from '../bff/src/services/llm.js';
import { validateTrip } from '../bff/src/prompt/trip-validator.js';

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
const SEED = join(ROOT, 'entry/src/main/resources/rawfile/seed');
const confirmed = process.argv.includes('--yes');

dotenv.config({ path: join(ROOT, 'bff/.env') });
if (!process.env.DEEPSEEK_API_KEY) {
  console.error('DEEPSEEK_API_KEY 未配置（bff/.env）');
  process.exit(2);
}

function readJsonl(path) {
  return readFileSync(path, 'utf8')
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .map((line) => JSON.parse(line));
}

function toSpot(s) {
  const booking = { requiresBooking: s.bk.req === true };
  if (typeof s.bk.m === 'string' && s.bk.m.length > 0) booking.bookingMethod = s.bk.m;
  if (Number.isInteger(s.bk.adv) && s.bk.adv > 0) booking.advanceDays = s.bk.adv;
  if (typeof s.bk.rel === 'string' && s.bk.rel.length > 0) booking.releaseTime = s.bk.rel;
  if (typeof s.bk.closed === 'string' && s.bk.closed.length > 0) booking.closedDay = s.bk.closed;
  return {
    id: s.id,
    name: s.n,
    city: '杨凌',
    tags: s.t,
    brief: '',
    suggestedDuration: s.dur,
    popularity: s.pop,
    nearbySpotIds: [],
    longitude: s.lo,
    latitude: s.la,
    district: s.d,
    nearestMetro: '',
    booking,
    provenance: { source: 'seed', updatedAt: '2026-11-01' }
  };
}

function toArea(a) {
  return {
    name: a.n,
    priceTier: a.tier,
    metroLines: a.lines,
    anchorStations: a.st,
    airportMinutes: a.air,
    trainStationMinutes: a.train,
    source: 'seed'
  };
}

const spots = readJsonl(join(SEED, 'spots_yangling.jsonl')).map(toSpot);
const areas = readJsonl(join(SEED, 'areas_yangling.jsonl')).map(toArea);
if (spots.length !== 10) {
  console.error(`杨凌种子应为 10 站，实际 ${spots.length}`);
  process.exit(2);
}
const area = areas[0];
// 与 P2/P3 验收同场景：1 天选 3 站，剩 7 个候选
const must = ['yl-001', 'yl-002', 'yl-005'];
const selectedSpots = spots
  .filter((s) => must.indexOf(s.id) >= 0)
  .map((s) => ({ name: s.name, priority: 'must' }));

const today = new Date();
const start = new Date(today.getTime() + 86400000);
const startDate = `${start.getFullYear()}-${String(start.getMonth() + 1).padStart(2, '0')}-${String(start.getDate()).padStart(2, '0')}`;
const body = {
  destination: '杨凌',
  startDate,
  endDate: startDate,
  people: 2,
  budget: 800,
  style: 'leisure',
  stayTier: 'comfort',
  transit: 'public',
  paces: ['standard'],
  selectedArea: { name: area.name },
  selectedSpots,
  area,
  spots,
  freeTier: false
};

const messages = buildMessages(body, { freeTier: false });
const promptChars = messages.reduce((sum, m) => sum + m.content.length, 0);
console.log(`请求：杨凌 1 天 · ${spots.length} 候选 / ${selectedSpots.length} 必去 · ` +
  `片区「${area.name}」· system+user ${promptChars} 字符 · 预计 ¥0.003`);
if (!confirmed) {
  console.log('未带 --yes：只做了预算与请求检查，未发起真实调用。');
  process.exit(0);
}

const started = Date.now();
const result = await proxyLlmRequest(messages, {
  maxTokens: 8192,
  thinkingDisabled: true,
  responseFormat: buildResponseFormat(process.env.LLM_RESPONSE_FORMAT || 'json_object')
});
const elapsed = Date.now() - started;

let trip;
try {
  trip = JSON.parse(result.content);
} catch (e) {
  const rawPath = `/tmp/yangling-raw-${Date.now()}.json`;
  writeFileSync(rawPath, result.content, 'utf8');
  console.error('JSON 解析失败：', e.message, '原始输出已存：', rawPath);
  process.exit(1);
}

const check = validateTrip(trip, { days: 1, startDate });
const failures = [];
const warnings = [];
if (!check.valid) failures.push(`validator: ${check.errors.join('; ')}`);

const day = trip.days && trip.days[0] ? trip.days[0] : null;
if (day === null) {
  failures.push('没有 days[0]');
}
const activities = day ? (day.activities || []) : [];
const meals = day && Array.isArray(day.meals) ? day.meals : [];
const lunch = meals.filter((m) => m.type === 'lunch').length;
const dinner = meals.filter((m) => m.type === 'dinner').length;
if (lunch < 1 || dinner < 1) failures.push(`午/晚餐次不足 (${lunch}/${dinner})`);

// 与 DayLoadCalc 同口径：交通节点只取时段或 duration 之一
let stay = 0;
let transit = 0;
for (const a of activities) {
  const [sh, sm] = String(a.time || '0:0').split(':').map(Number);
  const [eh, em] = String(a.endTime || '0:0').split(':').map(Number);
  const span = Math.max(0, (eh * 60 + em) - (sh * 60 + sm));
  const t = a.transport && Number.isFinite(a.transport.duration) ? a.transport.duration : 0;
  if (a.category === 'transport') {
    transit += span > 0 ? span : t;
  } else {
    stay += span;
    transit += t;
  }
}
const minutes = stay + transit;
const level = minutes > 600 ? 'OVER' : (minutes >= 480 ? 'WARN' : 'OK');
if (level !== 'OK') {
  warnings.push(`DayLoad ${minutes}min（停留 ${stay} + 通勤 ${transit}）→ ${level}；` +
    '产品口径为 WARN + 屏8「去减一站」，不判失败');
}

const spans = activities
  .map((a) => [a.time, a.endTime])
  .filter(([t, e]) => /^\d{2}:\d{2}$/.test(String(t)) && /^\d{2}:\d{2}$/.test(String(e)))
  .map(([t, e]) => [Number(String(t).slice(0, 2)) * 60 + Number(String(t).slice(3, 5)),
    Number(String(e).slice(0, 2)) * 60 + Number(String(e).slice(3, 5))])
  .sort((x, y) => x[0] - y[0]);
for (let i = 1; i < spans.length; i += 1) {
  if (spans[i][0] < spans[i - 1][1]) {
    failures.push(`活动重叠 ${spans[i - 1]} 与 ${spans[i]}`);
    break;
  }
}

if (day && day.accommodation !== undefined && String(day.accommodation).indexOf(area.name) < 0) {
  failures.push(`accommodation='${day.accommodation}' 不是所选「${area.name}」`);
}

const sumDaily = (trip.days || []).reduce(
  (s, d) => s + (Number.isFinite(d.dailyCost) ? d.dailyCost : 0), 0);
const rawTotalCost = trip.overview && Number.isFinite(trip.overview.totalCost)
  ? trip.overview.totalCost : 0;
// 与 LlmClient 落库口径一致：总费用归一为各天合计（规则 7 只要求「约等于」，
// 真实输出出现过 totalCost 与 ΣdailyCost 差 2 倍；费用页展示总览、每日卡展示 dailyCost，
// 合计是唯一自洽的口径）。
const normalizedTotalCost = sumDaily > 0 ? sumDaily : rawTotalCost;

console.log(JSON.stringify({
  model: result.usage.model,
  ms: elapsed,
  tokens: { prompt: result.usage.promptTokens, completion: result.usage.completionTokens },
  validator: { valid: check.valid, errors: check.errors },
  theme: day ? day.theme : null,
  activities: activities.map((a) => `${a.time}-${a.endTime} ${a.title}`),
  meals: meals.map((m) => `${m.type} ${m.time || ''} ${m.name || ''}`.trim()),
  dayLoad: { stay, transit, minutes, window: 600, level },
  accommodation: day ? day.accommodation : null,
  cost: { rawTotalCost, normalizedTotalCost, sumDaily },
  summary: trip.overview ? trip.overview.summary : null
}, null, 2));

if (warnings.length > 0) {
  console.warn('\nPROBE_WARN（不判失败；屏8 会显示超建议并提供「去减一站」）\n- ' + warnings.join('\n- '));
}
if (failures.length > 0) {
  console.error('\nPROBE_FAIL\n- ' + failures.join('\n- '));
  process.exit(1);
}
console.log('\nPROBE_OK 杨凌 1 天生成通过（规则 4/13/20 + 不重叠）');
