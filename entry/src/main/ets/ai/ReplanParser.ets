/**
 * ReplanParser：云函数响应 → ReplanDecision 的 ArkTS 类型守卫（方案 §3.4）。
 * 只做结构校验；集合一致性、时间算术在 data/SkipPlanner。
 */

import { TripParser } from './TripParser';
import { AppError } from '../common/error/AppError';
import { ErrorCode } from '../common/error/ErrorCode';
import {
  FreeBlock, KeepStop, ReplanAction, ReplanDecision, REPLAN_MAX_DWELL, REPLAN_MAX_FREE_BLOCKS,
  REPLAN_MAX_FREE_MIN, REPLAN_MAX_KEEP, REPLAN_MAX_NOTE, REPLAN_MIN_DWELL, REPLAN_MIN_FREE_MIN,
  REPLAN_SCHEMA_VERSION
} from '../model/Replan';

type Obj = Record<string, Object>;

export class ReplanParser {
  static parseDecision(text: string): ReplanDecision {
    let raw: Object | null = null;
    try {
      raw = JSON.parse(TripParser.extractJson(text)) as Object;
    } catch (err) {
      if (err instanceof AppError) {
        throw err;
      }
      throw new AppError(ErrorCode.JSON_PARSE_FAILED, `JSON 解析失败: ${(err as Error).message}`);
    }
    const root: Obj = ReplanParser.asObj(raw, '$');
    const version: number = ReplanParser.reqInt(root['schemaVersion'], 'schemaVersion');
    if (version !== REPLAN_SCHEMA_VERSION) {
      throw new AppError(ErrorCode.SCHEMA_VALIDATION_FAILED,
        `schemaVersion=${version} 不受支持（只接受 ${REPLAN_SCHEMA_VERSION}）`);
    }

    const keepArr: Object[] = ReplanParser.reqArray(root['keep'], 'keep');
    if (keepArr.length > REPLAN_MAX_KEEP) {
      throw new AppError(ErrorCode.SCHEMA_VALIDATION_FAILED,
        `keep 超上限 ${REPLAN_MAX_KEEP}（${keepArr.length}）`);
    }
    const keep: KeepStop[] = [];
    const seen: string[] = [];
    for (let i = 0; i < keepArr.length; i++) {
      const o: Obj = ReplanParser.asObj(keepArr[i], `keep[${i}]`);
      const id: string = ReplanParser.reqStr(o['id'], `keep[${i}].id`);
      const dwell: number = ReplanParser.reqInt(o['dwellMin'], `keep[${i}].dwellMin`);
      if (dwell < REPLAN_MIN_DWELL || dwell > REPLAN_MAX_DWELL) {
        throw new AppError(ErrorCode.SCHEMA_VALIDATION_FAILED,
          `keep[${i}].dwellMin=${dwell} 越界 [${REPLAN_MIN_DWELL},${REPLAN_MAX_DWELL}]`);
      }
      if (seen.indexOf(id) >= 0) {
        throw new AppError(ErrorCode.TYPE_GUARD_FAILED, `keep[${i}].id=${id} 重复`);
      }
      seen.push(id);
      const item: KeepStop = { id: id, dwellMin: dwell };
      keep.push(item);
    }

    const freeBlocks: FreeBlock[] = [];
    const blocksRaw: Object | undefined | null = root['freeBlocks'];
    if (blocksRaw !== undefined && blocksRaw !== null) {
      const arr: Object[] = ReplanParser.asArray(blocksRaw, 'freeBlocks');
      if (arr.length > REPLAN_MAX_FREE_BLOCKS) {
        throw new AppError(ErrorCode.SCHEMA_VALIDATION_FAILED,
          `freeBlocks 超上限 ${REPLAN_MAX_FREE_BLOCKS}（${arr.length}）`);
      }
      for (let i = 0; i < arr.length; i++) {
        const o: Obj = ReplanParser.asObj(arr[i], `freeBlocks[${i}]`);
        const afterId: string = ReplanParser.reqStr(o['afterId'], `freeBlocks[${i}].afterId`);
        const minutes: number = ReplanParser.reqInt(o['minutes'], `freeBlocks[${i}].minutes`);
        if (minutes < REPLAN_MIN_FREE_MIN || minutes > REPLAN_MAX_FREE_MIN) {
          throw new AppError(ErrorCode.SCHEMA_VALIDATION_FAILED,
            `freeBlocks[${i}].minutes=${minutes} 越界 ` +
              `[${REPLAN_MIN_FREE_MIN},${REPLAN_MAX_FREE_MIN}]`);
        }
        const block: FreeBlock = { afterId: afterId, minutes: minutes };
        freeBlocks.push(block);
      }
    }

    const note: string = ReplanParser.optStr(root['note'], 'note') ?? '';
    if (note.length > REPLAN_MAX_NOTE) {
      throw new AppError(ErrorCode.SCHEMA_VALIDATION_FAILED, `note 超上限 ${REPLAN_MAX_NOTE} 字`);
    }
    const decision: ReplanDecision = {
      schemaVersion: version,
      keep: keep,
      freeBlocks: freeBlocks,
      note: note
    };
    // P3 对话式可选字段：只有云函数按意图返回时才出现
    const actionRaw: Object | undefined = root['action'];
    if (actionRaw !== undefined && actionRaw !== null) {
      if (typeof actionRaw !== 'string' || !ReplanParser.isAction(actionRaw as string)) {
        throw new AppError(ErrorCode.TYPE_GUARD_FAILED, `action=${String(actionRaw)} 不受支持`);
      }
      decision.action = actionRaw as ReplanAction;
    }
    const targetId: string | undefined = ReplanParser.optStr(root['targetId'], 'targetId');
    if (targetId !== undefined) {
      decision.targetId = targetId;
    }
    const newStopId: string | undefined = ReplanParser.optStr(root['newStopId'], 'newStopId');
    if (newStopId !== undefined) {
      decision.newStopId = newStopId;
    }
    const shiftMinutes: number | undefined = ReplanParser.optInt(root['shiftMinutes'], 'shiftMinutes');
    if (shiftMinutes !== undefined) {
      if (shiftMinutes < REPLAN_MIN_DWELL || shiftMinutes > REPLAN_MAX_DWELL) {
        throw new AppError(ErrorCode.SCHEMA_VALIDATION_FAILED,
          `shiftMinutes=${shiftMinutes} 越界 [${REPLAN_MIN_DWELL},${REPLAN_MAX_DWELL}]`);
      }
      decision.shiftMinutes = shiftMinutes;
    }
    const skipRemaining: boolean | undefined = ReplanParser.optBool(root['skipRemaining'], 'skipRemaining');
    if (skipRemaining !== undefined) {
      decision.skipRemaining = skipRemaining;
    }
    return decision;
  }

  private static isAction(value: string): boolean {
    return value === ReplanAction.SKIP || value === ReplanAction.SHIFT ||
      value === ReplanAction.ADD || value === ReplanAction.REPLACE;
  }

  // ---- 收口原语（与 TripParser 同口径） ----

  private static asObj(v: Object | undefined | null, p: string): Obj {
    if (typeof v === 'object' && v !== null && !Array.isArray(v)) {
      return v as Obj;
    }
    throw new AppError(ErrorCode.TYPE_GUARD_FAILED, `${p}: 期望 object`);
  }

  private static asArray(v: Object | undefined | null, p: string): Object[] {
    if (Array.isArray(v)) {
      return v as Object[];
    }
    throw new AppError(ErrorCode.TYPE_GUARD_FAILED, `${p}: 期望 array`);
  }

  private static reqArray(v: Object | undefined, p: string): Object[] {
    if (v === undefined) {
      throw new AppError(ErrorCode.SCHEMA_VALIDATION_FAILED, `${p}: 缺字段`);
    }
    return ReplanParser.asArray(v, p);
  }

  private static reqStr(v: Object | undefined, p: string): string {
    if (v === undefined) {
      throw new AppError(ErrorCode.SCHEMA_VALIDATION_FAILED, `${p}: 缺字段`);
    }
    if (typeof v !== 'string' || (v as string).length === 0) {
      throw new AppError(ErrorCode.TYPE_GUARD_FAILED, `${p}: 期望非空 string`);
    }
    return v as string;
  }

  private static optStr(v: Object | undefined, p: string): string | undefined {
    if (v === undefined || v === null) {
      return undefined;
    }
    if (typeof v !== 'string') {
      throw new AppError(ErrorCode.TYPE_GUARD_FAILED, `${p}: 期望 string`);
    }
    return (v as string).length > 0 ? v as string : undefined;
  }

  private static reqNum(v: Object | undefined, p: string): number {
    if (v === undefined) {
      throw new AppError(ErrorCode.SCHEMA_VALIDATION_FAILED, `${p}: 缺字段`);
    }
    if (typeof v !== 'number') {
      throw new AppError(ErrorCode.TYPE_GUARD_FAILED, `${p}: 期望 number`);
    }
    return v as number;
  }

  private static reqInt(v: Object | undefined, p: string): number {
    const n: number = ReplanParser.reqNum(v, p);
    if (!Number.isInteger(n)) {
      throw new AppError(ErrorCode.TYPE_GUARD_FAILED, `${p}: 期望整数`);
    }
    return n;
  }

  private static optInt(v: Object | undefined, p: string): number | undefined {
    if (v === undefined || v === null) {
      return undefined;
    }
    if (typeof v !== 'number' || !Number.isInteger(v as number)) {
      throw new AppError(ErrorCode.TYPE_GUARD_FAILED, `${p}: 期望整数`);
    }
    return v as number;
  }

  private static optBool(v: Object | undefined, p: string): boolean | undefined {
    if (v === undefined || v === null) {
      return undefined;
    }
    if (typeof v !== 'boolean') {
      throw new AppError(ErrorCode.TYPE_GUARD_FAILED, `${p}: 期望 boolean`);
    }
    return v as boolean;
  }
}
