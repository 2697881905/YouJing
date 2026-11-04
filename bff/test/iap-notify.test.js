/**
 * 华为 IAP 服务端关键事件通知（D7）—— 官方 v3 JWS 契约版。
 *
 * 对表结果：通知体是 `{ jwsNotification }`，验签与订单收据同一套（x5c 链 + 根证书 + ES256）。
 * 用本地测试证书链现签真 JWS——验签走的正是线上那条通路。
 * 官方已钉死字段名（notificationType/subtype/notificationRequestId/notificationMetaData），
 * 剩余未验项：第一封真实回调的端到端（AGC 配置通知地址后）。
 */
import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';

import { initDb } from '../src/db.js';
import iapRouter from '../src/routes/iap.js';
import { getEntitlement } from '../src/services/quota.js';
import { makeJws, notificationPayload, TEST_ROOT_CERT_PATH } from './fixtures/jws.js';

process.env.JWT_SECRET = 'iap-notify-test-secret';
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
  res.status(err.status || 500).json({ error: err.code || 'INTERNAL_ERROR' });
});

let server;
await new Promise((resolve) => { server = app.listen(0, '127.0.0.1', resolve); });
const base = `http://127.0.0.1:${server.address().port}`;
after(() => { server.close(); db.close(); });

/** 官方 v3 请求体就是 { jwsNotification } */
async function notify(payload, overrides = {}) {
  const jws = makeJws({ ...notificationPayload(), ...payload });
  const resp = await fetch(`${base}/v1/iap/notify`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ jwsNotification: jws, ...overrides })
  });
  return { status: resp.status, body: await resp.json().catch(() => ({})) };
}

const accountId = Number(
  db.prepare('INSERT INTO account (union_id, device_id) VALUES (?, ?)').run('u-notify', 'dev-notify').lastInsertRowid
);

function seedSubscription(purchaseToken, productId = 'youjing_sub_monthly', periodEnd = '+1 months') {
  db.prepare(
    `INSERT INTO subscription (account_id, product_id, status, period_start, period_end, auto_renew, purchase_token)
     VALUES (?, ?, 'active', datetime('now'), datetime('now', ?), 1, ?)`
  ).run(accountId, productId, periodEnd, purchaseToken);
  db.prepare(
    `INSERT INTO \`order\` (account_id, product_type, product_id, amount_cents, purchase_token, status, paid_at)
     VALUES (?, 'subscription', ?, 1990, ?, 'paid', datetime('now'))`
  ).run(accountId, productId, purchaseToken);
}

test('根证书未配置时 fail closed（503），不能默认信任任意 POST', async () => {
  const saved = process.env.IAP_ROOT_CERT_PATH;
  process.env.IAP_ROOT_CERT_PATH = '/nonexistent/RootCaG2Ecdsa.cer';
  const r = await notify({ notificationRequestId: 'e-503' });
  process.env.IAP_ROOT_CERT_PATH = saved;
  assert.equal(r.status, 503);
  assert.equal(r.body.error, 'NOTIFY_NOT_CONFIGURED');
});

test('缺 jwsNotification / 坏 JWS / 坏签名都拒绝（400 或 401），且不改权益', async () => {
  seedSubscription('sub-guard');

  const missing = await fetch(`${base}/v1/iap/notify`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ foo: 'bar' })
  });
  assert.equal(missing.status, 400);

  const forged = await fetch(`${base}/v1/iap/notify`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ jwsNotification: 'forged.header.sig' })
  });
  assert.equal(forged.status, 401);

  // 签名与叶子证书不匹配的 JWS（另一把私钥签的）
  const badSign = await fetch(`${base}/v1/iap/notify`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      jwsNotification: makeJws({ ...notificationPayload(), notificationRequestId: 'e-badsign' }, { keyFile: 'iap-test-inter.key' })
    })
  });
  assert.equal(badSign.status, 401);

  assert.equal(getEntitlement(db, accountId).subscription?.status, 'active');
  db.prepare("DELETE FROM subscription WHERE purchase_token = 'sub-guard'").run();
  db.prepare("DELETE FROM `order` WHERE purchase_token = 'sub-guard'").run();
});

test('EXPIRE → 订阅失效，权益里不再有 subscription', async () => {
  seedSubscription('sub-expire');
  assert.ok(getEntitlement(db, accountId).subscription);

  const r = await notify({
    notificationType: 'EXPIRE', notificationSubtype: 'VOLUNTARY',
    notificationRequestId: 'e-expire-1',
    notificationMetaData: { environment: 'NORMAL', applicationId: '6917619826312400726', packageName: 'com.youjing.app', type: 2, purchaseToken: 'sub-expire' }
  });
  assert.equal(r.status, 200);
  assert.equal(r.body.applied, true);
  assert.equal(r.body.kind, 'expire');
  assert.equal(getEntitlement(db, accountId).subscription, null);
});

test('同一 notificationRequestId 重推：第二次 applied=false，不重复续期', async () => {
  seedSubscription('sub-renew');
  const payload = {
    notificationType: 'DID_NEW_TRANSACTION', notificationSubtype: 'DID_RENEW',
    notificationRequestId: 'e-renew-1',
    notificationMetaData: { environment: 'NORMAL', applicationId: '6917619826312400726', packageName: 'com.youjing.app', type: 2, currentProductId: 'youjing_sub_monthly', purchaseToken: 'sub-renew', purchaseOrderId: 'po-r1' }
  };

  const first = await notify(payload);
  assert.equal(first.body.applied, true);
  const endAfterFirst = db.prepare(
    "SELECT period_end FROM subscription WHERE purchase_token = 'sub-renew'"
  ).get().period_end;

  const second = await notify(payload);
  assert.equal(second.status, 200);
  assert.equal(second.body.applied, false);
  assert.equal(second.body.kind, 'renew');
  const endAfterSecond = db.prepare(
    "SELECT period_end FROM subscription WHERE purchase_token = 'sub-renew'"
  ).get().period_end;
  assert.equal(endAfterSecond, endAfterFirst, '重推不能把到期日又推一个月');
});

test('DID_RENEW 从较晚者起算：过期很久的订阅续费从今天算，不吃掉追溯期', async () => {
  seedSubscription('sub-late', 'youjing_sub_monthly', '-3 months');
  const r = await notify({
    notificationType: 'DID_NEW_TRANSACTION', notificationSubtype: 'DID_RENEW',
    notificationRequestId: 'e-late',
    notificationMetaData: { environment: 'NORMAL', applicationId: '6917619826312400726', packageName: 'com.youjing.app', type: 2, currentProductId: 'youjing_sub_monthly', purchaseToken: 'sub-late' }
  });
  assert.equal(r.body.applied, true);
  const sub = getEntitlement(db, accountId).subscription;
  assert.ok(sub, '续费后应恢复为 active');
  assert.ok(new Date(sub.periodEnd.replace(' ', 'T') + 'Z') > new Date(), 'period_end 应在未来');
});

test('REVOKE + REFUND_TRANSACTION → 订单退款 + 通行证撤销（按购买时绑的 order_id）', async () => {
  db.prepare(
    `INSERT INTO \`order\` (account_id, product_type, product_id, amount_cents, purchase_token, status, paid_at)
     VALUES (?, 'pass', 'youjing_pass', 990, 'pass-refund-1', 'paid', datetime('now'))`
  ).run(accountId);
  const orderId = db.prepare(
    "SELECT id FROM `order` WHERE purchase_token = 'pass-refund-1'"
  ).get().id;
  db.prepare(
    "INSERT INTO trip_pass (account_id, local_trip_id, status, order_id) VALUES (?, 'trip-refund', 'active', ?)"
  ).run(accountId, orderId);

  const r = await notify({
    notificationType: 'REVOKE', notificationSubtype: 'REFUND_TRANSACTION',
    notificationRequestId: 'e-refund',
    notificationMetaData: { environment: 'NORMAL', applicationId: '6917619826312400726', packageName: 'com.youjing.app', type: 1, purchaseToken: 'pass-refund-1', purchaseOrderId: 'po-pass-1' }
  });
  assert.equal(r.body.applied, true);

  assert.equal(
    db.prepare("SELECT status FROM `order` WHERE id = ?").get(orderId).status, 'refunded'
  );
  assert.equal(
    db.prepare("SELECT status FROM trip_pass WHERE local_trip_id = 'trip-refund'").get().status, 'refunded'
  );
  const ent = getEntitlement(db, accountId);
  assert.equal(ent.passes.find((p) => p.localTripId === 'trip-refund'), undefined, '撤销后不该再出现在权益里');
});

test('AUTO_RENEW_DISABLED 只关续订开关，不断供（旧 CANCEL 语义的正名）', async () => {
  seedSubscription('sub-cancel');
  const r = await notify({
    notificationType: 'DID_CHANGE_RENEWAL_STATUS', notificationSubtype: 'AUTO_RENEW_DISABLED',
    notificationRequestId: 'e-cancel',
    notificationMetaData: { environment: 'NORMAL', applicationId: '6917619826312400726', packageName: 'com.youjing.app', type: 2, purchaseToken: 'sub-cancel' }
  });
  assert.equal(r.status, 200);
  assert.equal(r.body.kind, 'renew_status');
  assert.equal(
    db.prepare("SELECT auto_renew FROM subscription WHERE purchase_token = 'sub-cancel'").get().auto_renew, 0
  );
  assert.ok(getEntitlement(db, accountId).subscription, '关自动续费不能立刻断供，仍有效到期满');
});

test('认不出的事件类型：200 但不改权益（避免华为无限重推）', async () => {
  const r = await notify({
    notificationType: 'SOMETHING_NEW', notificationRequestId: 'e-unknown',
    notificationMetaData: { environment: 'NORMAL', applicationId: '6917619826312400726', packageName: 'com.youjing.app', type: 0, purchaseToken: 'anything' }
  });
  assert.equal(r.status, 200);
  assert.equal(r.body.applied, false);
  assert.equal(r.body.kind, 'unknown');
});

test('TEST 通知（AGC 测试按钮）：200 且不改权益', async () => {
  const r = await notify({ notificationType: 'TEST', notificationRequestId: 'e-test' });
  assert.equal(r.status, 200);
  assert.equal(r.body.applied, false);
  assert.equal(r.body.kind, 'test');
});

test('period_end 已过但通知未到：getEntitlement 也不能再送额度', () => {
  // 用独立账号：同一账号前面几条用例留下的 active 订阅会盖住这一行，那是测试串扰不是产品行为
  const other = Number(
    db.prepare('INSERT INTO account (union_id, device_id) VALUES (?, ?)').run('u-expired', 'dev-expired').lastInsertRowid
  );
  db.prepare(
    `INSERT INTO subscription (account_id, product_id, status, period_start, period_end, auto_renew, purchase_token)
     VALUES (?, 'youjing_sub_monthly', 'active', datetime('now', '-2 months'), datetime('now', '-1 days'), 1, 'sub-past')`
  ).run(other);
  const ent = getEntitlement(db, other);
  assert.equal(ent.subscription, null, '过期订阅不能只靠 status=active 继续生效');
});

test('已退款的订阅不会被迟到的 DID_RENEW 复活', async () => {
  seedSubscription('sub-refund-renew');
  const refund = await notify({
    notificationType: 'REVOKE', notificationSubtype: 'REFUND_TRANSACTION',
    notificationRequestId: 'e-rr-1',
    notificationMetaData: { environment: 'NORMAL', applicationId: '6917619826312400726', packageName: 'com.youjing.app', type: 2, purchaseToken: 'sub-refund-renew' }
  });
  assert.equal(refund.body.applied, true);
  const renew = await notify({
    notificationType: 'DID_NEW_TRANSACTION', notificationSubtype: 'DID_RENEW',
    notificationRequestId: 'e-rr-2',
    notificationMetaData: { environment: 'NORMAL', applicationId: '6917619826312400726', packageName: 'com.youjing.app', type: 2, currentProductId: 'youjing_sub_monthly', purchaseToken: 'sub-refund-renew' }
  });
  assert.equal(renew.status, 200);
  assert.equal(renew.body.applied, false);
  assert.equal(renew.body.kind, 'renew');
  const row = db.prepare(
    "SELECT status FROM subscription WHERE purchase_token = 'sub-refund-renew'"
  ).get();
  assert.equal(row.status, 'refunded');
});
