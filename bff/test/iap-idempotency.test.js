/**
 * 同一张收据重复提交必须幂等（§5ci 续 85 的 D8）。
 *
 * 改前：`subscription.purchase_token` 有 UNIQUE 约束，第二次提交直接把约束异常抛成 500，
 * 客户端网络抖动后的重试会看到"服务端错误"，而实际是它自己已经买成功了。
 * 收据是唯一凭据，重放的正确语义是「返回当前权益」，不是再记一单、也不是报错。
 */
import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import express from 'express';

import { initDb } from '../src/db.js';
import iapRouter from '../src/routes/iap.js';
import { issueToken } from '../src/middleware/auth.js';

process.env.JWT_SECRET = 'iap-test-secret';

// 收据校验现在 fail-closed：测试要显式配一个"全都验过"的校验桩，
// 否则 /v1/iap/verify 会 503，这些幂等用例根本走不到入库。
const verifier = http.createServer((req, res) => {
  req.resume();
  req.on('end', () => {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ verified: true }));
  });
});
await new Promise((resolve) => verifier.listen(0, '127.0.0.1', resolve));
process.env.IAP_VERIFY_URL = `http://127.0.0.1:${verifier.address().port}/verify`;
process.env.IAP_APP_ID = 'iap-test-app';
process.env.IAP_VERIFY_TOKEN = 'iap-test-token';

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
  verifier.close();
});

const accountId = Number(
  db.prepare('INSERT INTO account (union_id, device_id) VALUES (?, ?)').run('u-iap', 'dev-iap').lastInsertRowid
);
const token = issueToken(accountId, 'dev-iap');
const accountId2 = Number(
  db.prepare('INSERT INTO account (union_id, device_id) VALUES (?, ?)').run('u-iap-2', 'dev-iap-2').lastInsertRowid
);
const token2 = issueToken(accountId2, 'dev-iap-2');

async function verify(body, bearer) {
  const resp = await fetch(`${base}/v1/iap/verify`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${bearer || token}`
    },
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

test('通行证购买时绑上订单号：退款回调只拿收据号也能追回这张通行证', async () => {
  const receipt = 'receipt-pass-link';
  const resp = await verify({ purchaseToken: receipt, productType: 'pass', localTripId: 'trip-link' });
  assert.equal(resp.status, 200);

  const orderId = db.prepare('SELECT id FROM `order` WHERE purchase_token = ?').get(receipt).id;
  const pass = db.prepare(
    "SELECT order_id FROM trip_pass WHERE local_trip_id = 'trip-link'"
  ).get();
  assert.equal(pass.order_id, orderId, '没有这层绑定，REFUND 通知就只能记一笔孤儿日志、撤不掉通行证');
});

test('同一通行证收据换账号：第二个人被拒，且不落 pass', async () => {
  // 旧实现先插 trip_pass 再查 order：订单不重复，但第二个人照样白拿一张 active 通行证。
  const receipt = 'receipt-shared-pass';
  const first = await verify({ purchaseToken: receipt, productType: 'pass', localTripId: 'trip-shared' });
  const second = await verify(
    { purchaseToken: receipt, productType: 'pass', localTripId: 'trip-shared' }, token2);

  assert.equal(first.status, 200);
  assert.equal(second.status, 409);
  assert.equal(second.body.error, 'RECEIPT_ALREADY_USED');

  const passes = db.prepare('SELECT COUNT(*) AS c FROM trip_pass WHERE account_id = ?').get(accountId2);
  assert.equal(passes.c, 0, '收据不能给别人换来通行证');
});

test('同一订阅收据换账号：同样拒绝，不落订阅', async () => {
  const receipt = 'receipt-shared-sub';
  const first = await verify({ purchaseToken: receipt, productType: 'subscription' });
  const second = await verify({ purchaseToken: receipt, productType: 'subscription' }, token2);

  assert.equal(first.status, 200);
  assert.equal(second.status, 409);
  const subs = db.prepare('SELECT COUNT(*) AS c FROM subscription WHERE account_id = ?').get(accountId2);
  assert.equal(subs.c, 0);
});
