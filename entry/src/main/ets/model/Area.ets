/**
 * 住宿区域数据模型 · 内置资产「住宿区域库」（开发文档 §3.2）。
 * 只推荐位置，不接第三方住宿服务（§7 决策）。
 */

/** 价格档位（经济/舒适/豪华；预留 priceLevel，预算协同后期启用） */
export enum AreaPriceTier {
  ECONOMY = 'economy',
  COMFORT = 'comfort',
  LUXURY = 'luxury'
}

/** 浏览分组（核心区/商圈/地铁站，「查看更多区域」的分组键） */
export enum AreaGroup {
  CORE = 'core',
  COMMERCIAL = 'commercial',
  METRO = 'metro'
}

/** 住宿区域 */
export interface Area {
  id: string;
  name: string;
  city: string;
  longitude: number;
  latitude: number;
  /** 一句话描述 */
  description: string;
  /** 锚定地铁站名，1-3 个 */
  anchorStations: string[];
  /** 途经地铁线路 */
  metroLines: string[];
  /** 到机场通勤分钟数 */
  airportMinutes: number;
  /** 到火车站通勤分钟数 */
  trainStationMinutes: number;
  /** 商圈标签 */
  commerceTags: string[];
  /** 餐饮密度（高/中/低） */
  diningDensity: string;
  /** 适合人群（如「亲子」「首次来京」） */
  suitableCrowds: string[];
  priceTier: AreaPriceTier;
  /** 参考价位段文案（如「400-700/晚」），预算协同启用前仅展示 */
  priceRange?: string;
  group: AreaGroup;
  /** 数据来源 */
  source: string;
  /** 更新时间 'YYYY-MM-DD' */
  updatedAt: string;
}
