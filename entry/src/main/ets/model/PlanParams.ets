/**
 * 规划参数模型 · 追问状态机输出与行程生成输入（开发文档 §4.1-5）。
 * PromptBuilder 的输入聚合于此；枚举与屏 3 四题选项一一对应。
 */

import { SpotTag } from './Spot';

/** 旅行风格（屏3 Q1：休闲/暴走/亲子/美食/文化） */
export enum TravelStyle {
  LEISURE = 'leisure',
  FAST_PACE = 'fast_pace',
  FAMILY = 'family',
  FOODIE = 'foodie',
  CULTURE = 'culture'
}

/** 交通方式偏好（屏3 Q3：公共交通/打车为主/包车） */
export enum TransitPreference {
  PUBLIC = 'public',
  TAXI_MAIN = 'taxi_main',
  CHARTER = 'charter'
}

/** 节奏偏好（屏3b Q4 多选：每天3个轻松 / 4-5个标准 / 6+紧凑） */
export enum PaceOption {
  RELAXED = 'relaxed', // 每天 3 个活动
  STANDARD = 'standard', // 每天 4-5 个
  PACKED = 'packed' // 每天 6+
}

/** 景点优先级（屏4 标注：必去/想去/可选） */
export enum SpotPriority {
  MUST = 'must',
  WANT = 'want',
  OPTIONAL = 'optional'
}

/** 用户选中的景点 */
export interface SelectedSpot {
  spotId: string;
  priority: SpotPriority;
  userNote?: string;
}

/** 用户选中的住宿区域 */
export interface SelectedArea {
  areaId: string;
}

/** 行程基础输入（屏2：目的地 + 日期 + 人数 + 预算） */
export interface TripBasicInput {
  destination: string;
  startDate: string;
  endDate: string;
  people: number;
  /** 总预算（元）；0 表示未设 */
  budget: number;
}

/** 生成行程的完整参数（传给 PromptBuilder） */
export interface PlanParams {
  basic: TripBasicInput;
  /** 风格，单选 */
  style: TravelStyle;
  /** 住宿偏好档位（复用 Area.AreaPriceTier 码值字符串） */
  stayTier: string;
  /** 交通偏好，单选 */
  transit: TransitPreference;
  /** 节奏，多选（屏3b）；空数组 = 未选，走默认兜底 */
  paces: PaceOption[];
  selectedSpots: SelectedSpot[];
  selectedArea: SelectedArea;
  /** 端侧第一层筛选用的标签偏好提示（可选，AI 精选参考） */
  tagAffinity?: SpotTag[];
}

/** 追问状态机的问题定义（屏3/3b，App 内状态机，非对话式） */
export interface QuestionOption {
  /** 提交码值（对应上面枚举） */
  value: string;
  /** 按钮文案 */
  label: string;
  /** 选项说明（如「每天 3 个活动」） */
  desc?: string;
}

export interface FlowQuestion {
  id: string;
  title: string;
  /** 标题下辅助说明（屏3「只影响推荐排序，随时可改」） */
  helper?: string;
  options: QuestionOption[];
  multiSelect: boolean;
  /** 默认兜底答案（用户不操作也能生成，§4.2） */
  defaultValues: string[];
}
