import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  buildSystemPrompt, buildUserPrompt, buildMessages, buildResponseFormat,
  expectedDayCount, TRIP_JSON_SCHEMA, TRIP_SCHEMA_OBJECT
} from '../src/prompt/index.js';
import { buildLlmRequestBody } from '../src/services/llm.js';
import { sparseRequest, richRequest } from './fixtures/trip.js';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));
const BFF = fileURLToPath(new URL('../', import.meta.url));
const MANIFEST = join(BFF, 'src', 'prompt', 'generated', 'manifest.json');

function sha256(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

test('prompt-contract 生成物与 entry/ SOT 未漂移', () => {
  const manifest = JSON.parse(readFileSync(MANIFEST, 'utf8'));
  for (const [source, expected] of Object.entries(manifest.sources)) {
    assert.equal(sha256(join(ROOT, source)), expected,
      `${source} 已变化；请 cd bff && npm run sync:prompt`);
  }
  for (const [output, expected] of Object.entries(manifest.outputs)) {
    assert.equal(sha256(join(BFF, 'src', 'prompt', 'generated', output)), expected,
      `${output} 被手改或生成物过期；请 npm run sync:prompt，不要手改 generated/`);
  }
});

test('systemPrompt 携带 19 条规则与同源 JSON Schema', () => {
  const prompt = buildSystemPrompt();
  assert.equal((prompt.match(/^\d+\./gm) || []).length, 19, '规则条数应为 19');
  assert.ok(prompt.includes('JSON Schema:'));
  assert.ok(prompt.includes(TRIP_JSON_SCHEMA), '系统提示词必须内嵌同源 Schema');
  for (const phrase of [
    'days 数组长度必须等于',
    'dayIndex 从 1 连续递增',
    'status 只能取',
    'category 只能取',
    '必须覆盖用户标记为 must',
    '餐饮每天至少午餐、晚餐各一条',
    'address 一律填空串',
    '计划天数为 1 时',
    '各段通勤之和不超过 **8 小时（480 分钟）**',
    '最后一站结束时间 ≤ 第一站开始时间 + 10 小时',
    '禁止编造预约方式',
    '开放'
  ]) {
    assert.ok(prompt.includes(phrase), `缺少关键约束：${phrase}`);
  }
  assert.equal(TRIP_SCHEMA_OBJECT.title, 'Trip');
  assert.deepEqual(TRIP_SCHEMA_OBJECT.properties.days.items.properties.intensity.enum,
    ['low', 'medium', 'high']);
});

test('freeTier 只追加精简要求，不删规则', () => {
  const full = buildSystemPrompt(false);
  const free = buildSystemPrompt(true);
  assert.ok(free.length > full.length);
  assert.ok(free.startsWith(full));
  assert.ok(free.includes('输出尽量精简'));
});

test('sparse 用户消息如实说明缺失字段，不伪造景点细节', () => {
  const user = buildUserPrompt(sparseRequest());
  assert.ok(user.includes('计划天数：3 天'));
  assert.ok(user.includes('预算：8000 元/人'));
  assert.ok(user.includes('住宿区域：碑林区'));
  assert.ok(user.includes('- 西安城墙'));
  assert.ok(user.includes('未提供停留时长、坐标、预约、开放时间'));
  assert.ok(user.includes('以官方为准'));
  assert.ok(!user.includes('建议90分钟'));
  assert.ok(!user.includes('坐标(0.0000,0.0000)'));
});

test('rich 用户消息复用 ets PromptBuilder 的完整景点/区域格式', () => {
  const user = buildUserPrompt(richRequest());
  assert.ok(user.includes('住宿区域：碑林区'));
  assert.ok(user.includes('价格档位 comfort'));
  assert.ok(user.includes('到机场 45 分钟'));
  assert.ok(user.includes('建议90分钟'));
  assert.ok(user.includes('坐标(108.9400,34.2600)'));
  assert.ok(user.includes('开放:8:00–22:00'));
  assert.ok(user.includes('[must]'));
});

test('messages 与 response_format 使用同一 Schema', () => {
  const messages = buildMessages(sparseRequest(), { freeTier: false });
  assert.equal(messages.length, 2);
  assert.equal(messages[0].role, 'system');
  assert.equal(messages[1].role, 'user');

  const schemaFormat = buildResponseFormat('json_schema');
  assert.equal(schemaFormat.type, 'json_schema');
  assert.equal(schemaFormat.json_schema.strict, true);
  assert.deepEqual(schemaFormat.json_schema.schema, TRIP_SCHEMA_OBJECT);

  const body = buildLlmRequestBody(messages, { responseFormat: schemaFormat });
  assert.equal(body.response_format.type, 'json_schema');
  assert.equal(body.response_format.json_schema.schema.title, 'Trip');

  const fallback = buildResponseFormat('json_object');
  assert.deepEqual(fallback, { type: 'json_object' });
});

test('expectedDayCount 与端侧 DateUtils 同口径', () => {
  assert.equal(expectedDayCount(sparseRequest()), 3);
  assert.equal(expectedDayCount({ startDate: '2026-11-06', endDate: '2026-11-06' }), 1);
  assert.equal(expectedDayCount({}), 1);
});
