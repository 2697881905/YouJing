/**
 * 设备激活的华为 idToken 验签（D10）。
 *
 * 用本地 JWKS + 本地密钥对签真 JWT：验的是与线上同一条 createVerify 通路，
 * 只把华为公钥换成测试公钥。**未验**：真实华为 idToken（要真机登录 + 官方 JWKS，
 * 端到端另跑）。
 */
import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import express from 'express';
import { createSign, generateKeyPairSync, constants } from 'node:crypto';

import { initDb } from '../src/db.js';
import deviceRouter from '../src/routes/device.js';

process.env.JWT_SECRET = 'device-idtoken-secret';
process.env.HUAWEI_CLIENT_ID = 'client-under-test';
process.env.HUAWEI_ISSUER = 'https://accounts.huawei.com';

const { publicKey, privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const publicJwk = publicKey.export({ format: 'jwk' });
const KID = 'kid-under-test';
const jwks = { keys: [{ ...publicJwk, kid: KID, alg: 'PS256', use: 'sig' }] };

const jwksServer = http.createServer((req, res) => {
  req.resume();
  req.on('end', () => {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(jwks));
  });
});
await new Promise((resolve) => jwksServer.listen(0, '127.0.0.1', resolve));
process.env.HUAWEI_JWKS_URL = `http://127.0.0.1:${jwksServer.address().port}/certs`;

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
after(() => { server.close(); jwksServer.close(); db.close(); });

function b64url(buf) { return Buffer.from(buf).toString('base64url'); }

function signJwt(payload, alg) {
  const header = { alg, kid: KID, typ: 'JWT' };
  const h = b64url(JSON.stringify(header));
  const p = b64url(JSON.stringify(payload));
  const input = Buffer.from(`${h}.${p}`);
  const signer = createSign('RSA-SHA256');
  signer.update(input);
  const sig = alg === 'PS256'
    ? signer.sign({ key: privateKey, padding: constants.RSA_PKCS1_PSS_PADDING,
      saltLength: constants.RSA_PSS_SALTLEN_DIGEST })
    : signer.sign(privateKey);
  return `${h}.${p}.${b64url(sig)}`;
}

function payload(overrides = {}) {
  return {
    iss: 'https://accounts.huawei.com',
    aud: 'client-under-test',
    sub: 'union-from-token',
    exp: Math.floor(Date.now() / 1000) + 600,
    ...overrides
  };
}

async function activate(body) {
  const resp = await fetch(`${base}/v1/device/activate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });
  return { status: resp.status, body: await resp.json() };
}

function unionOf(deviceId) {
  const row = db.prepare('SELECT union_id FROM account WHERE device_id = ?').get(deviceId);
  return row === undefined ? '' : row.union_id;
}

test('PS256 合法 idToken：按验签后的 sub 建华为账号', async () => {
  const r = await activate({ deviceId: 'dev-ps256', idToken: signJwt(payload(), 'PS256') });
  assert.equal(r.status, 200);
  assert.ok(r.body.deviceToken.length > 0);
  assert.equal(unionOf('dev-ps256'), 'union-from-token');
});

test('RS256 也接受（官方声明两种算法）', async () => {
  const r = await activate({ deviceId: 'dev-rs256', idToken: signJwt(payload({ sub: 'u-rs256' }), 'RS256') });
  assert.equal(r.status, 200);
  assert.equal(unionOf('dev-rs256'), 'u-rs256');
});

test('篡改 payload / 错 aud / 过期 / alg=none：一律 401，不建账号', async () => {
  const good = signJwt(payload({ sub: 'u-tamper' }), 'PS256');
  const parts = good.split('.');
  const tampered = `${parts[0]}.${b64url(JSON.stringify(payload({ sub: 'u-attacker' })))}.${parts[2]}`;

  const cases = [
    ['dev-tamper', tampered],
    ['dev-bad-aud', signJwt(payload({ aud: 'someone-else' }), 'PS256')],
    ['dev-expired', signJwt(payload({ exp: Math.floor(Date.now() / 1000) - 10 }), 'PS256')],
    ['dev-none', `${b64url(JSON.stringify({ alg: 'none', kid: KID }))}.${b64url(JSON.stringify(payload()))}.`]
  ];
  for (const [deviceId, token] of cases) {
    const r = await activate({ deviceId, idToken: token });
    assert.equal(r.status, 401, deviceId);
    assert.equal(unionOf(deviceId), '', deviceId);
  }
});

test('只带自报 unionId、不带 idToken：按游客建 anon 账号（冒用面关闭）', async () => {
  const r = await activate({ deviceId: 'dev-body-union', unionId: 'victim-union-id' });
  assert.equal(r.status, 200);
  const union = unionOf('dev-body-union');
  assert.equal(union, 'anon-dev-body-union');
  assert.notEqual(union, 'victim-union-id');
});

test('idToken 非字符串：400', async () => {
  const r = await activate({ deviceId: 'dev-bad-token-type', idToken: { evil: true } });
  assert.equal(r.status, 400);
  assert.equal(r.body.error, 'INVALID_ID_TOKEN');
});
