/**
 * 核心行程模型 · 阶段 1 数据契约冻结（开发文档 §3.1）。
 * 字段与后续 ai/TripSchema.ets 的 JSON Schema、TripParser 类型守卫三者同源。
 *
 * 约定：
 * - 枚举值取英文稳定码（AI/存储层用），中文展示标签由 UI 层映射；
 * - 日期一律 'YYYY-MM-DD'，时间一律 'HH:mm'（24 小时制）；
 * - 金额单位：人民币元，number 类型（展示层负责千分位与 tabular-nums）。
 */

/** 活动预约状态（§3.1 五值封闭） */
export enum ActivityStatus {
  BOOKED = 'booked', // 已约
  NOT_BOOKED = 'not_booked', // 未约
  FULL = 'full', // 约满
  PENDING = 'pending', // 待定
  NO_NEED = 'no_need' // 无需预约
}

/** 活动类型（§3.1 七值封闭；类型色点五档见 handoff §6，第六种用图标/文字） */
export enum ActivityCategory {
  TRANSPORT = 'transport', // 交通
  SIGHT = 'sight', // 景点
  FOOD = 'food', // 餐饮
  SHOP = 'shop', // 购物
  REST = 'rest', // 休息/休整
  HOTEL = 'hotel', // 住宿
  OTHER = 'other' // 其他
}

/** 单日强度（低/中/高） */
export enum IntensityLevel {
  LOW = 'low',
  MEDIUM = 'medium',
  HIGH = 'high'
}

/** 餐次 */
export enum MealType {
  BREAKFAST = 'breakfast',
  LUNCH = 'lunch',
  DINNER = 'dinner'
}

/** 相邻活动前的通勤信息（Activity.transport） */
export interface TransportInfo {
  /** 出行方式自由文案（如「地铁 2 号线」「步行」「打车」），UI 直接展示 */
  mode: string;
  /** 耗时，分钟 */
  duration: number;
  /** 通勤详情/换乘说明 */
  detail: string;
}

/** 活动节点 */
export interface Activity {
  id: string;
  time: string;
  endTime: string;
  title: string;
  /** 场所名（POI） */
  location: string;
  address: string;
  longitude: number;
  latitude: number;
  status: ActivityStatus;
  category: ActivityCategory;
  note?: string;
  /** AI 生成的排期理由（屏8/10「为什么排在这里」理由件），可空 */
  reason?: string;
  /** 到达此节点前的通勤（交通类活动本体也走此结构） */
  transport?: TransportInfo;
}

/** 餐饮 */
export interface Meal {
  type: MealType;
  /** 用餐时刻 HH:mm。AI 可省略（旧数据也没有），省略时列表按餐次档位排位、不显示假时间 */
  time?: string;
  name: string;
  location: string;
  note?: string;
  estimatedCost: number;
}

/** 单日行程 */
export interface TripDay {
  /** 从 1 开始 */
  dayIndex: number;
  date: string;
  /** 当日主题（如「故宫国家博物馆文化线」） */
  theme: string;
  intensity: IntensityLevel;
  /** 当日风险提示（天气/闭馆日/预约冲突等，可空） */
  risk?: string;
  dailyCost: number;
  activities: Activity[];
  meals: Meal[];
  /** 当晚住宿描述（区域名 + 建议酒店档位文案） */
  accommodation?: string;
}

/** 行程总览（生成结果头部摘要卡） */
export interface TripOverview {
  totalCost: number;
  /** 亮点条目（3 条左右，serif title 展示） */
  highlights: string[];
  /** 一段话总结 */
  summary: string;
}

/** 行程（聚合根） */
export interface Trip {
  id: string;
  /** 目的地城市 */
  destination: string;
  startDate: string;
  endDate: string;
  /** 出行人数 */
  people: number;
  /** 总预算（元）；v1 仅采集与展示，预算协同为阶段 10 预留 */
  budget: number;
  /** 旅行风格（复用 PlanParams.TravelStyle 的码值） */
  style: string;
  overview: TripOverview;
  days: TripDay[];
  /** 小贴士 */
  tips: string[];
}
