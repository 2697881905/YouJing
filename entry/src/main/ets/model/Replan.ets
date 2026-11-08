/**
 * 跳过与重排的数据契约（方案 §3.4）。
 * 客户端 ↔ 云函数只交换请求/响应两种结构；时间算术留在 data/SkipPlanner。
 */

import { ActivityCategory, ActivityStatus, MealType, TripDay } from './Trip';

export const REPLAN_SCHEMA_VERSION: number = 1;
export const REPLAN_MIN_DWELL: number = 15;
export const REPLAN_MAX_DWELL: number = 240;
export const REPLAN_MAX_KEEP: number = 20;
export const REPLAN_MAX_FREE_BLOCKS: number = 3;
export const REPLAN_MIN_FREE_MIN: number = 15;
export const REPLAN_MAX_FREE_MIN: number = 480;
export const REPLAN_MAX_NOTE: number = 200;
/** 加一站的当日预算上限（分钟）：超过就不加，避免把一天排成赶场 */
export const REPLAN_ADD_BUDGET_MIN: number = 480;

/** LLM 的单项决策：保留谁、停多久。 */
export interface KeepStop {
  id: string;
  dwellMin: number;
}

/** LLM 的额外空档：放在 afterId 结束之后，不写进模型。 */
export interface FreeBlock {
  afterId: string;
  minutes: number;
}

/** P3 对话式接管的四种动作（云函数把自然语言映射到其中一种） */
export enum ReplanAction {
  SKIP = 'skip',
  SHIFT = 'shift',
  ADD = 'add',
  REPLACE = 'replace'
}

/** 云函数响应（经 ReplanParser 守卫后的内存形态）。 */
export interface ReplanDecision {
  schemaVersion: number;
  keep: KeepStop[];
  freeBlocks: FreeBlock[];
  note: string;
  /** P3 对话式：动作与目标；旧跳过响应省略 action 时按 skip 处理 */
  action?: ReplanAction;
  targetId?: string;
  /** 换一站时，端侧候选池里的新站点 id */
  newStopId?: string;
  /** 顺延分钟数（15–240） */
  shiftMinutes?: number;
  /** 跳过时是否把后续所有未开始站点一并改空闲 */
  skipRemaining?: boolean;
}

/** 端侧排程结果：day 是改写后的深拷贝；note 给页面顶部提示。 */
export interface ReplanOutcome {
  day: TripDay;
  note: string;
  usedFallback: boolean;
  /** 行程是否真的变了（顺延无目标时为 false，页面据此不出结果提示） */
  changed?: boolean;
}

/** 请求里只带通勤时长，不带方式/详情（§3.4 示例）。 */
export interface ReplanTransport {
  duration: number;
}

export interface ReplanRequestActivity {
  id: string;
  time: string;
  endTime: string;
  title: string;
  category: ActivityCategory;
  status: ActivityStatus;
  longitude: number;
  latitude: number;
  transport?: ReplanTransport;
}

export interface ReplanRequestMeal {
  type: MealType;
  time?: string;
}

export interface ReplanRequestDay {
  date: string;
  activities: ReplanRequestActivity[];
  meals: ReplanRequestMeal[];
}

/**
 * 三种动作三选一（云函数强校验）：
 * - skippedId：跳过某站（原有能力）；
 * - addStopId：新增站点的 id，该站已带临时时刻放进 day.activities；
 * - replaceStopId：被替换的旧站点 id（换节点不换槽，端侧确定性改写，云函数不做决策）。
 */
export interface ReplanRequest {
  schemaVersion: number;
  now: string;
  skippedId?: string;
  addStopId?: string;
  replaceStopId?: string;
  /** P3 对话式：用户自然语言意愿；与三种 id 动作互斥 */
  intentText?: string;
  /** 换一站/加一站时端侧提供的候选（不含当日已在的站） */
  candidates?: ReplanRequestActivity[];
  day: ReplanRequestDay;
}
