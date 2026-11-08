'use strict';

/**
 * 有径 · 当日行程重排云函数（方案 §3.4）。
 * 只做：鉴权 → 校验请求 → 服务端重算剩余 → 调 LLM 决策 → 守卫响应。
 * 不做时间算术：具体时刻由端侧 SkipPlanner 计算。
 */

const SCHEMA_VERSION = 1;
const MAX_KEEP = 20;
const MIN_DWELL = 15;
const MAX_DWELL = 240;
const MAX_FREE_BLOCKS = 3;
const MIN_FREE_MIN = 15;
const MAX_FREE_MIN = 480;
const MAX_NOTE = 200;
const MAX_BODY_BYTES = 64 * 1024;
const MAX_ACTIVITIES = 100;
const MAX_MEALS = 10;
const UPSTREAM_TIMEOUT_MS = 5000;
const ANCHOR_CATEGORIES = ['transport', 'hotel'];
const CATEGORIES = ['transport', 'sight', 'food', 'shop', 'rest', 'hotel', 'other'];
const STATUSES = ['booked', 'not_booked', 'full', 'pending', 'no_need'];
const MEAL_TYPES = ['breakfast', 'lunch', 'dinner'];

function respond(statusCode, body) {
  return {
    statusCode: statusCode,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
    body: JSON.stringify(body)
  };
}

function fail(statusCode, code, message) {
  return respond(statusCode, { code: code, message: message });
}

function isTime(value) {
  if (typeof value !== 'string' || !/^\d{2}:\d{2}$/.test(value)) {
    return false;
  }
  const h = Number(value.slice(0, 2));
  const m = Number(value.slice(3, 5));
  return h <= 23 && m <= 59;
}

function minutesOf(hhmm) {
  return Number(hhmm.slice(0, 2)) * 60 + Number(hhmm.slice(3, 5));
}

function hhmm(minutes) {
  const clamped = Math.max(0, Math.min(1439, Math.round(minutes)));
  return `${String(Math.floor(clamped / 60)).padStart(2, '0')}:${String(clamped % 60).padStart(2, '0')}`;
}

function headerOf(event, name) {
  const headers = (event && event.headers) || {};
  const wanted = name.toLowerCase();
  for (const key of Object.keys(headers)) {
    if (key.toLowerCase() === wanted) {
      return String(headers[key]);
    }
  }
  return '';
}

function parseBody(event) {
  const raw = event && event.body;
  if (raw === undefined || raw === null) {
    return null;
  }
  if (typeof raw === 'object') {
    return raw;
  }
  if (typeof raw !== 'string') {
    return null;
  }
  let text = raw;
  if (event.isBase64Encoded) {
    text = Buffer.from(raw, 'base64').toString('utf8');
  }
  if (Buffer.byteLength(text, 'utf8') > MAX_BODY_BYTES) {
    return null;
  }
  try {
    return JSON.parse(text);
  } catch (err) {
    return null;
  }
}

function normalizeRequest(body) {
  if (!body || body.schemaVersion !== SCHEMA_VERSION) {
    return null;
  }
  if (!isTime(body.now)) {
    return null;
  }
  const hasIntent = typeof body.intentText === 'string' && body.intentText.trim().length > 0;
  if (hasIntent && body.intentText.length > 200) {
    return null;
  }
  const actions = [];
  if (typeof body.skippedId === 'string' && body.skippedId.length > 0) {
    actions.push('skip');
  }
  if (typeof body.addStopId === 'string' && body.addStopId.length > 0) {
    actions.push('add');
  }
  if (typeof body.replaceStopId === 'string' && body.replaceStopId.length > 0) {
    actions.push('replace');
  }
  if (hasIntent) {
    if (actions.length !== 0) {
      return null;
    }
  } else if (actions.length !== 1) {
    return null;
  }
  const action = hasIntent ? 'intent' : actions[0];
  const targetId = hasIntent ? '' : (action === 'skip' ? body.skippedId :
    (action === 'add' ? body.addStopId : body.replaceStopId));
  const day = body.day;
  if (!day || typeof day.date !== 'string' || !Array.isArray(day.activities) ||
      !Array.isArray(day.meals)) {
    return null;
  }
  if (day.activities.length > MAX_ACTIVITIES || day.meals.length > MAX_MEALS) {
    return null;
  }
  const ids = new Set();
  const activities = [];
  for (const a of day.activities) {
    if (!a || typeof a.id !== 'string' || a.id.length === 0 || ids.has(a.id)) {
      return null;
    }
    if (!isTime(a.time) || !isTime(a.endTime)) {
      return null;
    }
    if (typeof a.title !== 'string' || a.title.length > 200) {
      return null;
    }
    if (CATEGORIES.indexOf(a.category) < 0 || STATUSES.indexOf(a.status) < 0) {
      return null;
    }
    ids.add(a.id);
    let transport = 0;
    if (a.transport !== undefined && a.transport !== null) {
      if (typeof a.transport.duration !== 'number' || !Number.isFinite(a.transport.duration)) {
        return null;
      }
      transport = Math.max(0, Math.floor(a.transport.duration));
    }
    activities.push({
      id: a.id,
      time: a.time,
      endTime: a.endTime,
      title: a.title,
      category: a.category,
      status: a.status,
      transport: transport
    });
  }
  const target = hasIntent ? null : activities.find((a) => a.id === targetId);
  if (!hasIntent) {
    if (!target) {
      return null;
    }
    if (ANCHOR_CATEGORIES.indexOf(target.category) >= 0 ||
        target.category === 'rest' || target.status === 'booked') {
      return null;
    }
    // 加一站只接受「今天还没开始」的站点；换一站端侧确定性改写，不走 LLM
    if (action === 'add' && minutesOf(target.time) < minutesOf(body.now)) {
      return null;
    }
  }
  const candidates = [];
  if (Array.isArray(body.candidates)) {
    if (body.candidates.length > MAX_ACTIVITIES) {
      return null;
    }
    const candidateIds = new Set();
    for (const c of body.candidates) {
      if (!c || typeof c.id !== 'string' || c.id.length === 0 || candidateIds.has(c.id)) {
        return null;
      }
      if (typeof c.title !== 'string' || c.title.length === 0 || c.title.length > 200) {
        return null;
      }
      if (CATEGORIES.indexOf(c.category) < 0 || STATUSES.indexOf(c.status) < 0) {
        return null;
      }
      if (!isTime(c.time) || !isTime(c.endTime)) {
        return null;
      }
      candidateIds.add(c.id);
      candidates.push({
        id: c.id, time: c.time, endTime: c.endTime, title: c.title,
        category: c.category, status: c.status
      });
    }
  }
  const meals = [];
  for (const m of day.meals) {
    if (!m || MEAL_TYPES.indexOf(m.type) < 0) {
      return null;
    }
    meals.push({ type: m.type, time: isTime(m.time) ? m.time : undefined });
  }
  return {
    now: body.now,
    action: action,
    targetId: targetId,
    skippedId: action === 'skip' ? targetId : undefined,
    addStopId: action === 'add' ? targetId : undefined,
    replaceStopId: action === 'replace' ? targetId : undefined,
    intentText: hasIntent ? body.intentText.trim() : undefined,
    candidates: candidates,
    day: { date: day.date, activities: activities, meals: meals }
  };
}

function remainingOf(request) {
  const nowMin = minutesOf(request.now);
  return request.day.activities
    .filter((a) => {
      if (request.action === 'skip' && a.id === request.skippedId) {
        return false;
      }
      return ANCHOR_CATEGORIES.indexOf(a.category) < 0 &&
        a.status !== 'booked' &&
        minutesOf(a.time) >= nowMin;
    })
    .sort((x, y) => minutesOf(x.time) - minutesOf(y.time));
}

function anchorsOf(request) {
  const skipped = request.day.activities.find((a) => a.id === request.skippedId);
  const spans = [];
  for (const a of request.day.activities) {
    if (request.action === 'skip' && a.id === request.skippedId) {
      continue;
    }
    if (request.action === 'add' && a.id === request.addStopId) {
      continue;
    }
    if (ANCHOR_CATEGORIES.indexOf(a.category) < 0 && a.status !== 'booked') {
      continue;
    }
    spans.push({ label: a.title, start: a.time, end: a.endTime });
  }
  for (const m of request.day.meals) {
    if (!m.time) {
      continue;
    }
    const start = minutesOf(m.time);
    spans.push({ label: `餐次 ${m.type}`, start: m.time, end: hhmm(Math.min(1439, start + 60)) });
  }
  if (skipped) {
    spans.push({ label: '本次空闲段', start: skipped.time, end: skipped.endTime });
  }
  return spans;
}

function promptFor(request, remaining) {
  const isAdd = request.action === 'add';
  const target = request.day.activities.find((a) => a.id === request.targetId);
  const system = [
    isAdd
      ? '你是有径 App 的行程重排助手。用户在当日行程中新增了一站，需要你对剩余站点（含新增站）重新排序并给出停留时长。'
      : '你是有径 App 的行程重排助手。用户放弃了下一站，需要你对当日剩余站点重新排序并给出停留时长。',
    '你只做决策，不做时间算术：不要输出任何具体开始/结束时刻。',
    '必须遵守：',
    '1. keep 必须恰好包含 remaining 里的每个 id 一次，不得新增、遗漏或重复；',
    '2. 每个 dwellMin 是 15–240 的整数分钟；',
    '3. freeBlocks 最多 3 块，afterId 必须是 activities 里已存在的 id，minutes 是 15–480 的整数；',
    '4. note 不超过 200 字，给用户一句中文说明；',
    '5. 只输出 JSON，不要 Markdown 围栏或解释。',
    '输出格式：{"schemaVersion":1,"keep":[{"id":"...","dwellMin":60}],"freeBlocks":[],"note":"..."}'
  ].join('\n');
  const user = JSON.stringify({
    now: request.now,
    date: request.day.date,
    target: {
      action: request.action,
      id: target.id,
      title: target.title,
      time: target.time,
      endTime: target.endTime
    },
    remaining: remaining.map((a) => ({
      id: a.id,
      title: a.title,
      time: a.time,
      endTime: a.endTime,
      category: a.category
    })),
    anchors: anchorsOf(request),
    meals: request.day.meals
  });
  return { system: system, user: user };
}

function intentPromptFor(request) {
  const nowMin = minutesOf(request.now);
  const future = request.day.activities.filter((a) => minutesOf(a.time) >= nowMin);
  const system = [
    '你是有径 App 的行程助手。把用户的一句自然语言意愿映射成四种动作之一。',
    '动作含义：',
    '- skip：跳过某一站；skipRemaining=true 表示把今天后续未开始的站一并结束；',
    '- shift：把今天后续行程整体顺延 shiftMinutes 分钟（15–240）；',
    '- add：新增一站（端侧会打开选点面板，newStopId 可给推荐候选）；',
    '- replace：把某一站换成 candidates 里的另一站。',
    '必须遵守：',
    '1. 只输出 JSON：{"action":"skip|shift|add|replace","targetId":"...","newStopId":"...","shiftMinutes":30,"skipRemaining":false,"note":"..."}；',
    '2. skip/replace 必须给 targetId，且必须是 activities 里已存在的 id；',
    '3. replace 的 newStopId 必须来自 candidates；add 可省略 targetId；',
    '4. 不得编造 activities/candidates 里没有的站点或事实；',
    '5. note 不超过 100 字，用中文复述你理解到的意图。'
  ].join('\n');
  const user = JSON.stringify({
    now: request.now,
    date: request.day.date,
    intentText: request.intentText,
    activities: future.map((a) => ({
      id: a.id, title: a.title, time: a.time, endTime: a.endTime,
      category: a.category, status: a.status
    })),
    candidates: request.candidates
  });
  return { system: system, user: user };
}

async function callChat(messages, fetchImpl, env) {
  const url = env.LLM_CHAT_URL;
  const apiKey = env.LLM_API_KEY;
  const model = env.LLM_MODEL;
  if (!url || !apiKey || !model) {
    throw new Error('LLM env missing (LLM_CHAT_URL / LLM_API_KEY / LLM_MODEL)');
  }
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), UPSTREAM_TIMEOUT_MS);
  try {
    const resp = await fetchImpl(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${apiKey}` },
      body: JSON.stringify({
        model: model,
        temperature: 0.2,
        response_format: { type: 'json_object' },
        messages: messages
      }),
      signal: controller.signal
    });
    if (!resp || !resp.ok) {
      throw new Error(`upstream HTTP ${resp ? resp.status : 'no response'}`);
    }
    const data = await resp.json();
    const content = data && data.choices && data.choices[0] && data.choices[0].message &&
      data.choices[0].message.content;
    if (typeof content !== 'string' || content.length === 0) {
      throw new Error('upstream content missing');
    }
    return content;
  } finally {
    clearTimeout(timer);
  }
}

async function callLlm(request, remaining, fetchImpl, env) {
  const prompt = promptFor(request, remaining);
  return callChat([
    { role: 'system', content: prompt.system },
    { role: 'user', content: prompt.user }
  ], fetchImpl, env);
}

async function callIntentLlm(request, fetchImpl, env) {
  const prompt = intentPromptFor(request);
  return callChat([
    { role: 'system', content: prompt.system },
    { role: 'user', content: prompt.user }
  ], fetchImpl, env);
}

function extractJson(text) {
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start < 0 || end <= start) {
    throw new Error('response has no JSON body');
  }
  return text.slice(start, end + 1);
}

function guardDecision(raw, request, remaining) {
  if (!raw || raw.schemaVersion !== SCHEMA_VERSION) {
    throw new Error('schemaVersion mismatch');
  }
  if (!Array.isArray(raw.keep) || raw.keep.length > MAX_KEEP) {
    throw new Error('keep missing or too long');
  }
  if (raw.keep.length !== remaining.length) {
    throw new Error('keep must include every remaining id exactly once');
  }
  const allowed = new Set(remaining.map((a) => a.id));
  const seen = new Set();
  const keep = [];
  for (const item of raw.keep) {
    if (!item || typeof item.id !== 'string' || !allowed.has(item.id)) {
      throw new Error('keep contains unknown id');
    }
    if (seen.has(item.id)) {
      throw new Error('keep contains duplicate id');
    }
    if (!Number.isInteger(item.dwellMin) || item.dwellMin < MIN_DWELL || item.dwellMin > MAX_DWELL) {
      throw new Error('dwellMin out of range');
    }
    seen.add(item.id);
    keep.push({ id: item.id, dwellMin: item.dwellMin });
  }
  const rawBlocks = raw.freeBlocks === undefined || raw.freeBlocks === null ? [] : raw.freeBlocks;
  if (!Array.isArray(rawBlocks) || rawBlocks.length > MAX_FREE_BLOCKS) {
    throw new Error('freeBlocks invalid');
  }
  const allIds = new Set(request.day.activities.map((a) => a.id));
  const freeBlocks = [];
  for (const block of rawBlocks) {
    if (!block || typeof block.afterId !== 'string' || !allIds.has(block.afterId)) {
      throw new Error('freeBlocks.afterId unknown');
    }
    if (!Number.isInteger(block.minutes) ||
        block.minutes < MIN_FREE_MIN || block.minutes > MAX_FREE_MIN) {
      throw new Error('freeBlocks.minutes out of range');
    }
    freeBlocks.push({ afterId: block.afterId, minutes: block.minutes });
  }
  const note = typeof raw.note === 'string' ? raw.note : '';
  if (note.length > MAX_NOTE) {
    throw new Error('note too long');
  }
  return { schemaVersion: SCHEMA_VERSION, keep: keep, freeBlocks: freeBlocks, note: note };
}

function guardIntentDecision(raw, request) {
  const ACTIONS = ['skip', 'shift', 'add', 'replace'];
  if (!raw || ACTIONS.indexOf(raw.action) < 0) {
    throw new Error('action invalid');
  }
  const byId = new Map(request.day.activities.map((a) => [a.id, a]));
  const candidateIds = new Set((request.candidates || []).map((c) => c.id));
  const targetId = typeof raw.targetId === 'string' ? raw.targetId : '';
  const newStopId = typeof raw.newStopId === 'string' ? raw.newStopId : '';
  if (raw.action === 'skip' || raw.action === 'replace') {
    const target = byId.get(targetId);
    if (!target) {
      throw new Error('targetId unknown');
    }
    if (raw.action === 'skip' &&
        (ANCHOR_CATEGORIES.indexOf(target.category) >= 0 || target.category === 'rest' ||
         target.status === 'booked')) {
      throw new Error('target not skippable');
    }
  }
  if (raw.action === 'replace' && !candidateIds.has(newStopId)) {
    throw new Error('newStopId unknown');
  }
  if (raw.action === 'add' && newStopId && !candidateIds.has(newStopId)) {
    throw new Error('newStopId unknown');
  }
  let shiftMinutes;
  if (raw.action === 'shift') {
    if (!Number.isInteger(raw.shiftMinutes) || raw.shiftMinutes < 15 || raw.shiftMinutes > 240) {
      throw new Error('shiftMinutes out of range');
    }
    shiftMinutes = raw.shiftMinutes;
  }
  const note = typeof raw.note === 'string' ? raw.note.slice(0, MAX_NOTE) : '';
  const decision = {
    schemaVersion: SCHEMA_VERSION,
    keep: [],
    freeBlocks: [],
    action: raw.action,
    note: note
  };
  if (targetId) {
    decision.targetId = targetId;
  }
  if (newStopId) {
    decision.newStopId = newStopId;
  }
  if (shiftMinutes !== undefined) {
    decision.shiftMinutes = shiftMinutes;
  }
  if (typeof raw.skipRemaining === 'boolean') {
    decision.skipRemaining = raw.skipRemaining;
  }
  return decision;
}

async function handler(event, context, deps) {
  const env = (deps && deps.env) || process.env;
  const fetchImpl = (deps && deps.fetch) || globalThis.fetch;
  const expected = env.YOUJING_REPLAN_TOKEN;
  if (!expected) {
    return fail(500, 'SERVER_MISCONFIGURED', 'YOUJING_REPLAN_TOKEN 未配置');
  }
  if (headerOf(event, 'x-youjing-token') !== expected) {
    return fail(401, 'UNAUTHORIZED', 'token 不匹配');
  }
  const body = parseBody(event);
  if (!body) {
    return fail(400, 'BAD_REQUEST', '请求体不是合法 JSON');
  }
  const request = normalizeRequest(body);
  if (!request) {
    return fail(422, 'INVALID_REQUEST', '请求字段不合法');
  }
  if (request.action === 'replace') {
    // 换节点不换槽：端侧保留原时段与通勤，云函数不做 LLM 决策
    return respond(200, { schemaVersion: SCHEMA_VERSION, keep: [], freeBlocks: [], note: '' });
  }
  if (request.action === 'intent') {
    let content;
    try {
      content = await callIntentLlm(request, fetchImpl, env);
    } catch (err) {
      return fail(502, 'UPSTREAM_FAILED', String(err && err.message ? err.message : err));
    }
    try {
      const decision = guardIntentDecision(JSON.parse(extractJson(content)), request);
      return respond(200, decision);
    } catch (err) {
      return fail(422, 'DECISION_REJECTED', String(err && err.message ? err.message : err));
    }
  }
  const remaining = remainingOf(request);
  if (remaining.length === 0) {
    return respond(200, { schemaVersion: SCHEMA_VERSION, keep: [], freeBlocks: [], note: '' });
  }
  let content;
  try {
    content = await callLlm(request, remaining, fetchImpl, env);
  } catch (err) {
    return fail(502, 'UPSTREAM_FAILED', String(err && err.message ? err.message : err));
  }
  try {
    const decision = guardDecision(JSON.parse(extractJson(content)), request, remaining);
    return respond(200, decision);
  } catch (err) {
    return fail(422, 'DECISION_REJECTED', String(err && err.message ? err.message : err));
  }
}

module.exports = {
  handler: handler,
  _test: {
    normalizeRequest: normalizeRequest,
    remainingOf: remainingOf,
    guardDecision: guardDecision,
    guardIntentDecision: guardIntentDecision,
    intentPromptFor: intentPromptFor,
    promptFor: promptFor,
    parseBody: parseBody,
    headerOf: headerOf
  }
};
