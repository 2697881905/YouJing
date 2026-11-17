/**
 * 手表决策的路由决策表（纯逻辑，无 @kit / 无页面 / 无 DAO，可离线断言）。
 *
 * 立场（规格 §7 / §9）：
 * - 手机是唯一裁决者；手表只回 optionKey。
 * - 行程页在场 → 当场执行（保留撤销快照与 toast 体验）。
 * - 行程页不在场 → 落待执行队列；高风险（stake=high）回页后只重新请示，绝不静默执行。
 * - 卡已撤/已决/重复 cardId → 丢弃（幂等）。
 */

import { CompanionStake } from '../companion/CompanionTypes';
import { WATCH_DISMISS_KEY, WATCH_OPTION_CHECKIN, WATCH_OPTION_SKIP, WatchDecision } from 'watchcontract';

export type WatchRouteAction = 'execute' | 'queue' | 'dismiss' | 'drop';

export type CheckinIntent = 'checkin' | 'skip' | 'dismiss' | 'invalid';

export interface WatchRouteContext {
  /** 手机侧仍挂着这张卡（cardId 对得上，且未被手机收起） */
  cardLive: boolean;
  /** 行程页在场（CompanionStore 执行器已注册） */
  pagePresent: boolean;
  /** 卡的风险级：高风险离页不静默执行 */
  stake: CompanionStake;
  /** 同 cardId 已处理过 */
  duplicate: boolean;
}

export interface WatchRoutePlan {
  action: WatchRouteAction;
  reason: string;
}

/** 手表决策的新鲜度上限：超过即视为过时卡（与 WatchBridge 的持久化口径一致） */
export const WATCH_CARD_TTL_MS: number = 30 * 60 * 1000;

/** 入站前置校验结果：pass=false 时由调用方静默丢弃并打日志 */
export interface WatchPrecheck {
  pass: boolean;
  reason: string;
}

export class WatchRoute {
  /** 时间戳过时（ts 非法也算过时，不猜） */
  static isStale(ts: number, now: number): boolean {
    return ts <= 0 || now - ts > WATCH_CARD_TTL_MS;
  }

  /** 卡属于其他账号分区（US-10）；空 uid = 历史记录，按当前账号处理 */
  static isForeignAccount(cardUid: string, currentUid: string): boolean {
    return cardUid.length > 0 && cardUid !== currentUid;
  }

  /**
   * 入站前置校验（顺序即语义）：
   * 1) cardId 对不上 → 卡已撤/已决；2) 过时；3) 跨账号。
   */
  static precheck(cardLive: boolean, cardUid: string, cardTs: number,
    now: number, currentUid: string): WatchPrecheck {
    if (!cardLive) {
      const dead: WatchPrecheck = { pass: false, reason: 'card-not-live' };
      return dead;
    }
    if (WatchRoute.isStale(cardTs, now)) {
      const stale: WatchPrecheck = { pass: false, reason: 'stale' };
      return stale;
    }
    if (WatchRoute.isForeignAccount(cardUid, currentUid)) {
      const foreign: WatchPrecheck = { pass: false, reason: 'foreign-account' };
      return foreign;
    }
    const ok: WatchPrecheck = { pass: true, reason: '' };
    return ok;
  }

  /** 请示卡决策表 */
  static planCompanion(decision: WatchDecision, ctx: WatchRouteContext): WatchRoutePlan {
    if (ctx.duplicate) {
      const dup: WatchRoutePlan = { action: 'drop', reason: 'duplicate' };
      return dup;
    }
    if (!ctx.cardLive) {
      const stale: WatchRoutePlan = { action: 'drop', reason: 'card-not-live' };
      return stale;
    }
    if (decision.optionKey === WATCH_DISMISS_KEY) {
      const dismiss: WatchRoutePlan = { action: 'dismiss', reason: 'watch-dismiss' };
      return dismiss;
    }
    if (!ctx.pagePresent) {
      const off: WatchRoutePlan = {
        action: 'queue',
        reason: ctx.stake === 'high' ? 'high-stake-offpage' : 'offpage'
      };
      return off;
    }
    const exec: WatchRoutePlan = { action: 'execute', reason: 'inpage' };
    return exec;
  }

  /** 打卡卡决策表：只认三个键，其余一律 invalid */
  static checkinIntent(optionKey: string): CheckinIntent {
    if (optionKey === WATCH_OPTION_CHECKIN) {
      return 'checkin';
    }
    if (optionKey === WATCH_OPTION_SKIP) {
      return 'skip';
    }
    if (optionKey === WATCH_DISMISS_KEY) {
      return 'dismiss';
    }
    return 'invalid';
  }
}
