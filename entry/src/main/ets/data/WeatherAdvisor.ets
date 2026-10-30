/**
 * 天气 → 人类可读简报（纯逻辑，不碰 @kit / UI）。
 *
 * 「有雨」阈值 60% 同时被建议条（TripSignals）复用：两处必须同一口径，
 * 所以阈值只在这里定义一次。
 */

import { WeatherBrief, WeatherDay, WeatherHour } from '../model/Weather';
import { DateUtils } from '../utils/DateUtils';

const RAIN_MIN_PROB: number = 60;
const HEAT_MAX_C: number = 33;
const COLD_MIN_C: number = 0;

export class WeatherAdvisor {
  static readonly RAIN_MIN_PROB: number = RAIN_MIN_PROB;

  /** WMO weather code → 中文短标签 */
  static label(code: number): string {
    if (code === 0) {
      return '晴';
    }
    if (code === 1) {
      return '晴间多云';
    }
    if (code === 2) {
      return '多云';
    }
    if (code === 3) {
      return '阴';
    }
    if (code === 45 || code === 48) {
      return '雾';
    }
    if (code >= 51 && code <= 57) {
      return '毛毛雨';
    }
    if (code >= 61 && code <= 65) {
      return '雨';
    }
    if (code === 66 || code === 67) {
      return '冻雨';
    }
    if (code >= 71 && code <= 77) {
      return '雪';
    }
    if (code >= 80 && code <= 82) {
      return '阵雨';
    }
    if (code === 85 || code === 86) {
      return '阵雪';
    }
    if (code >= 95) {
      return '雷阵雨';
    }
    return '多云';
  }

  static brief(day: WeatherDay): WeatherBrief {
    const max: number = Math.round(day.tempMax);
    const min: number = Math.round(day.tempMin);
    const rain: number = Math.round(day.rainMax);
    const text: string = `今日 ${max}°/${min}° ${WeatherAdvisor.label(day.code)} · 降水 ${rain}%`;
    let advice: string = '';
    const first: WeatherHour | null = WeatherAdvisor.firstRain(day, 0);
    if (first !== null) {
      advice = `${DateUtils.hhmmOf(first.startMin)} 后降水 ${Math.round(first.rainProb)}%`;
    } else if (max >= HEAT_MAX_C) {
      advice = `高温 ${max}°，午间少排室外`;
    } else if (min <= COLD_MIN_C) {
      advice = `最低 ${min}°，注意保暖`;
    }
    const brief: WeatherBrief = { text: text, advice: advice };
    return brief;
  }

  /** fromMin 起第一个降水概率达标的整点；没有返回 null */
  static firstRain(day: WeatherDay, fromMin: number): WeatherHour | null {
    for (const h of day.hours) {
      if (h.startMin < fromMin) {
        continue;
      }
      if (h.rainProb >= RAIN_MIN_PROB) {
        return h;
      }
    }
    return null;
  }

  /** [startMin, endMin) 覆盖到的整点里最大的降水概率；无覆盖/全缺测返回 -1 */
  static rainIn(day: WeatherDay, startMin: number, endMin: number): number {
    let best: number = -1;
    for (const h of day.hours) {
      if (h.startMin + 60 <= startMin || h.startMin >= endMin) {
        continue;
      }
      if (h.rainProb > best) {
        best = h.rainProb;
      }
    }
    return best;
  }
}
