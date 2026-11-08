'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { handler, _test } = require('../index.js');

const ENV = {
  YOUJING_PICK_TOKEN: 'secret',
  LLM_CHAT_URL: 'https://llm.example/v1/chat/completions',
  LLM_API_KEY: 'k',
  LLM_MODEL: 'm'
};

function bodyOf() {
  return {
    city: '杨凌',
    days: 1,
    pace: 'standard',
    interests: '文化/历史',
    candidates: [
      {
        id: 's1', name: '教稼园', tag: '经典', brief: '农耕渊源',
        district: '杨陵区', popularity: 70, suggestedDuration: 60, requiresBooking: false
      },
      {
        id: 's2', name: '农高会会址', tag: '经典', brief: '农业展会会址',
        district: '杨陵区', popularity: 80, suggestedDuration: 90, requiresBooking: true
      }
    ]
  };
}

function eventOf(body, token) {
  return {
    headers: { 'x-youjing-token': token === undefined ? 'secret' : token },
    body: typeof body === 'string' ? body : JSON.stringify(body)
  };
}

function llmReturning(payload) {
  return async () => ({
    ok: true,
    status: 200,
    json: async () => ({ choices: [{ message: { content: JSON.stringify(payload) } }] })
  });
}

test('401 when token mismatches', async () => {
  const res = await handler(eventOf(bodyOf(), 'wrong'), {}, { env: ENV, fetch: llmReturning({}) });
  assert.equal(res.statusCode, 401);
});

test('500 when token is not configured', async () => {
  const res = await handler(eventOf(bodyOf()), {}, { env: {}, fetch: llmReturning({}) });
  assert.equal(res.statusCode, 500);
});

test('400 when body is not JSON', async () => {
  const res = await handler(eventOf('not-json'), {}, { env: ENV, fetch: llmReturning({}) });
  assert.equal(res.statusCode, 400);
});

test('422 when candidates are empty or duplicated', async () => {
  const empty = bodyOf();
  empty.candidates = [];
  assert.equal((await handler(eventOf(empty), {}, { env: ENV, fetch: llmReturning({}) })).statusCode, 422);
  const dup = bodyOf();
  dup.candidates.push({ ...dup.candidates[0] });
  assert.equal((await handler(eventOf(dup), {}, { env: ENV, fetch: llmReturning({}) })).statusCode, 422);
});

test('happy path returns ranked reasons', async () => {
  const decision = {
    ranked: [{ id: 's2', reason: '会址需预约，先安排' }, { id: 's1', reason: '园子小而安静' }],
    note: '一天先看会址'
  };
  const res = await handler(eventOf(bodyOf()), {}, { env: ENV, fetch: llmReturning(decision) });
  assert.equal(res.statusCode, 200);
  const out = JSON.parse(res.body);
  assert.deepEqual(out.ranked.map((r) => r.id), ['s2', 's1']);
  assert.equal(out.note, '一天先看会址');
});

test('422 when model invents an id or misses one', async () => {
  const extra = {
    ranked: [{ id: 's1', reason: '' }, { id: 's2', reason: '' }, { id: 'zz', reason: '' }],
    note: ''
  };
  assert.equal((await handler(eventOf(bodyOf()), {}, { env: ENV, fetch: llmReturning(extra) })).statusCode, 422);
  const missing = { ranked: [{ id: 's1', reason: '' }], note: '' };
  assert.equal((await handler(eventOf(bodyOf()), {}, { env: ENV, fetch: llmReturning(missing) })).statusCode, 422);
});

test('guard rejects duplicate ids and overlong reason', () => {
  assert.throws(() => _test.guardPick({
    ranked: [{ id: 's1', reason: '' }, { id: 's1', reason: '' }]
  }, ['s1', 's2']));
  assert.throws(() => _test.guardPick({
    ranked: [{ id: 's1', reason: 'x'.repeat(81) }, { id: 's2', reason: '' }]
  }, ['s1', 's2']));
});

test('502 when upstream fails', async () => {
  const res = await handler(eventOf(bodyOf()), {}, {
    env: ENV,
    fetch: async () => ({ ok: false, status: 500, json: async () => ({}) })
  });
  assert.equal(res.statusCode, 502);
});
