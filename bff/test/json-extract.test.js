/**
 * 模型输出 JSON 提取（2026-11-03 真实失败形态）。
 *
 * 实测 json_object 模式下模型偶发在 JSON 后面补一句说明，`JSON.parse` 直接抛
 * `Unexpected non-whitespace character after JSON at position 1963`；生产会 502 并让端侧整次重试。
 * 这里只验证「提取第一个完整对象」这件事本身——提取出来的内容仍要过 validateTrip。
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { parseFirstJsonObject } from '../src/lib/json-extract.js';

test('JSON 后跟说明文字：取到前面的完整对象', () => {
  const parsed = parseFirstJsonObject('{"a":1,"b":"x"}\n以上是本次行程，祝旅途愉快。');
  assert.deepEqual(parsed, { a: 1, b: 'x' });
});

test('代码围栏 + 前后杂文：仍取第一个完整对象', () => {
  const parsed = parseFirstJsonObject('好的，结果如下：\n```json\n{"a":{"b":2}}\n```\n请查收。');
  assert.deepEqual(parsed, { a: { b: 2 } });
});

test('字符串里的花括号/转义引号不会把深度算乱', () => {
  const parsed = parseFirstJsonObject('{"note":"含 } 与 \\" 的字符串","ok":true}');
  assert.deepEqual(parsed, { note: '含 } 与 " 的字符串', ok: true });
});

test('两个 JSON 对象：只取第一个', () => {
  const parsed = parseFirstJsonObject('{"first":1}\n{"second":2}');
  assert.deepEqual(parsed, { first: 1 });
});

test('截断/坏 JSON/无对象：返回 null，交给调用方按原错误处理', () => {
  assert.equal(parseFirstJsonObject('{"a":1'), null);
  assert.equal(parseFirstJsonObject('not json at all'), null);
  assert.equal(parseFirstJsonObject(''), null);
  assert.equal(parseFirstJsonObject(undefined), null);
});
