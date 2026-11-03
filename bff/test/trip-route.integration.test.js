import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import express from 'express';

import { initDb } from '../src/db.js';
import tripRouter from '../src/routes/trip.js';
import { authMiddleware, issueToken } from '../src/middleware/auth.js';
import { validTrip, richRequest } from './fixtures/trip.js';

process.env.JWT_SECRET = 'route-test-secret';
process.env.DEEPSEEK_API_KEY = 'route-test-key';
process.env.LLM_MODEL = 'route-test-model';
process.env.LLM_RESPONSE_FORMAT = 'json_object';

const calls = [];
let upstreamDelayMs = 0;
const upstream = http.createServer((req, res) => {
  let body = '';
  req.on('data', (chunk) => {
    body += chunk;
  });
  req.on('end', () => {
    calls.push({ url: req.url, body: JSON.parse(body) });
    setTimeout(() => {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        choices: [{ message: { content: JSON.stringify(validTrip()) } }],
        usage: { prompt_tokens: 11, completion_tokens: 22 },
        model: 'route-test-model'
      }));
    }, upstreamDelayMs);
  });
});

const db = initDb(':memory:');
const app = express();
app.use(express.json({ limit: '2mb' }));
app.use((req, _res, next) => {
  req.db = db;
  next();
});
app.use('/v1/trip', authMiddleware, tripRouter);
app.use((err, _req, res, _next) => {
  res.status(err.status || 500).json({
    error: err.code || 'INTERNAL_ERROR',
    message: err.message
  });
});

let appServer;
let baseUrl;
let upstreamUrl;

await new Promise((resolve) => upstream.listen(0, '127.0.0.1', resolve));
upstreamUrl = `http://127.0.0.1:${upstream.address().port}/v1`;
process.env.LLM_BASE_URL = upstreamUrl;
await new Promise((resolve) => {
  appServer = app.listen(0, '127.0.0.1', resolve);
});
baseUrl = `http://127.0.0.1:${appServer.address().port}`;

after(() => {
  appServer.close();
  upstream.close();
  db.close();
});

function payloadFor(days = 1) {
  const payload = richRequest();
  payload.startDate = '2026-11-06';
  payload.endDate = days === 1 ? '2026-11-06' : '2026-11-08';
  payload.selectedSpots = payload.spots.map((spot) => ({ spotId: spot.id, priority: 'must' }));
  return payload;
}

async function post(accountId, key, body) {
  const token = issueToken(accountId, `device-${accountId}`);
  const started = Date.now();
  const resp = await fetch(`${baseUrl}/v1/trip/generate`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
      'Idempotency-Key': key
    },
    body: JSON.stringify(body)
  });
  const text = await resp.text();
  return { status: resp.status, text, body: JSON.parse(text), ms: Date.now() - started };
}

test('路由真实 UPSERT：首次 200，配额按提交后快照返回', async () => {
  calls.length = 0;
  upstreamDelayMs = 0;
  const first = await post(1, 'route-key-1', payloadFor());
  assert.equal(first.status, 200);
  assert.equal(first.body.quota.giftRemaining, 2, '首次成功后 giftRemaining 应为 2');
  assert.equal(first.body.quota.remainingToday, 1, '首次成功后 usedToday 应为 1');
  assert.equal(calls.length, 1);
  assert.equal(calls[0].body.response_format.type, 'json_object');
  assert.ok(Array.isArray(calls[0].body.messages));
  assert.ok(calls[0].body.messages[1].content.includes('已选景点（含完整规划信息）'));
  // gift 是免费档：8192 token + 精简后缀
  assert.equal(calls[0].body.max_tokens, 8192);
  assert.ok(calls[0].body.messages[0].content.includes('输出尽量精简'));
});

test('幂等重放：同键同体第二次不调上游、字节相同', async () => {
  const first = await post(1, 'route-key-1', payloadFor());
  calls.length = 0;
  const second = await post(1, 'route-key-1', payloadFor());
  assert.equal(second.status, 200);
  assert.equal(calls.length, 0, '重放不应再调上游');
  assert.equal(second.text, first.text);
  assert.equal(second.body.quota.giftRemaining, 2);
});

test('同键不同体：422，且不调上游', async () => {
  calls.length = 0;
  const first = await post(2, 'route-key-2', payloadFor());
  assert.equal(first.status, 200);
  calls.length = 0;
  const conflict = await post(2, 'route-key-2', { ...payloadFor(), people: 3 });
  assert.equal(conflict.status, 422);
  assert.equal(conflict.body.error, 'IDEMPOTENCY_KEY_REUSED');
  assert.equal(calls.length, 0);
});

test('并发同键：一个 200、一个 409，上游只调一次', async () => {
  calls.length = 0;
  upstreamDelayMs = 150;
  const [a, b] = await Promise.all([
    post(3, 'route-key-3', payloadFor()),
    post(3, 'route-key-3', payloadFor())
  ]);
  const statuses = [a.status, b.status].sort((x, y) => x - y);
  assert.deepEqual(statuses, [200, 409]);
  assert.equal(calls.length, 1, '只能有一个请求真正调上游');
  const winner = a.status === 200 ? a : b;
  assert.equal(winner.body.quota.giftRemaining, 2);
});

test('上游 4xx 映射 502 LLM_UPSTREAM_ERROR：不落 succeeded、不扣 gift', async () => {
  const failingUpstream = http.createServer((_req, res) => {
    res.writeHead(400, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: { message: 'upstream rejected response_format' } }));
  });
  await new Promise((resolve) => failingUpstream.listen(0, '127.0.0.1', resolve));
  const oldBase = process.env.LLM_BASE_URL;
  process.env.LLM_BASE_URL = `http://127.0.0.1:${failingUpstream.address().port}/v1`;
  try {
    const bad = await post(5, 'route-key-5', payloadFor());
    assert.equal(bad.status, 502);
    assert.equal(bad.body.error, 'LLM_UPSTREAM_ERROR');
    assert.ok(bad.body.message.includes('LLM upstream 400'));

    const gift = db.prepare(
      `SELECT COALESCE(SUM(delta),0) AS total FROM quota_ledger
       WHERE account_id = 5 AND source = 'gift' AND state = 'committed'`
    ).get();
    assert.equal(gift.total, 0, '上游 4xx 不应扣 gift');
    const row = db.prepare(
      'SELECT status, error_code FROM trip_request WHERE account_id = 5'
    ).get();
    assert.equal(row.status, 'failed');
    assert.equal(row.error_code, 502);
  } finally {
    process.env.LLM_BASE_URL = oldBase;
    failingUpstream.close();
  }
});

test('BFF 校验失败 502：不落 succeeded、不扣 gift', async () => {
  calls.length = 0;
  upstreamDelayMs = 0;
  // 用一个缺 days 的假上游响应，走真实路由的 502 分支
  const originalBody = validTrip();
  delete originalBody.days;
  const failingUpstream = http.createServer((_req, res) => {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      choices: [{ message: { content: JSON.stringify(originalBody) } }],
      usage: { prompt_tokens: 5, completion_tokens: 6 }
    }));
  });
  await new Promise((resolve) => failingUpstream.listen(0, '127.0.0.1', resolve));
  const oldBase = process.env.LLM_BASE_URL;
  process.env.LLM_BASE_URL = `http://127.0.0.1:${failingUpstream.address().port}/v1`;
  try {
    const bad = await post(4, 'route-key-4', payloadFor());
    assert.equal(bad.status, 502);
    assert.equal(bad.body.error, 'LLM_INVALID_TRIP');
    const gift = db.prepare(
      `SELECT COALESCE(SUM(delta),0) AS total FROM quota_ledger
       WHERE account_id = 4 AND source = 'gift' AND state = 'committed'`
    ).get();
    assert.equal(gift.total, 0, '502 不应扣 gift');
  } finally {
    process.env.LLM_BASE_URL = oldBase;
    failingUpstream.close();
  }
});

test('quota 回传 subscription 快照：到期后为 null、额度退回赠送档（D9）', async () => {
  const accountId = 9;
  db.prepare(
    `INSERT INTO subscription (account_id, product_id, status, period_start, period_end, auto_renew, purchase_token)
     VALUES (?, 'youjing_sub_monthly', 'active', datetime('now'), datetime('now', '+1 months'), 1, 'route-sub-1')`
  ).run(accountId);

  const first = await post(accountId, 'route-key-sub-1', payloadFor());
  assert.equal(first.status, 200);
  assert.equal(first.body.quota.source, 'subscription');
  assert.equal(first.body.quota.subscription.status, 'active', '未到期的订阅要回传快照');
  assert.equal(first.body.quota.dailyCap, 20);
  // 订阅是付费档：16384 token、不带精简后缀（端侧此前只按"有没有订阅"算，这里钉服务端口径）
  assert.equal(calls[calls.length - 1].body.max_tokens, 16384);
  assert.ok(!calls[calls.length - 1].body.messages[0].content.includes('输出尽量精简'));

  // 到期（或退款通知已落库）之后：服务端必须回 null，端上据此清掉本地订阅
  db.prepare(
    "UPDATE subscription SET period_end = datetime('now','-1 days') WHERE purchase_token = 'route-sub-1'"
  ).run();
  const second = await post(accountId, 'route-key-sub-2', payloadFor());
  assert.equal(second.status, 200);
  assert.equal(second.body.quota.subscription, null, '过期订阅不能继续回传 active');
  assert.equal(second.body.quota.source, 'gift', '过期后应退回赠送档');
  assert.equal(second.body.quota.giftRemaining, 2);
});

test('上游 429 映射 429 LLM_RATE_LIMITED：端上 6003 文案不再不可达，且不扣额度', async () => {
  const busyUpstream = http.createServer((_req, res) => {
    res.writeHead(429, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: { message: 'rate limited' } }));
  });
  await new Promise((resolve) => busyUpstream.listen(0, '127.0.0.1', resolve));
  const oldBase = process.env.LLM_BASE_URL;
  process.env.LLM_BASE_URL = `http://127.0.0.1:${busyUpstream.address().port}/v1`;
  try {
    const r = await post(11, 'route-key-429', payloadFor());
    assert.equal(r.status, 429, '上游限流必须透传 429，不能包成 502');
    assert.equal(r.body.error, 'LLM_RATE_LIMITED');
    const gift = db.prepare(
      `SELECT COALESCE(SUM(delta),0) AS total FROM quota_ledger
       WHERE account_id = 11 AND source = 'gift' AND state = 'committed'`
    ).get();
    assert.equal(gift.total, 0, '限流失败不该扣 gift');
  } finally {
    process.env.LLM_BASE_URL = oldBase;
    busyUpstream.close();
  }
});

test('通行证买家按付费档出提示词（8192→16384、不再追加精简后缀）', async () => {
  // 端侧的旧判据是「没有订阅 ⇒ freeTier=true」，通行证买家（付费、无订阅）会被算成免费档。
  // 服务端改为按实际扣费来源判定：gift=免费档，pass/subscription=付费档。
  const accountId = 12;
  db.prepare(
    "INSERT INTO trip_pass (account_id, local_trip_id, status) VALUES (?, 'trip-pass-ai', 'active')"
  ).run(accountId);
  calls.length = 0;
  const r = await post(accountId, 'route-key-pass-ai', Object.assign(payloadFor(), { passId: 'trip-pass-ai' }));
  assert.equal(r.status, 200);
  assert.equal(r.body.quota.source, 'pass');
  assert.equal(calls.length, 1);
  assert.equal(calls[0].body.max_tokens, 16384, '通行证是付费档，不能吃 8192 的免费上限');
  assert.ok(!calls[0].body.messages[0].content.includes('输出尽量精简'),
    '付费档不该带免费档的精简后缀');
});

test('模型在 JSON 后附带说明文字：提取第一个对象后照常 200，不触发重试', async () => {
  // 2026-11-03 真实输出：JSON.parse 报 Unexpected non-whitespace character after JSON。
  // 改前会 502 → 端侧整次重试；改后取第一个完整对象并继续走 validateTrip。
  let chattyCalls = 0;
  const chattyUpstream = http.createServer((_req, res) => {
    chattyCalls += 1;
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      choices: [{ message: { content: JSON.stringify(validTrip()) + '\n以上是本次行程，祝旅途愉快。' } }],
      usage: { prompt_tokens: 13, completion_tokens: 17 }
    }));
  });
  await new Promise((resolve) => chattyUpstream.listen(0, '127.0.0.1', resolve));
  const oldBase = process.env.LLM_BASE_URL;
  process.env.LLM_BASE_URL = `http://127.0.0.1:${chattyUpstream.address().port}/v1`;
  try {
    const r = await post(13, 'route-key-chatty', payloadFor());
    assert.equal(r.status, 200);
    assert.equal(chattyCalls, 1, '兜底成功就不该再打一次上游');
    assert.equal(r.body.quota.giftRemaining, 2);
  } finally {
    process.env.LLM_BASE_URL = oldBase;
    chattyUpstream.close();
  }
});

test('核心参数非法：400，不扣额度、不打上游', async () => {
  calls.length = 0;
  const cases = [
    { ...payloadFor(), destination: '' },
    { ...payloadFor(), startDate: '2026/11/06' },
    { ...payloadFor(), endDate: '2026-11-05' },
    { ...payloadFor(), people: 0 },
    { ...payloadFor(), budget: -1 },
    { ...payloadFor(), startDate: '1999-01-01' },
    { ...payloadFor(), endDate: '2101-01-01' },
    { ...payloadFor(), startDate: '2026-11-06', endDate: '2026-12-30' }
  ];
  for (const body of cases) {
    const r = await post(14, 'route-key-bad-' + Math.random().toString(36).slice(2), body);
    assert.equal(r.status, 400, JSON.stringify({ startDate: body.startDate, people: body.people }));
    assert.equal(r.body.error, 'INVALID_REQUEST');
  }
  assert.equal(calls.length, 0, '坏请求不能打上游');
  const gift = db.prepare(
    `SELECT COALESCE(SUM(delta),0) AS total FROM quota_ledger
     WHERE account_id = 14 AND source = 'gift' AND state = 'committed'`
  ).get();
  assert.equal(gift.total, 0, '坏请求不能扣额度');
});

test('模型首次输出坏 JSON：带修正指令重问一次，成功则照常 200、只扣一次额度', async () => {
  const bodies = [];
  let call = 0;
  const flaky = http.createServer((req, res) => {
    let raw = '';
    req.on('data', (c) => { raw += c; });
    req.on('end', () => {
      call += 1;
      bodies.push(raw);
      const content = call === 1 ? '{"days": [' : JSON.stringify(validTrip());
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        choices: [{ message: { content }, finish_reason: call === 1 ? 'length' : 'stop' }],
        usage: { prompt_tokens: 10, completion_tokens: 20 }
      }));
    });
  });
  await new Promise((resolve) => flaky.listen(0, '127.0.0.1', resolve));
  const oldBase = process.env.LLM_BASE_URL;
  process.env.LLM_BASE_URL = `http://127.0.0.1:${flaky.address().port}/v1`;
  try {
    const r = await post(15, 'route-key-repair', payloadFor());
    assert.equal(r.status, 200);
    assert.equal(call, 2, '坏 JSON 应触发一次修正调用');
    assert.equal(r.body.quota.giftRemaining, 2, '两次模型调用只扣一次额度');
    assert.ok(bodies[1].includes('修正后的完整 JSON'), '第二次请求必须带修正指令');
    // 免费档首次 8192；修正调用抬到 16384，避免被 length 截断后再次产生坏 JSON
    assert.equal(JSON.parse(bodies[0]).max_tokens, 8192);
    assert.equal(JSON.parse(bodies[1]).max_tokens, 16384);
  } finally {
    process.env.LLM_BASE_URL = oldBase;
    flaky.close();
  }
});

test('修正调用仍是坏 JSON：502，且不扣额度', async () => {
  let call = 0;
  const alwaysBad = http.createServer((req, res) => {
    req.resume();
    req.on('end', () => {
      call += 1;
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        choices: [{ message: { content: '{"days": [' } }],
        usage: { prompt_tokens: 10, completion_tokens: 20 }
      }));
    });
  });
  await new Promise((resolve) => alwaysBad.listen(0, '127.0.0.1', resolve));
  const oldBase = process.env.LLM_BASE_URL;
  process.env.LLM_BASE_URL = `http://127.0.0.1:${alwaysBad.address().port}/v1`;
  try {
    const r = await post(16, 'route-key-repair-bad', payloadFor());
    assert.equal(r.status, 502);
    assert.equal(r.body.error, 'LLM_INVALID_JSON');
    assert.equal(call, 2);
    const gift = db.prepare(
      `SELECT COALESCE(SUM(delta),0) AS total FROM quota_ledger
       WHERE account_id = 16 AND source = 'gift' AND state = 'committed'`
    ).get();
    assert.equal(gift.total, 0);
  } finally {
    process.env.LLM_BASE_URL = oldBase;
    alwaysBad.close();
  }
});

test('上游一直不回：按超时失败（504）、不扣额度、幂等行标记 failed', async () => {
  const hung = http.createServer((req, res) => {
    req.resume();
    // 故意不响应：模拟上游挂起
    void res;
  });
  await new Promise((resolve) => hung.listen(0, '127.0.0.1', resolve));
  const oldBase = process.env.LLM_BASE_URL;
  const oldTimeout = process.env.LLM_TIMEOUT_MS;
  process.env.LLM_BASE_URL = `http://127.0.0.1:${hung.address().port}/v1`;
  process.env.LLM_TIMEOUT_MS = '200';
  try {
    const r = await post(17, 'route-key-timeout', payloadFor());
    assert.equal(r.status, 504);
    assert.equal(r.body.error, 'LLM_TIMEOUT');
    const gift = db.prepare(
      `SELECT COALESCE(SUM(delta),0) AS total FROM quota_ledger
       WHERE account_id = 17 AND source = 'gift' AND state = 'committed'`
    ).get();
    assert.equal(gift.total, 0, '超时失败不该扣额度');
    const row = db.prepare(
      "SELECT status FROM trip_request WHERE account_id = 17 AND idempotency_key LIKE '%' ORDER BY id DESC LIMIT 1"
    ).get();
    assert.equal(row.status, 'failed');
  } finally {
    process.env.LLM_BASE_URL = oldBase;
    if (oldTimeout === undefined) delete process.env.LLM_TIMEOUT_MS;
    else process.env.LLM_TIMEOUT_MS = oldTimeout;
    hung.close();
  }
});
