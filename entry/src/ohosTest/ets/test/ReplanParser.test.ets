/**
 * ReplanParser 回归：响应必须是 schemaVersion=1 的严格 JSON。
 * 上限/越界/重复的拒绝码与 TripParser 同口径（2001/2002/2003）。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { ReplanParser } from '../../../main/ets/ai/ReplanParser';
import { ReplanDecision } from '../../../main/ets/model/Replan';
import { AppError } from '../../../main/ets/common/error/AppError';
import { ErrorCode } from '../../../main/ets/common/error/ErrorCode';

function keepOf(id: string, dwellMin: number): Record<string, Object> {
  const o: Record<string, Object> = { 'id': id, 'dwellMin': dwellMin };
  return o;
}

function blockOf(afterId: string, minutes: number): Record<string, Object> {
  const o: Record<string, Object> = { 'afterId': afterId, 'minutes': minutes };
  return o;
}

function textOf(root: Record<string, Object>): string {
  return JSON.stringify(root);
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

export default function replanParserTest(): void {
  describe('ReplanParser', () => {
    it('parse_valid_decision', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const text: string = '```json\n' + textOf({
        'schemaVersion': 1,
        'keep': [keepOf('a3', 60), keepOf('a4', 45)],
        'freeBlocks': [blockOf('a2', 30)],
        'note': '下午节奏放缓'
      }) + '\n```';
      const d: ReplanDecision = ReplanParser.parseDecision(text);
      expect(d.schemaVersion).assertEqual(1);
      expect(d.keep.length).assertEqual(2);
      expect(d.keep[1].id).assertEqual('a4');
      expect(d.keep[1].dwellMin).assertEqual(45);
      expect(d.freeBlocks.length).assertEqual(1);
      expect(d.freeBlocks[0].afterId).assertEqual('a2');
      expect(d.freeBlocks[0].minutes).assertEqual(30);
      expect(d.note).assertEqual('下午节奏放缓');
    });

    it('optional_fields_default', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const d: ReplanDecision = ReplanParser.parseDecision(
        textOf({ 'schemaVersion': 1, 'keep': [keepOf('a3', 15)] }));
      expect(d.freeBlocks.length).assertEqual(0);
      expect(d.note).assertEqual('');
      expect(d.keep[0].dwellMin).assertEqual(15);

      const extra: ReplanDecision = ReplanParser.parseDecision(textOf({
        'schemaVersion': 1, 'keep': [keepOf('a3', 60)], 'unknown': 'ignored'
      }));
      expect(extra.keep.length).assertEqual(1);
    });

    it('reject_bad_json_and_schema', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(codeOf((): void => {
        ReplanParser.parseDecision('not json at all');
      })).assertEqual(ErrorCode.JSON_PARSE_FAILED);
      expect(codeOf((): void => {
        ReplanParser.parseDecision(textOf({ 'keep': [] }));
      })).assertEqual(ErrorCode.SCHEMA_VALIDATION_FAILED);
      expect(codeOf((): void => {
        ReplanParser.parseDecision(textOf({ 'schemaVersion': 2, 'keep': [] }));
      })).assertEqual(ErrorCode.SCHEMA_VALIDATION_FAILED);
      expect(codeOf((): void => {
        ReplanParser.parseDecision(textOf({ 'schemaVersion': 1, 'keep': 'x' }));
      })).assertEqual(ErrorCode.TYPE_GUARD_FAILED);
      expect(codeOf((): void => {
        ReplanParser.parseDecision(textOf({ 'schemaVersion': 1 }));
      })).assertEqual(ErrorCode.SCHEMA_VALIDATION_FAILED);
    });

    it('reject_keep_limits', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const many: Record<string, Object>[] = [];
      for (let i = 0; i < 21; i++) {
        many.push(keepOf(`a${i}`, 60));
      }
      expect(codeOf((): void => {
        ReplanParser.parseDecision(textOf({ 'schemaVersion': 1, 'keep': many }));
      })).assertEqual(ErrorCode.SCHEMA_VALIDATION_FAILED);
      expect(codeOf((): void => {
        ReplanParser.parseDecision(textOf({ 'schemaVersion': 1, 'keep': [keepOf('a3', 14)] }));
      })).assertEqual(ErrorCode.SCHEMA_VALIDATION_FAILED);
      expect(codeOf((): void => {
        ReplanParser.parseDecision(textOf({ 'schemaVersion': 1, 'keep': [keepOf('a3', 241)] }));
      })).assertEqual(ErrorCode.SCHEMA_VALIDATION_FAILED);
      expect(codeOf((): void => {
        ReplanParser.parseDecision(textOf({ 'schemaVersion': 1, 'keep': [keepOf('a3', 60.5)] }));
      })).assertEqual(ErrorCode.TYPE_GUARD_FAILED);
      expect(codeOf((): void => {
        ReplanParser.parseDecision(textOf({
          'schemaVersion': 1, 'keep': [keepOf('a3', 60), keepOf('a3', 60)]
        }));
      })).assertEqual(ErrorCode.TYPE_GUARD_FAILED);
      expect(codeOf((): void => {
        ReplanParser.parseDecision(textOf({ 'schemaVersion': 1, 'keep': [keepOf('', 60)] }));
      })).assertEqual(ErrorCode.TYPE_GUARD_FAILED);
    });

    it('reject_free_block_and_note_limits', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(codeOf((): void => {
        ReplanParser.parseDecision(textOf({
          'schemaVersion': 1, 'keep': [], 'freeBlocks': [
            blockOf('a1', 30), blockOf('a2', 30), blockOf('a3', 30), blockOf('a4', 30)
          ]
        }));
      })).assertEqual(ErrorCode.SCHEMA_VALIDATION_FAILED);
      expect(codeOf((): void => {
        ReplanParser.parseDecision(textOf({
          'schemaVersion': 1, 'keep': [], 'freeBlocks': [blockOf('a1', 10)]
        }));
      })).assertEqual(ErrorCode.SCHEMA_VALIDATION_FAILED);
      expect(codeOf((): void => {
        ReplanParser.parseDecision(textOf({
          'schemaVersion': 1, 'keep': [], 'note': 'x'.repeat(201)
        }));
      })).assertEqual(ErrorCode.SCHEMA_VALIDATION_FAILED);
    });
  });
}
