import test from 'node:test';
import assert from 'node:assert/strict';

import {
  idempotencyMiddleware, canonicalJson, requestHash, scopeKey
} from '../src/middleware/idempotency.js';

const BODY = {
  destination: '西安',
  startDate: '2026-11-06',
  endDate: '2026-11-08',
  people: 2,
  budget: 8000,
  style: 'leisure',
  selectedSpots: ['西安城墙'],
  selectedArea: '碑林区',
  freeTier: false
};

function createRes() {
  return {
    statusCode: 200,
    body: undefined,
    headers: {},
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
    set(name, value) {
      this.headers[name] = value;
      return this;
    }
  };
}

function fakeDb(row) {
  return {
    prepare() {
      return { get: () => row };
    }
  };
}

function run({ row = null, body = BODY, key = 'k-1', accountId = 7 } = {}) {
  const headers = key === null ? {} : { 'idempotency-key': key };
  const req = {
    headers,
    body,
    accountId,
    db: fakeDb(row)
  };
  const res = createRes();
  let nextCalled = false;
  idempotencyMiddleware(req, res, () => {
    nextCalled = true;
  });
  return { req, res, nextCalled };
}

function rowOf({ status, body = BODY, response = undefined }) {
  return {
    idempotency_key: 'ignored',
    account_id: 7,
    request_hash: requestHash(body),
    status,
    response_json: response === undefined ? null : JSON.stringify(response)
  };
}

test('缺少 Idempotency-Key 返回 400', () => {
  const { res, nextCalled } = run({ key: null });
  assert.equal(nextCalled, false);
  assert.equal(res.statusCode, 400);
  assert.equal(res.body.error, 'MISSING_IDEMPOTENCY_KEY');
});

test('缺少账号/设备标识返回 401', () => {
  const { res, nextCalled } = run({ accountId: null });
  assert.equal(nextCalled, false);
  assert.equal(res.statusCode, 401);
  assert.equal(res.body.error, 'TOKEN_INVALID');
});

test('成功重放原样返回首次响应体', () => {
  const first = {
    trip: { id: 'trip-1', destination: '西安' },
    quota: { source: 'gift', remainingToday: 0, giftRemaining: 2, passes: [] }
  };
  const { res, nextCalled } = run({ row: rowOf({ status: 'succeeded', response: first }) });
  assert.equal(nextCalled, false);
  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.body, first);
  assert.equal(res.headers['Idempotency-Replayed'], 'true');
});

test('同键不同体返回 422，不重放也不覆盖', () => {
  const otherBody = { ...BODY, destination: '成都' };
  const first = { trip: { id: 'trip-1' }, quota: { source: 'gift' } };
  const row = rowOf({ status: 'succeeded', body: otherBody, response: first });
  const { res, nextCalled } = run({ row });
  assert.equal(nextCalled, false);
  assert.equal(res.statusCode, 422);
  assert.equal(res.body.error, 'IDEMPOTENCY_KEY_REUSED');
});

test('进行中返回 409', () => {
  const { res, nextCalled } = run({ row: rowOf({ status: 'pending' }) });
  assert.equal(nextCalled, false);
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.error, 'IDEMPOTENCY_IN_PROGRESS');
});

test('失败且同体同键允许重跑，并带上旧行', () => {
  const row = rowOf({ status: 'failed' });
  const { req, res, nextCalled } = run({ row });
  assert.equal(nextCalled, true);
  assert.equal(res.statusCode, 200);
  assert.equal(req.idempotencyExisting, row);
  assert.equal(typeof req.idempotencyKey, 'string');
});

test('失败且同键不同体返回 422', () => {
  const row = rowOf({ status: 'failed', body: { ...BODY, people: 3 } });
  const { res, nextCalled } = run({ row });
  assert.equal(nextCalled, false);
  assert.equal(res.statusCode, 422);
});

test('成功行缺 response_json 时拒绝用请求参数冒充 Trip', () => {
  const row = rowOf({ status: 'succeeded' });
  row.response_json = null;
  const { res, nextCalled } = run({ row });
  assert.equal(nextCalled, false);
  assert.equal(res.statusCode, 500);
  assert.equal(res.body.error, 'IDEMPOTENCY_STATE_CORRUPT');
});

test('response_json 损坏时返回 500 而不是错误数据', () => {
  const row = rowOf({ status: 'succeeded' });
  row.response_json = '{not-json';
  const { res, nextCalled } = run({ row });
  assert.equal(nextCalled, false);
  assert.equal(res.statusCode, 500);
  assert.equal(res.body.error, 'IDEMPOTENCY_STATE_CORRUPT');
});

test('canonicalJson 键序稳定、数组顺序敏感、忽略 undefined 键', () => {
  assert.equal(canonicalJson({ b: 2, a: 1 }), canonicalJson({ a: 1, b: 2 }));
  assert.equal(requestHash({ a: 1, b: undefined }), requestHash({ a: 1 }));
  assert.notEqual(requestHash({ list: [1, 2] }), requestHash({ list: [2, 1] }));
  assert.notEqual(requestHash(BODY), requestHash({ ...BODY, people: 3 }));
});

test('scopeKey 把账号/设备纳入作用域', () => {
  assert.notEqual(scopeKey(7, 'k-1'), scopeKey(8, 'k-1'));
  assert.notEqual(scopeKey(7, 'k-1'), scopeKey(7, 'k-2'));
});
