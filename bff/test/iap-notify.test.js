/**
 * 华为 IAP 服务端通知（D7）：验签、到期/续费/退款落权益、按 eventId 幂等。
 *
 * 用本地生成的 RSA 密钥对签真签名——验签走的正是线上那条 createVerify 通路，
 * 只是把华为的公钥换成测试公钥。**未验**：华为真实回调的字段名与枚举值（要第一封真通知对表）。
 */
import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { generateKeyPairSync, createSign } from 'node:crypto';

import { initDb } from '../src/db.js';
import iapRouter from '../src/routes/iap.js';
import { getEntitlement } from '../src/services/quota.js';

process.env.JWT_SECRET = 'iap-notify-test-secret';
const { publicKey, privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const PUBLIC_PEM = publicKey.export({ type: 'spki', format: 'pem' });
const PRIVATE_PEM = privateKey.export({ type: 'pkcs8', format: 'pem' });
process.env.IAP_NOTIFY_PUBLIC_KEY = PUBLIC_PEM;

const db = initDb(':memory:');
const app = express();
app.use(express.json({
  limit: '2mb',
  verify: (req, _res, buf) => { req.rawBody = buf; }
}));
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

function sign(raw) {
  return createSign('RSA-SHA256').update(raw).sign(PRIVATE_PEM, 'base64');
}

async function notify(body, { signature, raw } = {}) {
  const text = raw || JSON.stringify(body);
  const headers = { 'Content-Type': 'application/json' };
  if (signature !== null) headers.Authorization = signature || sign(text);
  const resp = await fetch(`${base}/v1/iap/notify`, { method: 'POST', headers, body: text });
  return { status: resp.status, body: await resp.json() };
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

test('未配置公钥时 fail closed（503），不能默认信任任意 POST', async () => {
  const saved = process.env.IAP_NOTIFY_PUBLIC_KEY;
  delete process.env.IAP_NOTIFY_PUBLIC_KEY;
  const r = await notify({ notificationType: 'EXPIRED', purchaseToken: 'x', eventId: 'e-503' });
  process.env.IAP_NOTIFY_PUBLIC_KEY = saved;
  assert.equal(r.status, 503);
  assert.equal(r.body.error, 'NOTIFY_NOT_CONFIGURED');
});

test('缺签名 / 签名对不上都拒绝，且不改权益', async () => {
  seedSubscription('sub-guard');
  const missing = await notify({ notificationType: 'EXPIRED', purchaseToken: 'sub-guard' }, { signature: null });
  assert.equal(missing.status, 401);

  const bad = await notify(
    { notificationType: 'EXPIRED', purchaseToken: 'sub-guard' },
    { signature: Buffer.from('not-a-real-signature').toString('base64') }
  );
  assert.equal(bad.status, 401);

  assert.equal(getEntitlement(db, accountId).subscription?.status, 'active');
  db.prepare("DELETE FROM subscription WHERE purchase_token = 'sub-guard'").run();
  db.prepare("DELETE FROM `order` WHERE purchase_token = 'sub-guard'").run();
});

test('EXPIRED → 订阅失效，权益里不再有 subscription', async () => {
  seedSubscription('sub-expire');
  assert.ok(getEntitlement(db, accountId).subscription);

  const r = await notify({ notificationType: 'EXPIRED', purchaseToken: 'sub-expire', eventId: 'e-expire-1' });
  assert.equal(r.status, 200);
  assert.equal(r.body.applied, true);
  assert.equal(getEntitlement(db, accountId).subscription, null);
});

test('同一 eventId 重推：第二次 applied=false，不重复续期', async () => {
  seedSubscription('sub-renew');
  const body = { notificationType: 'RENEWED', purchaseToken: 'sub-renew', eventId: 'e-renew-1' };

  const first = await notify(body);
  assert.equal(first.body.applied, true);
  const endAfterFirst = db.prepare(
    "SELECT period_end FROM subscription WHERE purchase_token = 'sub-renew'"
  ).get().period_end;

  const second = await notify(body);
  assert.equal(second.status, 200);
  assert.equal(second.body.applied, false);
  assert.equal(second.body.kind, 'renew');
  const endAfterSecond = db.prepare(
    "SELECT period_end FROM subscription WHERE purchase_token = 'sub-renew'"
  ).get().period_end;
  assert.equal(endAfterSecond, endAfterFirst, '重推不能把到期日又推一个月');
});

test('RENEWED 从较晚者起算：过期很久的订阅续费从今天算，不吃掉追溯期', async () => {
  seedSubscription('sub-late', 'youjing_sub_monthly', '-3 months');
  const r = await notify({ notificationType: 'RENEWED', purchaseToken: 'sub-late', eventId: 'e-late' });
  assert.equal(r.body.applied, true);
  const sub = getEntitlement(db, accountId).subscription;
  assert.ok(sub, '续费后应恢复为 active');
  assert.ok(new Date(sub.periodEnd.replace(' ', 'T') + 'Z') > new Date(), 'period_end 应在未来');
});

test('REFUND → 订单退款 + 通行证撤销（按购买时绑的 order_id）', async () => {
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

  const r = await notify({ notificationType: 'REFUND', purchaseToken: 'pass-refund-1', eventId: 'e-refund' });
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

test('认不出的事件类型：200 但不改权益（避免华为无限重推）', async () => {
  const r = await notify({ notificationType: 'SOMETHING_NEW', purchaseToken: 'anything', eventId: 'e-unknown' });
  assert.equal(r.status, 200);
  assert.equal(r.body.applied, false);
  assert.equal(r.body.kind, 'unknown');
});

test('CANCEL 不等于到期：用户关自动续费时订阅仍给额度', async () => {
  seedSubscription('sub-cancel');
  const r = await notify({ notificationType: 'CANCEL', purchaseToken: 'sub-cancel', eventId: 'e-cancel' });
  assert.equal(r.body.applied, false);
  assert.ok(getEntitlement(db, accountId).subscription, 'CANCEL 只改自动续费意向，不能立刻断供');
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

test('已退款的订阅不会被迟到的 RENEWED 复活', async () => {
  seedSubscription('sub-refund-renew');
  const refund = await notify({ notificationType: 'REFUND', purchaseToken: 'sub-refund-renew', eventId: 'e-rr-1' });
  assert.equal(refund.body.applied, true);
  const renew = await notify({ notificationType: 'RENEWED', purchaseToken: 'sub-refund-renew', eventId: 'e-rr-2' });
  assert.equal(renew.status, 200);
  assert.equal(renew.body.applied, false);
  assert.equal(renew.body.kind, 'renew');
  const row = db.prepare(
    "SELECT status FROM subscription WHERE purchase_token = 'sub-refund-renew'"
  ).get();
  assert.equal(row.status, 'refunded');
});
