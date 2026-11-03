/**
 * Prompt/Schema 契约入口。
 *
 * SOT 不在本文件，也不在 BFF 的任何手写常量里：
 * - 规则与 schema 来自 entry/src/main/ets/ai/{PromptBuilder,TripSchema}.ets；
 * - `npm run sync:prompt` 把 SOT 转译到 `generated/`；
 * - `npm test` 的 hash 校验会在 SOT 改动后拦住漏同步。
 *
 * 因此改提示词或 schema 的正确顺序是：
 *   1. 改 entry/ SOT（需另开范围，不在 bff-only 任务里做）
 *   2. cd bff && npm run sync:prompt
 *   3. npm test
 */

import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { TripSchema } = require('./generated/ai/TripSchema.js');

/** 与 ets `TripSchema.TRIP_JSON_SCHEMA` 完全一致的字符串 */
export const TRIP_JSON_SCHEMA = TripSchema.TRIP_JSON_SCHEMA;

/** 解析后的 JSON Schema 对象；validator 与 response_format 共用 */
export const TRIP_SCHEMA_OBJECT = JSON.parse(TRIP_JSON_SCHEMA);

/** 枚举表也从同源 Schema 读取，避免 BFF 再抄一份 */
export const TRIP_ENUMS = Object.freeze({
  activityStatus: TRIP_SCHEMA_OBJECT.properties.days.items.properties.activities.items
    .properties.status.enum,
  activityCategory: TRIP_SCHEMA_OBJECT.properties.days.items.properties.activities.items
    .properties.category.enum,
  intensity: TRIP_SCHEMA_OBJECT.properties.days.items.properties.intensity.enum,
  mealType: TRIP_SCHEMA_OBJECT.properties.days.items.properties.meals.items
    .properties.type.enum
});

/**
 * 结构化输出配置。
 * 默认 json_schema（用户要求的结构化防线）；上游不支持时用
 * `LLM_RESPONSE_FORMAT=json_object` 显式降级，不静默猜。
 */
export function buildResponseFormat(mode = process.env.LLM_RESPONSE_FORMAT || 'json_schema') {
  if (mode === 'json_object') {
    return { type: 'json_object' };
  }
  if (mode !== 'json_schema') {
    throw new Error(`LLM_RESPONSE_FORMAT 只接受 json_schema | json_object，收到 ${mode}`);
  }
  return {
    type: 'json_schema',
    json_schema: {
      name: 'trip',
      strict: true,
      schema: TRIP_SCHEMA_OBJECT
    }
  };
}
