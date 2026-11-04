/**
 * 收据校验 fail-closed（D1/D3）—— JWS 本地验签版。
 *
 * 改前 `verifyPurchase()` 恒 `{ verified:true }`：假收据换订阅（D1）、换通行证（D3）。
 * 第一次收口走远端校验桩（IAP_VERIFY_URL 契约）；现已对表华为官方——客户端上报
 * `jwsPurchaseOrder`/`jwsSubscriptionStatus`，服务端用测试证书链本地验签 + 业务校验。
 *
 * 这份用例先喂正对照（真链真签必须通过），再验各种失败方向——只测"拒收"不能证明通路的另一半。
 */
import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';

import { initDb } from '../src/db.js';
import iapRouter from '../src/routes/iap.js';
import { issueToken } from '../src/middleware/auth.js';
import { verifyPurchaseReceipt, iapVerifierConfigured } from '../src/services/iap.js';
import { makeJws, purchaseOrderPayload, subscriptionStatusPayload, chainWithoutOid, TEST_ROOT_CERT_PATH } from './fixtures/jws.js';

process.env.JWT_SECRET = 'iap-verify-secret';
process.env.IAP_ROOT_CERT_PATH = TEST_ROOT_CERT_PATH;
process.env.IAP_APP_ID = '6917619826312400726';

const db = initDb(':memory:');
const app = express();
app.use(express.json({ limit: '2mb' }));
app.use((req, _res, next) => { req.db = db; next(); });
app.use('/v1/iap', iapRouter);
app.use((err, _req, res, _next) => {
  res.status(err.status || 500).json({ error: err.code || 'INTERNAL_ERROR' });
});
let server;
await new Promise((resolve) => { server = app.listen(0, '127.0.0.1', resolve); });
const base = `http://127.0.0.1:${server.address().port}`;
after(() => { server.close(); db.close(); });

const accountId = Number(
  db.prepare('INSERT INTO account (union_id, device_id) VALUES (?, ?)').run('u-verify', 'dev-verify').lastInsertRowid
);
const token = issueToken(accountId, 'dev-verify');

const passJws = () => makeJws(purchaseOrderPayload());
const subStatusJws = () => makeJws(subscriptionStatusPayload());
const subOrderJws = () => makeJws(purchaseOrderPayload({
  purchaseOrderId: 'test-po-sub',
  purchaseToken: 'testptoken000000000000000000000000000000000000000000000003',
  productId: 'youjing_sub_monthly',
  productType: '2',
  price: 1990,
  duration: 'P1M'
}));

test('未配置 APP_ID：fail-closed，一律拒收且 isConfigured=false', async () => {
  const saved = process.env.IAP_APP_ID;
  delete process.env.IAP_APP_ID;
  try {
    assert.equal(iapVerifierConfigured(), false);
    const r = await verifyPurchaseReceipt({ jwsPurchaseOrder: passJws(), productType: 'pass' });
    assert.equal(r.verified, false);
    assert.equal(r.reason, 'IAP_NOT_CONFIGURED');
  } finally {
    process.env.IAP_APP_ID = saved;
  }
});

test('根证书路径不存在：fail-closed（503 的根源）', async () => {
  const saved = process.env.IAP_ROOT_CERT_PATH;
  process.env.IAP_ROOT_CERT_PATH = '/nonexistent/RootCaG2Ecdsa.cer';
  try {
    assert.equal(iapVerifierConfigured(), false);
  } finally {
    process.env.IAP_ROOT_CERT_PATH = saved;
  }
});

test('正对照：真链真签的通行证 JWS 必须通过（否则"全都拒收"也能骗过前面那条）', async () => {
  assert.equal(iapVerifierConfigured(), true);
  const r = await verifyPurchaseReceipt({ jwsPurchaseOrder: passJws(), productType: 'pass' });
  assert.equal(r.verified, true);
  assert.equal(r.receipt.purchaseToken, 'testptoken000000000000000000000000000000000000000000000001');
  assert.equal(r.receipt.environment, 'Production');
});

test('正对照：订阅状态 JWS（SubGroupStatusPayload）通过，purchaseToken 取 last 状态', async () => {
  const r = await verifyPurchaseReceipt({ jwsSubscriptionStatus: subStatusJws(), productType: 'subscription', requestedProductId: 'youjing_sub_monthly' });
  assert.equal(r.verified, true);
  assert.equal(r.receipt.productId, 'youjing_sub_monthly');
});

test('正对照：订阅只给订单 JWS（productType=2）也通过', async () => {
  const r = await verifyPurchaseReceipt({ jwsPurchaseOrder: subOrderJws(), productType: 'subscription', requestedProductId: 'youjing_sub_monthly' });
  assert.equal(r.verified, true);
});

test('验签拦截方向：坏签名 / 无 OID 链 / 根不匹配 / 非法形状，全部拒绝且不抛异常', async () => {
  // 用链上另一把私钥签（签名与叶子证书公钥不匹配）
  assert.equal(
    (await verifyPurchaseReceipt({ jwsPurchaseOrder: makeJws(purchaseOrderPayload(), { keyFile: 'iap-test-inter.key' }), productType: 'pass' })).reason,
    'JWS_BAD_SIGNATURE'
  );
  // 无 OID 叶子：其他华为用途证书不能冒充 IAP 收据
  assert.equal(
    (await verifyPurchaseReceipt({ jwsPurchaseOrder: makeJws(purchaseOrderPayload(), { chain: chainWithoutOid() }), productType: 'pass' })).reason,
    'JWS_MISSING_OID'
  );
  // 非三段式
  assert.equal(
    (await verifyPurchaseReceipt({ jwsPurchaseOrder: 'not-a-jws', productType: 'pass' })).reason,
    'JWS_BAD_FORMAT'
  );
  // 缺 JWS
  assert.equal(
    (await verifyPurchaseReceipt({ productType: 'pass' })).reason,
    'JWS_MISSING_JWS'
  );
});

test('业务校验：他人应用 / 错商品 / 已撤销 / 订阅非生效中，全部拒绝', async () => {
  // applicationId 不匹配（跨应用复用真收据）
  assert.equal(
    (await verifyPurchaseReceipt({ jwsPurchaseOrder: makeJws(purchaseOrderPayload({ applicationId: 'other-app' })), productType: 'pass' })).reason,
    'APP_MISMATCH'
  );
  // productId 不匹配（低买高报：拿 pass 收据换订阅 / 报高价商品）
  assert.equal(
    (await verifyPurchaseReceipt({ jwsPurchaseOrder: makeJws(purchaseOrderPayload({ productId: 'youjing_sub_yearly' })), productType: 'pass' })).reason,
    'PRODUCT_MISMATCH'
  );
  // 已撤销订单
  assert.equal(
    (await verifyPurchaseReceipt({ jwsPurchaseOrder: makeJws(purchaseOrderPayload({ purchaseOrderRevocationReasonCode: '1' })), productType: 'pass' })).reason,
    'RECEIPT_REVOKED'
  );
  // 订阅状态非生效中（已到期 status='2'）
  const expired = subscriptionStatusPayload();
  expired.lastSubscriptionStatus.status = '2';
  assert.equal(
    (await verifyPurchaseReceipt({ jwsSubscriptionStatus: makeJws(expired), productType: 'subscription', requestedProductId: 'youjing_sub_monthly' })).reason,
    'SUB_NOT_ACTIVE'
  );
  // 订阅订单 productId 与请求不符
  assert.equal(
    (await verifyPurchaseReceipt({ jwsPurchaseOrder: subOrderJws(), productType: 'subscription', requestedProductId: 'youjing_sub_yearly' })).reason,
    'PRODUCT_MISMATCH'
  );
});

test('路由层：未配置时 503，且不落订阅/订单（伪造收据换不到订阅）', async () => {
  const saved = process.env.IAP_APP_ID;
  delete process.env.IAP_APP_ID;
  try {
    const resp = await fetch(`${base}/v1/iap/verify`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      body: JSON.stringify({ jwsPurchaseOrder: passJws(), productType: 'subscription', productId: 'youjing_sub_monthly' })
    });
    assert.equal(resp.status, 503);
    const body = await resp.json();
    assert.equal(body.error, 'IAP_NOT_CONFIGURED');

    const subs = db.prepare('SELECT COUNT(*) AS c FROM subscription WHERE account_id = ?').get(accountId);
    const orders = db.prepare('SELECT COUNT(*) AS c FROM `order` WHERE account_id = ?').get(accountId);
    assert.equal(subs.c, 0, '拒绝的收据不能落订阅');
    assert.equal(orders.c, 0, '拒绝的收据不能落订单');
  } finally {
    process.env.IAP_APP_ID = saved;
  }
});

test('路由层：验签拒绝时回 200 verified:false，同样不落库（伪造 JWS 换不到通行证）', async () => {
  const resp = await fetch(`${base}/v1/iap/verify`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ jwsPurchaseOrder: 'forged.header.signature', productType: 'pass', localTripId: 'trip-forged' })
  });
  assert.equal(resp.status, 200);
  const body = await resp.json();
  assert.equal(body.verified, false);
  const passes = db.prepare('SELECT COUNT(*) AS c FROM trip_pass WHERE account_id = ?').get(accountId);
  assert.equal(passes.c, 0, '拒绝的收据不能落通行证');
});

test('路由层：正对照落库——通行证与订阅各买一次', async () => {
  const passResp = await fetch(`${base}/v1/iap/verify`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ jwsPurchaseOrder: passJws(), productType: 'pass', localTripId: 'trip-verify-ok' })
  });
  assert.equal(passResp.status, 200);
  assert.equal((await passResp.json()).verified, true);
  const passes = db.prepare('SELECT COUNT(*) AS c FROM trip_pass WHERE local_trip_id = ?').get('trip-verify-ok').c;
  assert.equal(passes, 1);

  const subResp = await fetch(`${base}/v1/iap/verify`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ jwsSubscriptionStatus: subStatusJws(), productType: 'subscription', productId: 'youjing_sub_monthly' })
  });
  assert.equal(subResp.status, 200);
  assert.equal((await subResp.json()).verified, true);
  const subs = db.prepare('SELECT COUNT(*) AS c FROM subscription WHERE purchase_token = ?')
    .get('testptoken000000000000000000000000000000000000000000000002').c;
  assert.equal(subs, 1, '入库键必须是 JWS 里的权威 purchaseToken');
});

test('非法 productType / 未知商品 id / 缺 JWS / 超长 JWS：400 且不落库', async () => {
  const before = db.prepare('SELECT COUNT(*) AS c FROM `order` WHERE account_id = ?').get(accountId).c;

  const send = async (body) => {
    const resp = await fetch(`${base}/v1/iap/verify`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      body: JSON.stringify(body)
    });
    return { status: resp.status, body: await resp.json() };
  };

  const badType = await send({ jwsPurchaseOrder: passJws(), productType: 'unknown_type' });
  assert.equal(badType.status, 400);
  assert.equal(badType.body.error, 'UNSUPPORTED_PRODUCT_TYPE');

  const badProduct = await send({ jwsSubscriptionStatus: subStatusJws(), productType: 'subscription', productId: 'free_forever' });
  assert.equal(badProduct.status, 400);
  assert.equal(badProduct.body.error, 'UNKNOWN_PRODUCT_ID');

  const missingJws = await send({ productType: 'pass', localTripId: 'trip-x' });
  assert.equal(missingJws.status, 400);
  assert.equal(missingJws.body.error, 'MISSING_JWS');

  const longJws = await send({ jwsPurchaseOrder: 'x'.repeat(8193), productType: 'pass', localTripId: 'trip-x' });
  assert.equal(longJws.status, 400);
  assert.equal(longJws.body.error, 'INVALID_JWS');

  const longTrip = await send({ jwsPurchaseOrder: passJws(), productType: 'pass', localTripId: 't'.repeat(129) });
  assert.equal(longTrip.status, 400);
  assert.equal(longTrip.body.error, 'MISSING_TRIP_ID');

  const after = db.prepare('SELECT COUNT(*) AS c FROM `order` WHERE account_id = ?').get(accountId).c;
  assert.equal(after, before, '被边界校验拒绝的请求不能落订单');
});

// ── 环境闸门（2026-11-04 承接 Trae 改动后补）────────────────────────────
// 沙盒/开发单不花钱。收据验签通过 ≠ 该发货：非生产环境默认拒收，
// 真机沙盒验收要用 IAP_ALLOW_SANDBOX=1 显式放行——漏了这一道，
// 任何人拿沙盒收据就能换到真订阅（钱收不到，权益照发）。
test('环境闸门：非生产收据默认拒收，IAP_ALLOW_SANDBOX=1 才放行', async () => {
  const sandboxJws = makeJws(purchaseOrderPayload({
    environment: 'SANDBOX',
    purchaseOrderId: 'test-po-sandbox-1',
    purchaseToken: 'testptoken-sandbox-gate-0001'
  }));
  const noEnvJws = makeJws(purchaseOrderPayload({
    environment: undefined,
    purchaseOrderId: 'test-po-noenv-1',
    purchaseToken: 'testptoken-noenv-gate-0001'
  }));
  const sub = subscriptionStatusPayload();
  const devSubJws = makeJws({
    ...sub,
    environment: 'Dev',
    lastSubscriptionStatus: { ...sub.lastSubscriptionStatus, purchaseToken: 'testptoken-devsub-gate-0001' }
  });

  // 缺 environment 也按非生产处理（fail-closed 的方向是拒真，不是收假）
  for (const [name, jws, type] of [
    ['SANDBOX 通行证', sandboxJws, 'pass'],
    ['缺 environment 通行证', noEnvJws, 'pass'],
    ['Dev 订阅状态', devSubJws, 'subscription']
  ]) {
    const r = await verifyPurchaseReceipt({
      jwsPurchaseOrder: type === 'pass' ? jws : null,
      jwsSubscriptionStatus: type === 'subscription' ? jws : null,
      productType: type,
      requestedProductId: type === 'pass' ? 'youjing_pass' : 'youjing_sub_monthly'
    });
    assert.equal(r.verified, false, `${name} 默认不该放行`);
    assert.equal(r.reason, 'NON_PRODUCTION_ENVIRONMENT', `${name} 的拒绝原因`);
  }

  // 路由层：这是「收据有效但环境不收」，回 200 verified:false（不是 503 部署态）
  const before = db.prepare('SELECT COUNT(*) AS c FROM `order` WHERE account_id = ?').get(accountId).c;
  const resp = await fetch(`${base}/v1/iap/verify`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ jwsPurchaseOrder: sandboxJws, productType: 'pass', localTripId: 'trip-sandbox-gate' })
  });
  assert.equal(resp.status, 200);
  assert.equal((await resp.json()).verified, false);
  assert.equal(db.prepare('SELECT COUNT(*) AS c FROM `order` WHERE account_id = ?').get(accountId).c,
    before, '被环境闸门拒掉的收据不能落账');

  // 正对照：显式放行后同一张沙盒收据必须过——只测拒收等于没测另一半通路
  process.env.IAP_ALLOW_SANDBOX = '1';
  try {
    const allowed = await verifyPurchaseReceipt({
      jwsPurchaseOrder: sandboxJws, productType: 'pass', requestedProductId: 'youjing_pass'
    });
    assert.equal(allowed.verified, true, 'IAP_ALLOW_SANDBOX=1 时沙盒收据应可验收（真机调试）');
    assert.equal(allowed.receipt.purchaseToken, 'testptoken-sandbox-gate-0001');
    const prodStillOk = await verifyPurchaseReceipt({
      jwsPurchaseOrder: passJws(), productType: 'pass', requestedProductId: 'youjing_pass'
    });
    assert.equal(prodStillOk.verified, true, '放行开关不影响生产收据');
  } finally {
    delete process.env.IAP_ALLOW_SANDBOX;
  }
});
