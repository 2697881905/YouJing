/**
 * 景点数据模型 · 内置资产「景点库」（开发文档 §3.2）。
 * AI 不是数据源：本结构字段即端侧筛选与 Prompt 构造的全部输入。
 */

/** 景点标签（必去/经典/小众/亲子，四值封闭） */
export enum SpotTag {
  MUST_SEE = 'must_see',
  CLASSIC = 'classic',
  NICHE = 'niche',
  FAMILY = 'family'
}

/** 预约规则组。所有硬信息 UI 必须带「以官方为准」标注（§7 决策） */
export interface SpotBooking {
  requiresBooking: boolean;
  /** 预约方式（公众号/官网/电话等自由文案） */
  bookingMethod?: string;
  /** 需提前几天 */
  advanceDays?: number;
  /** 放票时间文案（如「每天 18:00」） */
  releaseTime?: string;
  /** 闭馆日（如「周一」） */
  closedDay?: string;
  /** 预约难度（易/中/难自由文案） */
  difficulty?: string;
}

/** 溯源组（数据管理用，不上 UI） */
export interface DataProvenance {
  /** 数据来源（购买/爬虫/官方） */
  source: string;
  /** 更新时间 'YYYY-MM-DD' */
  updatedAt: string;
  /** 可信度（高/中/低） */
  confidence?: string;
}

/** 景点 */
export interface Spot {
  id: string;
  name: string;
  /** 所在城市（首批北上广深） */
  city: string;
  tags: SpotTag[];
  /** 一句话简介（第一层筛选的精简列表输出字段） */
  brief: string;
  /** 建议游玩时长，分钟 */
  suggestedDuration: number;
  /**
   * 每日一致的开放时段（如「8:30–17:00」「全天开放」）；仅 MapKit 城市有。
   * 各天不一致、有闭馆日或没有数据时留空，界面统一「以官方为准」。
   */
  openingHours?: string;
  /** 热度指数（0-100，组内排序键） */
  popularity: number;
  /** 周边景点 id（第三层规划传入，用于串联） */
  nearbySpotIds: string[];
  longitude: number;
  latitude: number;
  /** 所在区 */
  district: string;
  /** 最近地铁站名 */
  nearestMetro: string;
  /** 入口提示（如「从午门进」） */
  entranceTip?: string;
  booking: SpotBooking;
  provenance: DataProvenance;
}
