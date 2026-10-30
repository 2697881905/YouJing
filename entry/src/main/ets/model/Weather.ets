/**
 * 天气数据契约（Open-Meteo 子集，切片 3 T1）。
 * 只保留屏15 用得到的字段：当日概览 + 逐小时降水/气温。
 */

/** 一个整点；startMin 是目的地当地当日分钟数（00:00 = 0） */
export interface WeatherHour {
  startMin: number;
  /** WMO weather code */
  code: number;
  /** 气温 °C */
  tempC: number;
  /** 降水概率 %；-1 = 缺测 */
  rainProb: number;
}

export interface WeatherDay {
  /** 目的地当地日期 YYYY-MM-DD */
  date: string;
  /** 当日 WMO weather code */
  code: number;
  tempMax: number;
  tempMin: number;
  /** 当日最大降水概率 % */
  rainMax: number;
  hours: WeatherHour[];
}

/** 屏15 hero 的天气简报；文案由 WeatherAdvisor 生成，UI 只负责显示 */
export interface WeatherBrief {
  /** 今日 6°/20° 晴间多云 · 降水 0% */
  text: string;
  /** 附加建议；没有就空串 */
  advice: string;
}
