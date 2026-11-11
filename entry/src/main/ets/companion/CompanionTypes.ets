/**
 * 伴随式 AI 助手 · 共享类型（纯数据，无 @kit 依赖，可离线断言）。
 *
 * 设计立场（见 Docs/superpowers/plans/2026-11-11-companion-ai-redesign.md）：
 * 助手站在「现实」这边——计划 vs 现实有真实后果时，就地浮出一张「请示卡」，
 * 端出带默认推荐的可点选选项；用户一键/一句话/划掉响应。低风险决定处久了降级为通知。
 * 本文件只定义大脑产出的数据结构，不含逻辑、不含 UI。
 */

import { TripDay } from '../model/Trip';

/** 决定的风险级：high（花钱/不可逆/大幅改行程）永远请示；low 才可降级。 */
export type CompanionStake = 'low' | 'high';

/** 请示 or 通知：由偏好降级决定（高风险恒 ask）。 */
export type CompanionMode = 'ask' | 'notify';

/** 伴随提示的种类（Phase 1 先做规划外到访两类，后续扩 behind/rain 等）。 */
export type CompanionKind = 'unplanned_arrival' | 'unknown_place';

/** 选项背后结构化意图——集成层据此执行（接 SkipPlanner/commitDay），大脑不直接改行程。 */
export type CompanionActionKind = 'move_tomorrow' | 'quick_visit' | 'keep_plan' | 'record_place' | 'none'
  | 'rest' | 'skip_next';

export interface CompanionAction {
  kind: CompanionActionKind;
  /** 受影响的计划节点 id；无则空串 */
  targetId: string;
  /** 顺延量（分钟）；无则 0 */
  deltaMin: number;
  /** 新地点名；无则空串 */
  placeName: string;
}

export interface CompanionOption {
  /** 稳定意图键（偏好计数用，跨文案变更不变） */
  key: string;
  /** 主文案 */
  label: string;
  /** 后果说明 */
  subline: string;
  action: CompanionAction;
}

export interface CompanionPrompt {
  /** 去重键（同情境不重复浮） */
  id: string;
  kind: CompanionKind;
  title: string;
  detail: string;
  options: CompanionOption[];
  /** 默认推荐项下标（保姆级：思考做完，用户多数只确认） */
  recommendedIndex: number;
  stake: CompanionStake;
  mode: CompanionMode;
}

/**
 * 规划外到访的输入。POI 识别由集成层做（ArrivalWatcher + 种子/MapKit），
 * 引擎只吃识别结果，保纯逻辑可测。
 */
export interface UnplannedInput {
  /** 是否识别出地点 */
  recognized: boolean;
  /** 识别出的地点名（未识别空串） */
  placeName: string;
  /** 该地点典型游览时长（分钟） */
  estVisitMin: number;
  /** 当日计划 */
  day: TripDay;
  /** 当前时刻（0-1439） */
  nowMin: number;
}