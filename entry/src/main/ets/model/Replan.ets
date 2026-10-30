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

/** 云函数响应（经 ReplanParser 守卫后的内存形态）。 */
export interface ReplanDecision {
  schemaVersion: number;
  keep: KeepStop[];
  freeBlocks: FreeBlock[];
  note: string;
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

export interface ReplanRequest {
  schemaVersion: number;
  now: string;
  skippedId: string;
  day: ReplanRequestDay;
}
