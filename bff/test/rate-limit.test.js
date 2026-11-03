/**
 * 生成接口的账号限流（成本防护）。
 *
 * 默认 10 次/分钟；窗口与上限可用 env 调小做测试。超出回 429 RATE_LIMITED，
 * 端侧会落到 CLOUD_RATE_LIMITED（「等一分钟再试；重试不会再扣一次额度」）。
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';

import { rateLimitMiddleware, resetRateLimit } from '../src/middleware/rateLimit.js';

process.env.RATE_LIMIT_PER_MINUTE = '2';
process.env.RATE_LIMIT_WINDOW_MS = '120';

const app = express();
app.use((req, _res, next) => { req.accountId = 7; next(); });
app.use(rateLimitMiddleware);
app.get('/ping', (_req, res) => res.json({ ok: true }));
let server;
await new Promise((resolve) => { server = app.listen(0, '127.0.0.1', resolve); });
const base = `http://127.0.0.1:${server.address().port}`;
test.after(() => server.close());

test('超过上限回 429，窗口过去后恢复', async () => {
  resetRateLimit();
  const first = await fetch(`${base}/ping`);
  const second = await fetch(`${base}/ping`);
  const third = await fetch(`${base}/ping`);
  assert.equal(first.status, 200);
  assert.equal(second.status, 200);
  assert.equal(third.status, 429);
  assert.equal((await third.json()).error, 'RATE_LIMITED');

  await new Promise((resolve) => setTimeout(resolve, 140));
  const nextWindow = await fetch(`${base}/ping`);
  assert.equal(nextWindow.status, 200);
});

test('reset 后重新计数（测试用）', async () => {
  resetRateLimit();
  assert.equal((await fetch(`${base}/ping`)).status, 200);
  assert.equal((await fetch(`${base}/ping`)).status, 200);
});
