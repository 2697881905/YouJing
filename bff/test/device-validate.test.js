/**
 * 设备激活的边界校验（账号表入口）。
 *
 * 改前只判 `if (!deviceId)`：数字/对象/超长字符串会一路进 better-sqlite3 抛成 500，
 * 或者把 account 表撑脏。这里钉住 400 的三种形态与「合法请求仍能激活」的正对照。
 */
import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';

import { initDb } from '../src/db.js';
import deviceRouter from '../src/routes/device.js';

process.env.JWT_SECRET = 'device-validate-secret';

const db = initDb(':memory:');
const app = express();
app.use(express.json({ limit: '1mb' }));
app.use((req, _res, next) => { req.db = db; next(); });
app.use('/v1/device', deviceRouter);
app.use((err, _req, res, _next) => {
  res.status(err.status || 500).json({ error: err.code || 'INTERNAL_ERROR' });
});
let server;
await new Promise((resolve) => { server = app.listen(0, '127.0.0.1', resolve); });
const base = `http://127.0.0.1:${server.address().port}`;
after(() => { server.close(); db.close(); });

async function activate(body) {
  const resp = await fetch(`${base}/v1/device/activate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });
  return { status: resp.status, body: await resp.json() };
}

test('合法 deviceId 仍能激活并拿到票据（正对照）', async () => {
  const r = await activate({ deviceId: 'dev-ok-1' });
  assert.equal(r.status, 200);
  assert.ok(typeof r.body.deviceToken === 'string' && r.body.deviceToken.length > 0);
});

test('缺 deviceId / 非字符串 / 空串 / 超长：一律 400，不建账号', async () => {
  const before = db.prepare('SELECT COUNT(*) AS c FROM account').get().c;
  for (const body of [
    {},
    { deviceId: 123 },
    { deviceId: '   ' },
    { deviceId: 'x'.repeat(129) }
  ]) {
    const r = await activate(body);
    assert.equal(r.status, 400, JSON.stringify(body));
    assert.equal(r.body.error, 'MISSING_DEVICE_ID');
  }
  const afterCount = db.prepare('SELECT COUNT(*) AS c FROM account').get().c;
  assert.equal(afterCount, before, '被拒绝的请求不能建账号');
});

test('unionId 非字符串或超长：400；空串/缺省按游客处理', async () => {
  const bad = await activate({ deviceId: 'dev-bad-union', unionId: { evil: true } });
  assert.equal(bad.status, 400);
  assert.equal(bad.body.error, 'INVALID_UNION_ID');

  const tooLong = await activate({ deviceId: 'dev-long-union', unionId: 'u'.repeat(129) });
  assert.equal(tooLong.status, 400);

  const guest = await activate({ deviceId: 'dev-guest-again', unionId: '' });
  assert.equal(guest.status, 200);
});
