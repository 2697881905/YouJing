/**
 * 同一张收据重复提交必须幂等（§5ci 续 85 的 D8）—— JWS 版。
 *
 * 改前：`subscription.purchase_token` 有 UNIQUE 约束，第二次提交直接把约束异常抛成 500，
 * 客户端网络抖动后的重试会看到"服务端错误"，而实际是它自己已经买成功了。
 * 收据是唯一凭据（JWS 里的权威 purchaseToken），重放的正确语义是「返回当前权益」，
 * 不是再记一单、也不是报错。
 */
import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';

import { initDb } from '../src/db.js';
import iapRouter from '../src/routes/iap.js';
import { issueToken } from '../src/middleware/auth.js';
import { makeJws, purchaseOrderPayload, subscriptionStatusPayload, TEST_ROOT_CERT_PATH } from './fixtures/jws.js';

process.env.JWT_SECRET = 'iap-test-secret';
process.env.IAP_ROOT_CERT_PATH = TEST_ROOT_CERT_PATH;
process.env.IAP_APP_ID = '6917619826312400726';

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
const accountId2 = Number(
  db.prepare('INSERT INTO account (union_id, device_id) VALUES (?, ?)').run('u-iap-2', 'dev-iap-2').lastInsertRowid
);
const token2 = issueToken(accountId2, 'dev-iap-2');

/** 同一 payload 重签/重放都是同一张收据（幂等键 = payload.purchaseToken） */
const passJwsWith = (purchaseToken) => makeJws(purchaseOrderPayload({ purchaseToken }));
const subJwsWith = (purchaseToken) => makeJws(subscriptionStatusPayload({
  lastSubscriptionStatus: {
    subGroupGenerationId: 'gen-idem', subscriptionId: 'sub-idem', purchaseToken,
    status: '1', expiresTime: Date.now() + 30 * 24 * 3600 * 1000,
    lastPurchaseOrder: purchaseOrderPayload({
      purchaseToken, productId: 'youjing_sub_monthly', productType: '2',
      purchaseOrderId: 'po-' + purchaseToken.slice(-6), price: 1990,
      duration: 'P1M', subGroupId: 'sg-idem', subGroupGenerationId: 'gen-idem', subscriptionId: 'sub-idem'
    })
  }
}));

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
  const receipt = 'idem-sub-token-000000000000000000000000000000000001';
  const jws = subJwsWith(receipt);
  const first = await verify({ jwsSubscriptionStatus: jws, productType: 'subscription', productId: 'youjing_sub_monthly' });
  const second = await verify({ jwsSubscriptionStatus: jws, productType: 'subscription', productId: 'youjing_sub_monthly' });

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
  const receipt = 'idem-pass-token-00000000000000000000000000000000001';
  const jws = passJwsWith(receipt);
  const first = await verify({ jwsPurchaseOrder: jws, productType: 'pass', localTripId: 'trip-x' });
  const second = await verify({ jwsPurchaseOrder: jws, productType: 'pass', localTripId: 'trip-x' });

  assert.equal(first.status, 200);
  assert.equal(second.status, 200, '重放不该报 500');
  assert.equal(second.body.passId, 'trip-x');

  const orders = db.prepare('SELECT COUNT(*) AS c FROM `order` WHERE purchase_token = ?').get(receipt);
  assert.equal(orders.c, 1, '订单不该重复记账');
});

test('通行证购买时绑上订单号：退款回调只拿收据号也能追回这张通行证', async () => {
  const receipt = 'idem-link-token-00000000000000000000000000000000001';
  const resp = await verify({ jwsPurchaseOrder: passJwsWith(receipt), productType: 'pass', localTripId: 'trip-link' });
  assert.equal(resp.status, 200);

  const orderId = db.prepare('SELECT id FROM `order` WHERE purchase_token = ?').get(receipt).id;
  const pass = db.prepare(
    "SELECT order_id FROM trip_pass WHERE local_trip_id = 'trip-link'"
  ).get();
  assert.equal(pass.order_id, orderId, '没有这层绑定，REFUND 通知就只能记一笔孤儿日志、撤不掉通行证');
});

test('同一通行证收据换账号：第二个人被拒，且不落 pass', async () => {
  // 旧实现先插 trip_pass 再查 order：订单不重复，但第二个人照样白拿一张 active 通行证。
  const receipt = 'idem-shared-pass-00000000000000000000000000000000001';
  const jws = passJwsWith(receipt);
  const first = await verify({ jwsPurchaseOrder: jws, productType: 'pass', localTripId: 'trip-shared' });
  const second = await verify(
    { jwsPurchaseOrder: jws, productType: 'pass', localTripId: 'trip-shared' }, token2);

  assert.equal(first.status, 200);
  assert.equal(second.status, 409);
  assert.equal(second.body.error, 'RECEIPT_ALREADY_USED');

  const passes = db.prepare('SELECT COUNT(*) AS c FROM trip_pass WHERE account_id = ?').get(accountId2);
  assert.equal(passes.c, 0, '收据不能给别人换来通行证');
});

test('同一订阅收据换账号：同样拒绝，不落订阅', async () => {
  const receipt = 'idem-shared-sub-000000000000000000000000000000000001';
  const jws = subJwsWith(receipt);
  const first = await verify({ jwsSubscriptionStatus: jws, productType: 'subscription' });
  const second = await verify({ jwsSubscriptionStatus: jws, productType: 'subscription' }, token2);

  assert.equal(first.status, 200);
  assert.equal(second.status, 409);
  const subs = db.prepare('SELECT COUNT(*) AS c FROM subscription WHERE account_id = ?').get(accountId2);
  assert.equal(subs.c, 0);
});

test('同一订阅收据并发提交：都 200，只落一行订阅与一单', async () => {
  const receipt = 'idem-race-sub-0000000000000000000000000000000000001';
  const jws = subJwsWith(receipt);
  const results = await Promise.all([
    verify({ jwsSubscriptionStatus: jws, productType: 'subscription' }),
    verify({ jwsSubscriptionStatus: jws, productType: 'subscription' })
  ]);
  for (const r of results) {
    assert.equal(r.status, 200);
    assert.equal(r.body.verified, true);
  }
  const subs = db.prepare('SELECT COUNT(*) AS c FROM subscription WHERE purchase_token = ?').get(receipt);
  assert.equal(subs.c, 1);
  const orders = db.prepare('SELECT COUNT(*) AS c FROM `order` WHERE purchase_token = ?').get(receipt);
  assert.equal(orders.c, 1);
});

test('同一通行证收据并发提交：都 200，只落一张通行证与一单', async () => {
  const receipt = 'idem-race-pass-0000000000000000000000000000000000001';
  const jws = passJwsWith(receipt);
  const results = await Promise.all([
    verify({ jwsPurchaseOrder: jws, productType: 'pass', localTripId: 'trip-race' }),
    verify({ jwsPurchaseOrder: jws, productType: 'pass', localTripId: 'trip-race' })
  ]);
  for (const r of results) assert.equal(r.status, 200);
  const passes = db.prepare(
    "SELECT COUNT(*) AS c FROM trip_pass WHERE local_trip_id = 'trip-race'"
  ).get();
  assert.equal(passes.c, 1);
  const orders = db.prepare('SELECT COUNT(*) AS c FROM `order` WHERE purchase_token = ?').get(receipt);
  assert.equal(orders.c, 1);
});

test('已退款的收据再次提交：verified=false，不复活权益', async () => {
  const receipt = 'idem-refunded-00000000000000000000000000000000000001';
  const jws = passJwsWith(receipt);
  const first = await verify({ jwsPurchaseOrder: jws, productType: 'pass', localTripId: 'trip-refunded' });
  assert.equal(first.status, 200);
  assert.equal(first.body.verified, true);

  db.prepare("UPDATE `order` SET status = 'refunded', refunded_at = datetime('now') WHERE purchase_token = ?")
    .run(receipt);

  const again = await verify({ jwsPurchaseOrder: jws, productType: 'pass', localTripId: 'trip-refunded' });
  assert.equal(again.status, 200);
  assert.equal(again.body.verified, false);
});

test('客户端谎报高价商品：记账以 JWS 权威 productId 为准', async () => {
  // payload 里是 monthly（JWS 权威），请求不传 productId 时默认 monthly —— 一致；
  // 这里验证：JWS 是 yearly 时（signature 背书），即便请求自报 monthly 也要拒绝而不是照单全收
  const receipt = 'idem-upgrade-000000000000000000000000000000000000001';
  const yearlyJws = makeJws(purchaseOrderPayload({
    purchaseToken: receipt, productId: 'youjing_sub_yearly', productType: '2',
    price: 9800, duration: 'P1Y'
  }));
  const r = await verify({ jwsPurchaseOrder: yearlyJws, productType: 'subscription', productId: 'youjing_sub_monthly' });
  assert.equal(r.status, 200);
  assert.equal(r.body.verified, false, '自报商品与收据不符必须拒绝');
  const subs = db.prepare('SELECT COUNT(*) AS c FROM subscription WHERE purchase_token = ?').get(receipt).c;
  assert.equal(subs, 0);
});
