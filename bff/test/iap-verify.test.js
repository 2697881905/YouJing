/**
 * 收据校验 fail-closed（D1/D3）。
 *
 * 改前 `verifyPurchase()` 恒 `{ verified:true }`：假收据换订阅（D1）、换通行证（D3），
 * 再兑换成真额度（D2/D4）。现在未配置校验服务时一律拒绝、配置了只认远端 `verified:true`。
 *
 * 这份用例先喂正对照（配了校验桩必须通过），再验各种失败方向——只测"拒收"不能证明通路的另一半。
 */
import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import express from 'express';

import { initDb } from '../src/db.js';
import iapRouter from '../src/routes/iap.js';
import { issueToken } from '../src/middleware/auth.js';
import { verifyPurchase, iapVerifierConfigured } from '../src/services/iap.js';

process.env.JWT_SECRET = 'iap-verify-secret';

function setVerifier(url) {
  if (url === null) {
    delete process.env.IAP_VERIFY_URL;
    delete process.env.IAP_APP_ID;
    delete process.env.IAP_VERIFY_TOKEN;
    return;
  }
  process.env.IAP_VERIFY_URL = url;
  process.env.IAP_APP_ID = 'verify-test-app';
  process.env.IAP_VERIFY_TOKEN = 'verify-test-token';
}

// 可切换行为的校验桩：/ok 验过、/reject 明确拒绝、/boom 500
const verifier = http.createServer((req, res) => {
  req.resume();
  req.on('end', () => {
    if (req.url === '/boom') {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'internal' }));
      return;
    }
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ verified: req.url === '/ok' }));
  });
});
await new Promise((resolve) => verifier.listen(0, '127.0.0.1', resolve));
const verifierBase = `http://127.0.0.1:${verifier.address().port}`;

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
after(() => { server.close(); verifier.close(); db.close(); });

const accountId = Number(
  db.prepare('INSERT INTO account (union_id, device_id) VALUES (?, ?)').run('u-verify', 'dev-verify').lastInsertRowid
);
const token = issueToken(accountId, 'dev-verify');

test('未配置校验服务：一律拒收，且 isConfigured=false', async () => {
  setVerifier(null);
  assert.equal(iapVerifierConfigured(), false);
  const r = await verifyPurchase('totally-forged-receipt', 'subscription');
  assert.equal(r.verified, false);
  assert.equal(r.reason, 'IAP_NOT_CONFIGURED');
});

test('配置了校验桩：正对照必须通过（否则"全都拒收"也能骗过前面那条）', async () => {
  setVerifier(`${verifierBase}/ok`);
  assert.equal(iapVerifierConfigured(), true);
  const r = await verifyPurchase('real-receipt', 'subscription');
  assert.equal(r.verified, true);
});

test('校验桩明确拒绝 / 5xx / 连不上：都是未通过，且不抛异常', async () => {
  setVerifier(`${verifierBase}/reject`);
  assert.equal((await verifyPurchase('r1', 'pass')).reason, 'VERIFIER_REJECTED');

  setVerifier(`${verifierBase}/boom`);
  assert.equal((await verifyPurchase('r2', 'pass')).reason, 'VERIFIER_HTTP_500');

  setVerifier('http://127.0.0.1:1/verify'); // 端口 1 必然连不上
  const down = await verifyPurchase('r3', 'pass');
  assert.equal(down.verified, false);
  assert.equal(down.reason, 'VERIFIER_UNAVAILABLE');
});

test('路由层：未配置时 503，且不落订阅/订单（伪造收据换不到订阅）', async () => {
  setVerifier(null);
  const resp = await fetch(`${base}/v1/iap/verify`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({
      purchaseToken: 'totally-forged-receipt-123',
      productType: 'subscription',
      productId: 'youjing_sub_monthly'
    })
  });
  assert.equal(resp.status, 503);
  const body = await resp.json();
  assert.equal(body.error, 'IAP_NOT_CONFIGURED');

  const subs = db.prepare('SELECT COUNT(*) AS c FROM subscription WHERE account_id = ?').get(accountId);
  const orders = db.prepare('SELECT COUNT(*) AS c FROM `order` WHERE account_id = ?').get(accountId);
  assert.equal(subs.c, 0, '拒绝的收据不能落订阅');
  assert.equal(orders.c, 0, '拒绝的收据不能落订单');
});

test('路由层：校验桩拒绝时回 200 verified:false，同样不落库', async () => {
  setVerifier(`${verifierBase}/reject`);
  const resp = await fetch(`${base}/v1/iap/verify`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({
      purchaseToken: 'forged-pass-1',
      productType: 'pass',
      localTripId: 'trip-forged'
    })
  });
  assert.equal(resp.status, 200);
  const body = await resp.json();
  assert.equal(body.verified, false);
  const passes = db.prepare('SELECT COUNT(*) AS c FROM trip_pass WHERE account_id = ?').get(accountId);
  assert.equal(passes.c, 0, '拒绝的收据不能落通行证');
});
