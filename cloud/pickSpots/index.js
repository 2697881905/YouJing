'use strict';

/**
 * P1 AI 精选云函数（AGC 零依赖版，无自购服务器）。
 * 只做：鉴权 → 校验候选 → 调 LLM → 守卫排序/理由。
 * 提示词不在这里手写：prompt/ 目录是 bff/scripts/sync-prompt-contract.mjs
 * 从 entry/ SOT 同步过来的生成物，云端只 require。
 */

const { PromptBuilder } = require('./prompt/ai/PromptBuilder.js');

const MAX_CANDIDATES = 40;
const MAX_REASON = 80;
const MAX_NOTE = 200;
const MAX_BODY_BYTES = 64 * 1024;
const UPSTREAM_TIMEOUT_MS = 5000;

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

function validatePickRequest(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    return 'body 必须是对象';
  }
  if (typeof body.city !== 'string' || body.city.trim().length === 0) {
    return 'city 必须是非空字符串';
  }
  if (!Number.isInteger(body.days) || body.days < 1 || body.days > 30) {
    return 'days 必须是 1–30 的整数';
  }
  if (typeof body.pace !== 'string' || typeof body.interests !== 'string') {
    return 'pace/interests 必须是字符串';
  }
  if (!Array.isArray(body.candidates) || body.candidates.length === 0) {
    return 'candidates 不能为空';
  }
  if (body.candidates.length > MAX_CANDIDATES) {
    return `candidates 最多 ${MAX_CANDIDATES} 个`;
  }
  const ids = new Set();
  for (const c of body.candidates) {
    if (!c || typeof c !== 'object') {
      return 'candidate 必须是对象';
    }
    if (typeof c.id !== 'string' || c.id.length === 0) {
      return 'candidate.id 非法';
    }
    if (ids.has(c.id)) {
      return 'candidate.id 重复';
    }
    if (typeof c.name !== 'string' || c.name.length === 0) {
      return 'candidate.name 非法';
    }
    if (typeof c.tag !== 'string' || typeof c.brief !== 'string' ||
        typeof c.district !== 'string') {
      return 'candidate 文本字段非法';
    }
    if (!Number.isFinite(c.popularity) || !Number.isFinite(c.suggestedDuration)) {
      return 'candidate 数值字段非法';
    }
    if (typeof c.requiresBooking !== 'boolean') {
      return 'candidate.requiresBooking 非法';
    }
    ids.add(c.id);
  }
  return '';
}

function candidateIdsOf(body) {
  return body.candidates.map((c) => c.id);
}

function guardPick(raw, candidateIds) {
  if (!raw || typeof raw !== 'object') {
    throw new Error('decision 不是对象');
  }
  if (!Array.isArray(raw.ranked)) {
    throw new Error('ranked 缺失');
  }
  if (raw.ranked.length !== candidateIds.length) {
    throw new Error('ranked 必须覆盖全部候选');
  }
  const allowed = new Set(candidateIds);
  const seen = new Set();
  const ranked = [];
  for (const item of raw.ranked) {
    if (!item || typeof item.id !== 'string' || !allowed.has(item.id)) {
      throw new Error('ranked.id 不在候选内');
    }
    if (seen.has(item.id)) {
      throw new Error('ranked.id 重复');
    }
    const reason = typeof item.reason === 'string' ? item.reason.trim() : '';
    if (reason.length > MAX_REASON) {
      throw new Error('reason 超长');
    }
    seen.add(item.id);
    ranked.push({ id: item.id, reason: reason });
  }
  const note = typeof raw.note === 'string' ? raw.note.trim() : '';
  if (note.length > MAX_NOTE) {
    throw new Error('note 超长');
  }
  return { ranked: ranked, note: note };
}

async function callLlm(body, fetchImpl, env) {
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
        messages: [
          { role: 'system', content: PromptBuilder.pickSystemPrompt() },
          { role: 'user', content: PromptBuilder.pickUserPrompt(body) }
        ]
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

function extractJson(text) {
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start < 0 || end <= start) {
    throw new Error('response has no JSON body');
  }
  return text.slice(start, end + 1);
}

async function handler(event, context, deps) {
  const env = (deps && deps.env) || process.env;
  const fetchImpl = (deps && deps.fetch) || globalThis.fetch;
  const expected = env.YOUJING_PICK_TOKEN || env.YOUJING_REPLAN_TOKEN;
  if (!expected) {
    return fail(500, 'SERVER_MISCONFIGURED', 'YOUJING_PICK_TOKEN 未配置');
  }
  if (headerOf(event, 'x-youjing-token') !== expected) {
    return fail(401, 'UNAUTHORIZED', 'token 不匹配');
  }
  const body = parseBody(event);
  if (!body) {
    return fail(400, 'BAD_REQUEST', '请求体不是合法 JSON');
  }
  const invalid = validatePickRequest(body);
  if (invalid !== '') {
    return fail(422, 'INVALID_REQUEST', invalid);
  }
  let content;
  try {
    content = await callLlm(body, fetchImpl, env);
  } catch (err) {
    return fail(502, 'UPSTREAM_FAILED', String(err && err.message ? err.message : err));
  }
  try {
    const decision = guardPick(JSON.parse(extractJson(content)), candidateIdsOf(body));
    return respond(200, decision);
  } catch (err) {
    return fail(422, 'DECISION_REJECTED', String(err && err.message ? err.message : err));
  }
}

module.exports = {
  handler: handler,
  _test: {
    validatePickRequest: validatePickRequest,
    candidateIdsOf: candidateIdsOf,
    guardPick: guardPick,
    parseBody: parseBody,
    headerOf: headerOf
  }
};
