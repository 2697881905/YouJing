/** ReplanParser 离线断言：响应必须是 schemaVersion=1 的严格 JSON。 */

import { ReplanParser } from '../ai/ReplanParser';
import { ReplanDecision } from '../model/Replan';
import { AppError } from '../common/error/AppError';
import { ErrorCode } from '../common/error/ErrorCode';

let cases = 0;

function ok(cond: boolean, msg: string): void {
  cases += 1;
  if (!cond) {
    throw new Error(`FAIL: ${msg}`);
  }
}

function eq(actual: string | number, expected: string | number, msg: string): void {
  cases += 1;
  if (actual !== expected) {
    throw new Error(`FAIL: ${msg}（actual=${actual} expected=${expected}）`);
  }
}

function codeOf(fn: () => void): number {
  try {
    fn();
    return 0;
  } catch (err) {
    if (err instanceof AppError) {
      return err.code;
    }
    return -1;
  }
}

function keepOf(id: string, dwellMin: number): Record<string, Object> {
  return { 'id': id, 'dwellMin': dwellMin };
}

function textOf(root: Record<string, Object>): string {
  return JSON.stringify(root);
}

const validText = '```json\n' + textOf({
  'schemaVersion': 1,
  'keep': [keepOf('a3', 60), keepOf('a4', 45)],
  'freeBlocks': [{ 'afterId': 'a2', 'minutes': 30 }],
  'note': '下午节奏放缓'
}) + '\n```';
const d: ReplanDecision = ReplanParser.parseDecision(validText);
eq(d.schemaVersion, 1, 'schemaVersion');
eq(d.keep.length, 2, 'keep 长度');
eq(d.keep[1].id, 'a4', 'keep id');
eq(d.keep[1].dwellMin, 45, 'dwellMin');
eq(d.freeBlocks.length, 1, 'freeBlocks 长度');
eq(d.freeBlocks[0].afterId, 'a2', 'afterId');
eq(d.freeBlocks[0].minutes, 30, 'minutes');
eq(d.note, '下午节奏放缓', 'note');

const minimal = ReplanParser.parseDecision(textOf({ 'schemaVersion': 1, 'keep': [keepOf('a3', 15)] }));
eq(minimal.freeBlocks.length, 0, 'freeBlocks 可省略');
eq(minimal.note, '', 'note 可省略');
eq(minimal.keep[0].dwellMin, 15, 'dwellMin 下界 15 接受');

eq(codeOf(() => ReplanParser.parseDecision('not json at all')), ErrorCode.JSON_PARSE_FAILED, '非 JSON → 2001');
eq(codeOf(() => ReplanParser.parseDecision(textOf({ 'keep': [] }))),
  ErrorCode.SCHEMA_VALIDATION_FAILED, '缺 schemaVersion → 2002');
eq(codeOf(() => ReplanParser.parseDecision(textOf({ 'schemaVersion': 2, 'keep': [] }))),
  ErrorCode.SCHEMA_VALIDATION_FAILED, 'schemaVersion=2 → 2002');
eq(codeOf(() => ReplanParser.parseDecision(textOf({ 'schemaVersion': 1, 'keep': 'x' }))),
  ErrorCode.TYPE_GUARD_FAILED, 'keep 非数组 → 2003');
eq(codeOf(() => ReplanParser.parseDecision(textOf({ 'schemaVersion': 1 }))),
  ErrorCode.SCHEMA_VALIDATION_FAILED, '缺 keep → 2002');
eq(codeOf(() => ReplanParser.parseDecision(textOf({
  'schemaVersion': 1, 'keep': Array.from({ length: 21 }, (_, i) => keepOf(`a${i}`, 60))
}))), ErrorCode.SCHEMA_VALIDATION_FAILED, 'keep 超 20 → 2002');
eq(codeOf(() => ReplanParser.parseDecision(textOf({
  'schemaVersion': 1, 'keep': [keepOf('a3', 14)]
}))), ErrorCode.SCHEMA_VALIDATION_FAILED, 'dwellMin 14 → 2002');
eq(codeOf(() => ReplanParser.parseDecision(textOf({
  'schemaVersion': 1, 'keep': [keepOf('a3', 241)]
}))), ErrorCode.SCHEMA_VALIDATION_FAILED, 'dwellMin 241 → 2002');
eq(codeOf(() => ReplanParser.parseDecision(textOf({
  'schemaVersion': 1, 'keep': [keepOf('a3', 60.5)]
}))), ErrorCode.TYPE_GUARD_FAILED, 'dwellMin 非整数 → 2003');
eq(codeOf(() => ReplanParser.parseDecision(textOf({
  'schemaVersion': 1, 'keep': [keepOf('a3', 60), keepOf('a3', 60)]
}))), ErrorCode.TYPE_GUARD_FAILED, 'keep id 重复 → 2003');
eq(codeOf(() => ReplanParser.parseDecision(textOf({
  'schemaVersion': 1, 'keep': [], 'freeBlocks': [
    { 'afterId': 'a1', 'minutes': 30 }, { 'afterId': 'a2', 'minutes': 30 },
    { 'afterId': 'a3', 'minutes': 30 }, { 'afterId': 'a4', 'minutes': 30 }
  ]
}))), ErrorCode.SCHEMA_VALIDATION_FAILED, 'freeBlocks 超 3 → 2002');
eq(codeOf(() => ReplanParser.parseDecision(textOf({
  'schemaVersion': 1, 'keep': [], 'freeBlocks': [{ 'afterId': 'a1', 'minutes': 10 }]
}))), ErrorCode.SCHEMA_VALIDATION_FAILED, 'minutes 10 → 2002');
eq(codeOf(() => ReplanParser.parseDecision(textOf({
  'schemaVersion': 1, 'keep': [], 'note': 'x'.repeat(201)
}))), ErrorCode.SCHEMA_VALIDATION_FAILED, 'note 超 200 → 2002');
eq(codeOf(() => ReplanParser.parseDecision(textOf({
  'schemaVersion': 1, 'keep': [keepOf('', 60)]
}))), ErrorCode.TYPE_GUARD_FAILED, 'id 空串 → 2003');

const extra = ReplanParser.parseDecision(textOf({
  'schemaVersion': 1, 'keep': [keepOf('a3', 60)], 'unknown': 'ignored'
}));
eq(extra.keep.length, 1, '未知字段忽略');

console.log(`REPLAN_PARSER_OK cases=${cases}`);
