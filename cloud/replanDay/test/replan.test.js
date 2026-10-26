'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { handler, _test } = require('../index.js');

const ENV = {
  YOUJING_REPLAN_TOKEN: 'secret',
  LLM_CHAT_URL: 'https://llm.example/v1/chat/completions',
  LLM_API_KEY: 'k',
  LLM_MODEL: 'm'
};

function bodyOf() {
  return {
    schemaVersion: 1,
    now: '14:05',
    skippedId: 'a2',
    day: {
      date: '2026-10-26',
      activities: [
        { id: 'a1', time: '09:00', endTime: '10:00', title: 'past', category: 'sight', status: 'no_need' },
        { id: 'a2', time: '14:00', endTime: '15:00', title: 'skip', category: 'sight', status: 'not_booked' },
        { id: 'a3', time: '15:30', endTime: '16:30', title: 'next1', category: 'sight', status: 'not_booked', transport: { duration: 8 } },
        { id: 'a4', time: '16:45', endTime: '17:30', title: 'next2', category: 'shop', status: 'no_need' },
        { id: 'a5', time: '19:00', endTime: '20:00', title: 'booked', category: 'sight', status: 'booked' }
      ],
      meals: [{ type: 'lunch', time: '12:00' }, { type: 'dinner', time: '18:00' }]
    }
  };
}

function eventOf(body, token) {
  return {
    headers: { 'X-Youjing-Token': token === undefined ? 'secret' : token },
    body: JSON.stringify(body)
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

test('500 when server token is not configured', async () => {
  const res = await handler(eventOf(bodyOf()), {}, { env: {}, fetch: llmReturning({}) });
  assert.equal(res.statusCode, 500);
});

test('422 when skippedId is unknown', async () => {
  const body = bodyOf();
  body.skippedId = 'nope';
  const res = await handler(eventOf(body), {}, { env: ENV, fetch: llmReturning({}) });
  assert.equal(res.statusCode, 422);
});

test('422 when skipped item is booked', async () => {
  const body = bodyOf();
  body.skippedId = 'a5';
  const res = await handler(eventOf(body), {}, { env: ENV, fetch: llmReturning({}) });
  assert.equal(res.statusCode, 422);
});

test('empty remaining returns empty keep without calling the LLM', async () => {
  const body = bodyOf();
  body.day.activities = body.day.activities.filter((a) => a.id === 'a1' || a.id === 'a2');
  const res = await handler(eventOf(body), {}, {
    env: ENV,
    fetch: async () => {
      throw new Error('should not be called');
    }
  });
  assert.equal(res.statusCode, 200);
  assert.deepEqual(JSON.parse(res.body).keep, []);
});

test('happy path accepts any permutation and freeBlocks', async () => {
  const decision = {
    schemaVersion: 1,
    keep: [{ id: 'a4', dwellMin: 45 }, { id: 'a3', dwellMin: 60 }],
    freeBlocks: [{ afterId: 'a2', minutes: 30 }],
    note: '放慢'
  };
  const res = await handler(eventOf(bodyOf()), {}, { env: ENV, fetch: llmReturning(decision) });
  assert.equal(res.statusCode, 200);
  const out = JSON.parse(res.body);
  assert.deepEqual(out.keep.map((k) => k.id).sort(), ['a3', 'a4']);
  assert.equal(out.freeBlocks[0].minutes, 30);
});

test('accepts an object body (AGC may pass parsed JSON)', async () => {
  const decision = {
    schemaVersion: 1,
    keep: [{ id: 'a3', dwellMin: 60 }, { id: 'a4', dwellMin: 45 }],
    freeBlocks: [],
    note: ''
  };
  const res = await handler({ headers: { 'x-youjing-token': 'secret' }, body: bodyOf() }, {},
    { env: ENV, fetch: llmReturning(decision) });
  assert.equal(res.statusCode, 200);
});

test('422 when keep misses an id', async () => {
  const decision = {
    schemaVersion: 1, keep: [{ id: 'a3', dwellMin: 60 }], freeBlocks: [], note: ''
  };
  const res = await handler(eventOf(bodyOf()), {}, { env: ENV, fetch: llmReturning(decision) });
  assert.equal(res.statusCode, 422);
});

test('422 when keep has a duplicate', async () => {
  const decision = {
    schemaVersion: 1,
    keep: [{ id: 'a3', dwellMin: 60 }, { id: 'a3', dwellMin: 60 }],
    freeBlocks: [],
    note: ''
  };
  const res = await handler(eventOf(bodyOf()), {}, { env: ENV, fetch: llmReturning(decision) });
  assert.equal(res.statusCode, 422);
});

test('422 when keep has an extra id', async () => {
  const decision = {
    schemaVersion: 1,
    keep: [{ id: 'a3', dwellMin: 60 }, { id: 'a4', dwellMin: 45 }, { id: 'a1', dwellMin: 30 }],
    freeBlocks: [],
    note: ''
  };
  const res = await handler(eventOf(bodyOf()), {}, { env: ENV, fetch: llmReturning(decision) });
  assert.equal(res.statusCode, 422);
});

test('422 when dwell or freeBlock is out of range', async () => {
  const badDwell = {
    schemaVersion: 1,
    keep: [{ id: 'a3', dwellMin: 14 }, { id: 'a4', dwellMin: 45 }],
    freeBlocks: [],
    note: ''
  };
  const res1 = await handler(eventOf(bodyOf()), {}, { env: ENV, fetch: llmReturning(badDwell) });
  assert.equal(res1.statusCode, 422);
  const badBlock = {
    schemaVersion: 1,
    keep: [{ id: 'a3', dwellMin: 60 }, { id: 'a4', dwellMin: 45 }],
    freeBlocks: [{ afterId: 'a2', minutes: 10 }],
    note: ''
  };
  const res2 = await handler(eventOf(bodyOf()), {}, { env: ENV, fetch: llmReturning(badBlock) });
  assert.equal(res2.statusCode, 422);
});

test('422 when afterId is unknown', async () => {
  const decision = {
    schemaVersion: 1,
    keep: [{ id: 'a3', dwellMin: 60 }, { id: 'a4', dwellMin: 45 }],
    freeBlocks: [{ afterId: 'zz', minutes: 30 }],
    note: ''
  };
  const res = await handler(eventOf(bodyOf()), {}, { env: ENV, fetch: llmReturning(decision) });
  assert.equal(res.statusCode, 422);
});

test('502 when upstream is non-2xx', async () => {
  const res = await handler(eventOf(bodyOf()), {}, {
    env: ENV,
    fetch: async () => ({ ok: false, status: 500, json: async () => ({}) })
  });
  assert.equal(res.statusCode, 502);
});

test('502 when upstream aborts', async () => {
  const res = await handler(eventOf(bodyOf()), {}, {
    env: ENV,
    fetch: async () => {
      const err = new Error('aborted');
      err.name = 'AbortError';
      throw err;
    }
  });
  assert.equal(res.statusCode, 502);
});

test('server recomputes remaining from the raw day', () => {
  const request = _test.normalizeRequest(bodyOf());
  const remaining = _test.remainingOf(request);
  assert.deepEqual(remaining.map((a) => a.id), ['a3', 'a4']);
  const prompt = _test.promptFor(request, remaining);
  assert.ok(prompt.system.includes('不得新增、遗漏或重复'));
  assert.ok(prompt.user.includes('a3'));
  assert.ok(prompt.user.includes('本次空闲段'));
});
