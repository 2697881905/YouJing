/**
 * 真模型提示词回归探针（一次性付费调用，默认不跑）。
 *
 * 为什么要有它：提示词是 SOT，但「App 编译过」不代表模型照做；BFF 单测只能验措辞，
 * 验不了真实输出。以往每次都是临时脚本，结论留在聊天里没法复跑。这个工具把
 * 「生成一次 → 用 BFF 同款 validator 判 → 再按规则 13/17/19/20 做业务断言」固定下来。
 *
 * 用法：
 *   node tools/probe_llm_rules.mjs --days 1 --yes     # 约 ¥0.003
 *   node tools/probe_llm_rules.mjs --days 3 --yes     # 约 ¥0.005
 *   node tools/probe_llm_rules.mjs --days 1 --yes --free-tier   # 免费档提示词变体
 *   node tools/probe_llm_rules.mjs --days 1 --yes --mapkit      # 任意城市（MapKit）形态
 * 不带 --yes 只打印将要花的钱与请求规模，不发起调用。
 *
 * 结构类断言（任一不成立则退出码 1）：
 *   1) BFF validateTrip 通过（结构/枚举/天数窗口）
 *   2) 每天午餐、晚餐各至少一条（规则 4/13）
 *   3) 没有与 meals 重复的通用用餐活动（规则 18：游览性小吃/下午茶仍允许）
 *   4) 当日活动按时间不重叠（LLM 常见失败态：两个活动同一时段）
 *   5) accommodation 缺省或等于用户选的住宿区域（规则 20）
 *
 * 规则 19（每天活动+通勤 ≤480min）默认是 **WARN 不是 FAIL**：
 * 产品口径是不静默裁剪、由屏8「去减一站」兜底（2026-11-03 真实输出出现过 505/570min）。
 * 要把它当硬门槛时加 `--strict`。
 */
import dotenv from '../bff/node_modules/dotenv/lib/main.js';
import { buildMessages, buildResponseFormat } from '../bff/src/prompt/index.js';
import { proxyLlmRequest } from '../bff/src/services/llm.js';
import { validateTrip } from '../bff/src/prompt/trip-validator.js';
import { richRequest } from '../bff/test/fixtures/trip.js';

const args = process.argv.slice(2);
const daysArg = args.indexOf('--days');
const days = daysArg >= 0 ? Number(args[daysArg + 1]) : 1;
const confirmed = args.includes('--yes');
const strict = args.includes('--strict');
const freeTier = args.includes('--free-tier');
const mapkit = args.includes('--mapkit');

if (!Number.isInteger(days) || days < 1 || days > 7) {
  console.error('--days 必须是 1–7 的整数');
  process.exit(2);
}

dotenv.config({ path: new URL('../bff/.env', import.meta.url).pathname });
if (!process.env.DEEPSEEK_API_KEY) {
  console.error('DEEPSEEK_API_KEY 未配置（bff/.env）');
  process.exit(2);
}

const body = richRequest();
body.startDate = '2026-11-10';
const end = new Date(Date.parse(body.startDate) + (days - 1) * 86400000);
body.endDate = end.toISOString().slice(0, 10);
body.selectedSpots = body.spots.map((s) => ({ name: s.name, priority: 'must' }));
if (mapkit) {
  // 任意城市（MapKit）形态：没有预约字段、有开放时间、住宿区来自地图服务
  body.spots[0].provenance = { source: 'MapKit 地点检索', updatedAt: '2026-11-01', confidence: '中' };
  body.spots[0].booking = { requiresBooking: false };
  body.spots[0].openingHours = '8:00–22:00';
  body.area.source = 'MapKit';
}

const messages = buildMessages(body, { freeTier });
const promptChars = messages.reduce((sum, m) => sum + m.content.length, 0);
console.log(`请求：${days} 天 · ${freeTier ? '免费档' : '付费档'}提示词 · ` +
  `${mapkit ? 'MapKit 形态' : '种子城市形态'} · ` +
  `system+user ${promptChars} 字符 · 预计 ¥${(days === 1 ? 0.003 : 0.005)}`);
if (mapkit) {
  const user = messages[1].content;
  if (user.indexOf('预约信息未获取，以官方为准') < 0 || user.indexOf('地图服务区县') < 0) {
    console.error('MapKit 提示词口径不对：用户消息里缺少「未获取/地图服务区县」');
    process.exit(1);
  }
}
if (!confirmed) {
  console.log('未带 --yes：只做了预算与请求检查，未发起真实调用。');
  process.exit(0);
}

const result = await proxyLlmRequest(messages, {
  maxTokens: 8192,
  thinkingDisabled: true,
  responseFormat: buildResponseFormat(process.env.LLM_RESPONSE_FORMAT || 'json_object')
});

let trip;
try {
  trip = JSON.parse(result.content);
} catch (e) {
  console.error('JSON 解析失败：', e.message);
  console.error('--- 头部 ---\n' + result.content.slice(0, 400));
  console.error('--- 尾部 ---\n' + result.content.slice(-400));
  process.exit(1);
}

const check = validateTrip(trip, { days, startDate: body.startDate });
const failures = [];
const warnings = [];
if (!check.valid) failures.push(`validator: ${check.errors.join('; ')}`);

const areaName = body.area.name;
const perDay = [];
for (const [i, day] of (trip.days || []).entries()) {
  const meals = Array.isArray(day.meals) ? day.meals : [];
  const lunch = meals.filter((m) => m.type === 'lunch').length;
  const dinner = meals.filter((m) => m.type === 'dinner').length;
  if (lunch < 1 || dinner < 1) failures.push(`D${i + 1}: 午/晚餐次不足 (${lunch}/${dinner})`);

  const foodActs = (day.activities || []).filter((a) => a.category === 'food');
  // 规则 18 只禁止「与餐次重复的通用用餐活动」；回民街逛吃/下午茶这类游览性餐饮是允许的。
  // 第一版探针把 food 活动一律判失败，会把合法输出打成缺陷（自证扫描器要先能区分两者）。
  const mealNames = meals.map((m) => String(m.name || '').trim()).filter((n) => n.length > 0);
  const genericMeal = /午餐|晚餐|早餐|午饭|晚饭|早饭/;
  const dupFood = foodActs.filter((a) => {
    const title = String(a.title || '').trim();
    if (genericMeal.test(title)) return true;
    return mealNames.some((n) => title === n || title.indexOf(n) >= 0 || n.indexOf(title) >= 0);
  });
  if (dupFood.length > 0) {
    failures.push(`D${i + 1}: food 活动与餐次重复 ${dupFood.map((a) => a.title).join(' / ')}`);
  }

  const minutes = (day.activities || []).reduce((sum, a) => {
    const [sh, sm] = String(a.time || '0:0').split(':').map(Number);
    const [eh, em] = String(a.endTime || '0:0').split(':').map(Number);
    const stayMin = Math.max(0, (eh * 60 + em) - (sh * 60 + sm));
    const leg = a.transport && Number.isFinite(a.transport.duration) ? a.transport.duration : 0;
    return sum + stayMin + leg;
  }, 0);
  if (minutes > 480) {
    (strict ? failures : warnings).push(`D${i + 1}: 活动+通勤 ${minutes}min > 480（规则 19）`);
  }

  // 同日活动时间不得重叠：重叠会让屏8 时间轴出现两个并行节点，DayLoad 也会重复计分钟
  const spans = (day.activities || [])
    .map((a) => [a.time, a.endTime])
    .filter(([t, e]) => /^\d{2}:\d{2}$/.test(String(t)) && /^\d{2}:\d{2}$/.test(String(e)))
    .map(([t, e]) => [Number(String(t).slice(0, 2)) * 60 + Number(String(t).slice(3, 5)),
      Number(String(e).slice(0, 2)) * 60 + Number(String(e).slice(3, 5))])
    .sort((x, y) => x[0] - y[0]);
  for (let k = 1; k < spans.length; k += 1) {
    if (spans[k][0] < spans[k - 1][1]) {
      failures.push(`D${i + 1}: 活动重叠 ${String(spans[k - 1][0] / 60 | 0).padStart(2, '0')}:` +
        `${String(spans[k - 1][0] % 60).padStart(2, '0')} 与 ${String(spans[k][0] / 60 | 0).padStart(2, '0')}:` +
        `${String(spans[k][0] % 60).padStart(2, '0')}`);
      break;
    }
  }

  // 规则 20 的意图是「不要编造具体酒店名」，不是逐字相等：
  // 真实输出出现过「碑林区（永宁门）」——永宁门是用户消息里的锚定站，属区域内更具体的说明。
  if (day.accommodation !== undefined && String(day.accommodation).indexOf(areaName) < 0) {
    failures.push(`D${i + 1}: accommodation='${day.accommodation}' 不是用户选的「${areaName}」`);
  }
  perDay.push({
    day: i + 1,
    activities: (day.activities || []).length,
    lunch,
    dinner,
    minutes,
    foodActivities: foodActs.map((a) => String(a.title || '')),
    accommodation: day.accommodation === undefined ? '(省略)' : day.accommodation
  });
}

console.log(JSON.stringify({
  model: result.usage.model,
  tokens: { prompt: result.usage.promptTokens, completion: result.usage.completionTokens },
  validator: { valid: check.valid, errors: check.errors },
  days: trip.days ? trip.days.length : 0,
  tips: Array.isArray(trip.tips) ? trip.tips : [],
  perDay
}, null, 2));

if (warnings.length > 0) {
  console.warn('\nPROBE_WARN（不判失败；屏8 会显示超建议并提供「去减一站」）\n- ' + warnings.join('\n- '));
}
if (failures.length > 0) {
  console.error('\nPROBE_FAIL\n- ' + failures.join('\n- '));
  process.exit(1);
}
console.log('\nPROBE_OK 结构类规则 4/13/18/20 + 不重叠在真实输出上成立');
