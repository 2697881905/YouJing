/**
 * Open-Meteo 响应 → WeatherDay 的 ArkTS 类型守卫（纯逻辑，不碰 @kit）。
 * 天气是锦上添花：任何缺字段/类型不符都抛 AppError，由 WeatherStore 静默降级。
 */

import { AppError } from '../error/AppError';
import { ErrorCode } from '../error/ErrorCode';
import { WeatherDay, WeatherHour } from '../../model/Weather';
import { DateUtils } from '../../utils/DateUtils';

type Obj = Record<string, Object>;

export class WeatherParser {
  /** todayIso 用来在 daily 里挑当天；跨时区找不到时退回第一条 */
  static parse(text: string, todayIso: string): WeatherDay {
    let raw: Object | null = null;
    try {
      raw = JSON.parse(text) as Object;
    } catch (err) {
      throw new AppError(ErrorCode.JSON_PARSE_FAILED, `天气 JSON 解析失败: ${(err as Error).message}`);
    }
    const root: Obj = WeatherParser.asObj(raw, '$');
    const daily: Obj = WeatherParser.asObj(root['daily'], 'daily');
    const hourly: Obj = WeatherParser.asObj(root['hourly'], 'hourly');
    const days: string[] = WeatherParser.strArray(daily['time'], 'daily.time');
    if (days.length === 0) {
      throw new AppError(ErrorCode.SCHEMA_VALIDATION_FAILED, 'daily.time 为空');
    }
    const dayCodes: number[] = WeatherParser.numArray(daily['weather_code'], 'daily.weather_code', 0);
    const maxes: number[] = WeatherParser.numArray(daily['temperature_2m_max'],
      'daily.temperature_2m_max', 0);
    const mins: number[] = WeatherParser.numArray(daily['temperature_2m_min'],
      'daily.temperature_2m_min', 0);
    const rains: number[] = WeatherParser.numArray(daily['precipitation_probability_max'],
      'daily.precipitation_probability_max', 0);

    let index: number = 0;
    if (todayIso.length > 0) {
      const found: number = days.indexOf(todayIso);
      if (found >= 0) {
        index = found;
      }
    }
    const date: string = days[index];
    const hours: WeatherHour[] = WeatherParser.hoursOf(hourly, date);
    if (hours.length === 0) {
      throw new AppError(ErrorCode.SCHEMA_VALIDATION_FAILED, `hourly 缺少 ${date} 的数据`);
    }
    const day: WeatherDay = {
      date: date,
      code: WeatherParser.at(dayCodes, index, 0),
      tempMax: WeatherParser.at(maxes, index, 0),
      tempMin: WeatherParser.at(mins, index, 0),
      rainMax: WeatherParser.at(rains, index, 0),
      hours: hours
    };
    return day;
  }

  private static hoursOf(hourly: Obj, date: string): WeatherHour[] {
    const times: string[] = WeatherParser.strArray(hourly['time'], 'hourly.time');
    const codes: number[] = WeatherParser.numArray(hourly['weather_code'], 'hourly.weather_code', 0);
    const temps: number[] = WeatherParser.numArray(hourly['temperature_2m'],
      'hourly.temperature_2m', 0);
    // 降水概率可能缺测：-1 表示未知，不拿 0 假装「不会下雨」
    const rains: number[] = WeatherParser.numArray(hourly['precipitation_probability'],
      'hourly.precipitation_probability', -1);
    const out: WeatherHour[] = [];
    for (let i = 0; i < times.length; i++) {
      const t: string = times[i];
      if (t.length < 16 || t.substring(0, 10) !== date) {
        continue;
      }
      const min: number = DateUtils.minutesOf(t.substring(11, 16));
      if (min < 0) {
        continue;
      }
      const h: WeatherHour = {
        startMin: min,
        code: WeatherParser.at(codes, i, 0),
        tempC: WeatherParser.at(temps, i, 0),
        rainProb: WeatherParser.at(rains, i, -1)
      };
      out.push(h);
    }
    return out;
  }

  private static at(values: number[], index: number, fallback: number): number {
    if (index < 0 || index >= values.length) {
      return fallback;
    }
    return values[index];
  }

  // ---- 收口原语（与 ReplanParser 同口径） ----

  private static asObj(v: Object | undefined | null, p: string): Obj {
    if (typeof v === 'object' && v !== null && !Array.isArray(v)) {
      return v as Obj;
    }
    throw new AppError(ErrorCode.TYPE_GUARD_FAILED, `${p}: 期望 object`);
  }

  private static asArray(v: Object | undefined | null, p: string): Object[] {
    if (Array.isArray(v)) {
      return v as Object[];
    }
    throw new AppError(ErrorCode.TYPE_GUARD_FAILED, `${p}: 期望 array`);
  }

  private static strArray(v: Object | undefined, p: string): string[] {
    const arr: Object[] = WeatherParser.asArray(v, p);
    const out: string[] = [];
    for (const item of arr) {
      if (typeof item !== 'string') {
        throw new AppError(ErrorCode.TYPE_GUARD_FAILED, `${p}: 期望 string`);
      }
      out.push(item as string);
    }
    return out;
  }

  private static numArray(v: Object | undefined, p: string, nullAs: number): number[] {
    const arr: Object[] = WeatherParser.asArray(v, p);
    const out: number[] = [];
    for (const item of arr) {
      if (item === null || item === undefined) {
        out.push(nullAs);
        continue;
      }
      if (typeof item !== 'number') {
        throw new AppError(ErrorCode.TYPE_GUARD_FAILED, `${p}: 期望 number`);
      }
      out.push(item as number);
    }
    return out;
  }
}
