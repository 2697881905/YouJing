/**
 * 同一张收据重复提交必须幂等（§5ci 续 85 的 D8）。
 *
 * 改前：`subscription.purchase_token` 有 UNIQUE 约束，第二次提交直接把约束异常抛成 500，
 * 客户端网络抖动后的重试会看到"服务端错误"，而实际是它自己已经买成功了。
 * 收据是唯一凭据，重放的正确语义是「返回当前权益」，不是再记一单、也不是报错。
 */
import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';

import { initDb } from '../src/db.js';
import iapRouter from '../src/routes/iap.js';
import { issueToken } from '../src/middleware/auth.js';

process.env.JWT_SECRET = 'iap-test-secret';

const db = initDb(':memory:');
const app = express();
app.use(express.json({ limit: '2mb' }));
app.use((req, _res, next) => {
  req.db = db;
  next();
});
app.use('/v1/iap', iapRouter);
app.use((err, _req, res, _next) => {
  res.status(err.status || 500).json({ error: err.code || 'INTERNAL_ERROR', message: err.message });
});

let server;
let base;
await new Promise((resolve) => {
  server = app.listen(0, '127.0.0.1', resolve);
});
base = `http://127.0.0.1:${server.address().port}`;
after(() => {
  server.close();
  db.close();
});

const accountId = Number(
  db.prepare('INSERT INTO account (union_id, device_id) VALUES (?, ?)').run('u-iap', 'dev-iap').lastInsertRowid
);
const token = issueToken(accountId, 'dev-iap');

async function verify(body) {
  const resp = await fetch(`${base}/v1/iap/verify`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify(body)
  });
  return { status: resp.status, body: await resp.json() };
}

test('同一订阅收据重复提交：两次都 200，且只落一行订阅与一单', async () => {
  const receipt = 'receipt-sub-1';
  const first = await verify({ purchaseToken: receipt, productType: 'subscription', productId: 'youjing_sub_monthly' });
  const second = await verify({ purchaseToken: receipt, productType: 'subscription', productId: 'youjing_sub_monthly' });

  assert.equal(first.status, 200);
  assert.equal(second.status, 200, '重放不该报 500');
  assert.equal(second.body.verified, true);
  assert.equal(second.body.entitlement.subscription.status, 'active');

  const subs = db.prepare('SELECT COUNT(*) AS c FROM subscription WHERE purchase_token = ?').get(receipt);
  assert.equal(subs.c, 1, '订阅行不该重复');
  const orders = db.prepare('SELECT COUNT(*) AS c FROM `order` WHERE purchase_token = ?').get(receipt);
  assert.equal(orders.c, 1, '订单不该重复记账');
});

test('同一通行证收据重复提交：两次都 200，且只记一单', async () => {
  const receipt = 'receipt-pass-1';
  const first = await verify({ purchaseToken: receipt, productType: 'pass', localTripId: 'trip-x' });
  const second = await verify({ purchaseToken: receipt, productType: 'pass', localTripId: 'trip-x' });

  assert.equal(first.status, 200);
  assert.equal(second.status, 200, '重放不该报 500');
  assert.equal(second.body.passId, 'trip-x');

  const orders = db.prepare('SELECT COUNT(*) AS c FROM `order` WHERE purchase_token = ?').get(receipt);
  assert.equal(orders.c, 1, '订单不该重复记账');
});
