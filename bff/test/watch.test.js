import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';

import { initDb } from '../src/db.js';
import watchRouter from '../src/routes/watch.js';
import { issueToken } from '../src/middleware/auth.js';

process.env.JWT_SECRET = 'watch-test-secret';
// 本套件只验 fail-closed 与暂存/幂等；正对照（真 idToken 验签）在 device-idtoken.test.js。
delete process.env.HUAWEI_CLIENT_ID;
delete process.env.PUSH_CLIENT_ID;
delete process.env.PUSH_CLIENT_SECRET;

const db = initDb(':memory:');
db.prepare('INSERT INTO account (union_id) VALUES (?)').run('union-a');
db.prepare('INSERT INTO account (union_id) VALUES (?)').run('union-b');
const accountA = db.prepare("SELECT id FROM account WHERE union_id = 'union-a'").get().id;
const accountB = db.prepare("SELECT id FROM account WHERE union_id = 'union-b'").get().id;

const app = express();
app.use(express.json({ limit: '2mb' }));
app.use((req, _res, next) => {
  req.db = db;
  next();
});
app.use('/watch', watchRouter);

let server;
let baseUrl;

await new Promise((resolve) => {
  server = app.listen(0, '127.0.0.1', resolve);
});
baseUrl = `http://127.0.0.1:${server.address().port}`;

after(() => {
  server.close();
  db.close();
});

function card(overrides = {}) {
  return {
    v: 1,
    type: 'card',
    cardId: 'probe-card-1',
    kind: 'companion',
    title: '你到了博览园——不在今天计划里',
    detail: '它会挤占下一站。怎么安排？',
    options: [
      { key: 'move_tomorrow', label: '挪明天', subline: '今天从容逛' },
      { key: 'keep_plan', label: '按原计划走', subline: '下次再去' }
    ],
    recommendedKey: 'move_tomorrow',
    ts: Date.now(),
    ...overrides
  };
}

function decision(overrides = {}) {
  return {
    v: 1,
    type: 'decision',
    cardId: 'probe-card-1',
    optionKey: 'move_tomorrow',
    ts: Date.now(),
    ...overrides
  };
}

async function call(method, path, token, body) {
  const headers = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const resp = await fetch(`${baseUrl}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const json = await resp.json().catch(() => null);
  return { status: resp.status, json };
}

const tokenA = issueToken(accountA, 'phone-a');
const tokenB = issueToken(accountB, 'phone-b');
const watchA = issueToken(accountA, 'watch-a');

// ---- 会话：fail-closed ----

test('手表 session 未配置 Client ID 时 fail-closed 401', async () => {
  const resp = await call('POST', '/watch/session', '', {
    watchDeviceId: 'watch-1', idToken: 'a.b.c'
  });
  assert.equal(resp.status, 401);
  assert.equal(resp.json.error, 'ID_TOKEN_INVALID');
});

test('手表 session 缺 watchDeviceId 400', async () => {
  const resp = await call('POST', '/watch/session', '', { idToken: 'a.b.c' });
  assert.equal(resp.status, 400);
});

// ---- 鉴权 ----

test('watch 路由缺票据 401', async () => {
  const resp = await call('POST', '/watch/decision', '', { decision: decision() });
  assert.equal(resp.status, 401);
});

test('whoami 返回票据对应账号', async () => {
  const resp = await call('GET', '/watch/whoami', watchA);
  assert.equal(resp.status, 200);
  assert.equal(resp.json.accountId, accountA);
  assert.equal(resp.json.deviceId, 'watch-a');
  assert.equal(resp.json.pushConfigured, false);
});

// ---- 决策：暂存 / 幂等 / 拉取 / ack ----

test('手表决策落库 + 幂等 + 手机拉取 + ack', async () => {
  const first = await call('POST', '/watch/decision', watchA, { decision: decision() });
  assert.equal(first.status, 200);
  assert.equal(first.json.duplicate, false);
  assert.ok(first.json.decisionId > 0);

  const again = await call('POST', '/watch/decision', watchA, { decision: decision() });
  assert.equal(again.status, 200);
  assert.equal(again.json.duplicate, true);
  assert.equal(again.json.decisionId, first.json.decisionId);

  const list = await call('GET', '/watch/decisions', tokenA);
  assert.equal(list.status, 200);
  assert.equal(list.json.decisions.length, 1);
  assert.equal(list.json.decisions[0].decision.optionKey, 'move_tomorrow');
  assert.equal(list.json.decisions[0].decision.cardId, 'probe-card-1');

  const since = await call('GET', `/watch/decisions?since=${first.json.decisionId}`, tokenA);
  assert.equal(since.json.decisions.length, 0);

  const ack = await call('POST', '/watch/decision/ack', tokenA, { ids: [first.json.decisionId] });
  assert.equal(ack.status, 200);
  assert.equal(ack.json.acked, 1);

  const afterAck = await call('GET', '/watch/decisions', tokenA);
  assert.equal(afterAck.json.decisions.length, 0);
});

test('决策按账号隔离：B 看不到 A 的决策', async () => {
  await call('POST', '/watch/decision', watchA, {
    decision: decision({ cardId: 'probe-card-iso', optionKey: 'keep_plan' })
  });
  const listB = await call('GET', '/watch/decisions', tokenB);
  assert.equal(listB.status, 200);
  assert.equal(listB.json.decisions.length, 0);
});

test('畸形决策 400', async () => {
  const resp = await call('POST', '/watch/decision', watchA, {
    decision: decision({ optionKey: '' })
  });
  assert.equal(resp.status, 400);
});

// ---- 卡片：暂存 / 当前卡 / 撤卡 / 账号冲突 ----

test('卡片暂存 → 手表拉当前卡 → 撤卡后 404（推送未配置不假装成功）', async () => {
  // 先注册一个 push token：证明「有 token 但未配置 Push」时仍是 fail-closed，而不是没 token 的假象
  const reg = await call('POST', '/watch/push-token', watchA, { pushToken: 'push-token-abc' });
  assert.equal(reg.status, 200);

  const created = await call('POST', '/watch/card', tokenA, { card: card() });
  assert.equal(created.status, 200);
  assert.equal(created.json.ok, true);
  assert.equal(created.json.pushed, 0);
  assert.equal(created.json.push, 'NOT_CONFIGURED');

  const current = await call('GET', '/watch/card/current', watchA);
  assert.equal(current.status, 200);
  assert.equal(current.json.card.cardId, 'probe-card-1');
  assert.equal(current.json.card.recommendedKey, 'move_tomorrow');

  const withdrawn = await call('POST', '/watch/card/withdraw', tokenA, { cardId: 'probe-card-1' });
  assert.equal(withdrawn.status, 200);
  assert.equal(withdrawn.json.withdrawn, 1);

  const afterWithdraw = await call('GET', '/watch/card/current', watchA);
  assert.equal(afterWithdraw.status, 404);
});

test('cardId 被其他账号占用 → 409', async () => {
  const resp = await call('POST', '/watch/card', tokenB, {
    card: card({ cardId: 'probe-card-1' })
  });
  assert.equal(resp.status, 409);
  assert.equal(resp.json.error, 'CARD_ID_CONFLICT');
});

test('畸形卡片 400', async () => {
  const resp = await call('POST', '/watch/card', tokenA, {
    card: card({ options: [] })
  });
  assert.equal(resp.status, 400);
});

test('push-token 注册成功（未配置推送也允许先存 token）', async () => {
  const resp = await call('POST', '/watch/push-token', watchA, { pushToken: 'push-token-abc' });
  assert.equal(resp.status, 200);
  const row = db.prepare(
    "SELECT push_token FROM watch_device WHERE account_id = ? AND watch_device_id = 'watch-a'"
  ).get(accountA);
  assert.equal(row.push_token, 'push-token-abc');
});
