#!/usr/bin/env node
'use strict';

/**
 * 真机联调桩（仅开发用，不部署）：
 *   /replan          合法决策（remaining 全量、倒序、每站 45 分钟）
 *   /replan-invalid  未知 id → 端侧守卫拒绝 → 本地兜底
 *   /replan-500      非 2xx → 本地兜底
 *   /replan-slow     9 秒后回 → 客户端 6 秒读超时 → 本地兜底
 *
 * 用法：node tools/replan_stub.js
 * 手机侧：hdc -t <dev> rport tcp:8787 tcp:8787
 * App 侧：临时把 ApiConfig.REPLAN_URL 设成 http://127.0.0.1:8787/replan
 * 注意：桩不校验 token；联调完把 REPLAN_URL / REPLAN_TOKEN 恢复为空串。
 */

const http = require('node:http');

const PORT = Number(process.env.PORT || 8787);
const HOST = '127.0.0.1';

function isTime(value) {
  return typeof value === 'string' && /^\d{2}:\d{2}$/.test(value);
}

function minutesOf(value) {
  return Number(value.slice(0, 2)) * 60 + Number(value.slice(3, 5));
}

function remainingOf(body) {
  const nowMin = minutesOf(body.now);
  return body.day.activities.filter((a) =>
    a.id !== body.skippedId &&
    a.category !== 'transport' && a.category !== 'hotel' &&
    a.status !== 'booked' &&
    minutesOf(a.time) >= nowMin);
}

const server = http.createServer((req, res) => {
  let raw = '';
  req.on('data', (chunk) => {
    raw += chunk;
  });
  req.on('end', () => {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    const send = (payload) => res.end(JSON.stringify(payload));
    if (req.url === '/replan-slow') {
      setTimeout(() => send({ schemaVersion: 1, keep: [], freeBlocks: [], note: 'slow' }), 9000);
      return;
    }
    if (req.url === '/replan-500') {
      res.statusCode = 500;
      send({ code: 'STUB', message: 'forced 500' });
      return;
    }
    if (req.url === '/replan-invalid') {
      send({ schemaVersion: 1, keep: [{ id: 'not-exist', dwellMin: 60 }], freeBlocks: [], note: '' });
      return;
    }
    let body = null;
    try {
      body = JSON.parse(raw);
    } catch (err) {
      res.statusCode = 400;
      send({ code: 'BAD_REQUEST', message: 'bad json' });
      return;
    }
    if (!isTime(body.now) || !body.day || !Array.isArray(body.day.activities)) {
      res.statusCode = 422;
      send({ code: 'INVALID_REQUEST', message: 'bad shape' });
      return;
    }
    const remaining = remainingOf(body);
    const keep = remaining.map((a) => ({ id: a.id, dwellMin: 45 })).reverse();
    send({ schemaVersion: 1, keep: keep, freeBlocks: [], note: 'stub 重排' });
  });
});

server.listen(PORT, HOST, () => {
  console.log(`replan stub listening on http://${HOST}:${PORT}`);
});
