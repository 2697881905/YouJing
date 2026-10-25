/**
 * TripParser：LLM 响应 → Trip 的 ArkTS 端类型守卫（§4.3 第三层防线）。
 *
 * 纪律（开发文档 §8 / 有据教训）：JSON.parse 返回 Object|null，禁直接断言、禁 any；
 * 逐字段校验类型/枚举/数组结构，任一失败抛 AppError(2xxx) 带字段路径；
 * 枚举白名单引用 TripSchema 常量——Schema/接口/守卫同源。
 * 上游约定：LLM 被要求只输出 JSON；extractJson 兜底剥 ``` 围栏与前后杂文。
 */

import { TripSchema } from './TripSchema';
import {
  Activity, ActivityCategory, ActivityStatus, IntensityLevel, Meal, MealType,
  TransportInfo, Trip, TripDay, TripOverview
} from '../model/Trip';
import { AppError } from '../common/error/AppError';
import { ErrorCode } from '../common/error/ErrorCode';

type Obj = Record<string, Object>;

export class TripParser {
  /** 从 LLM 文本中剥出 JSON 主体（容忍 ```json 围栏与前后说明文字） */
  static extractJson(text: string): string {
    const start: number = text.indexOf('{');
    const end: number = text.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw new AppError(ErrorCode.JSON_PARSE_FAILED, '响应中不含 JSON 主体');
    }
    return text.substring(start, end + 1);
  }

  static parseTrip(text: string): Trip {
    let raw: Object | null = null;
    try {
      raw = JSON.parse(TripParser.extractJson(text)) as Object;
    } catch (err) {
      throw new AppError(ErrorCode.JSON_PARSE_FAILED, `JSON 解析失败: ${(err as Error).message}`);
    }
    const root: Obj = TripParser.asObj(raw, '$');
    const days: Object[] = TripParser.asArray(root['days'], 'days');
    if (days.length === 0) {
      throw new AppError(ErrorCode.SCHEMA_VALIDATION_FAILED, 'days 不能为空数组');
    }
    const trip: Trip = {
      id: TripParser.reqStr(root['id'], 'id'),
      destination: TripParser.reqStr(root['destination'], 'destination'),
      startDate: TripParser.reqStr(root['startDate'], 'startDate'),
      endDate: TripParser.reqStr(root['endDate'], 'endDate'),
      people: TripParser.reqInt(root['people'], 'people'),
      budget: TripParser.reqInt(root['budget'], 'budget'),
      style: TripParser.reqStr(root['style'], 'style'),
      overview: TripParser.readOverview(TripParser.reqObj(root['overview'], 'overview')),
      days: days.map((d: Object, i: number): TripDay => TripParser.readDay(d, i)),
      tips: TripParser.strArray(TripParser.reqArray(root['tips'], 'tips'), 'tips')
    };
    if (TripParser.toDateNum(trip.startDate) > TripParser.toDateNum(trip.endDate)) {
      throw new AppError(ErrorCode.SCHEMA_VALIDATION_FAILED, 'startDate 晚于 endDate');
    }
    return trip;
  }

  private static readOverview(o: Obj): TripOverview {
    return {
      totalCost: TripParser.reqInt(o['totalCost'], 'overview.totalCost'),
      highlights: TripParser.strArray(TripParser.reqArray(o['highlights'], 'overview.highlights'),
        'overview.highlights'),
      summary: TripParser.reqStr(o['summary'], 'overview.summary')
    };
  }

  private static readDay(d: Object, i: number): TripDay {
    const o: Obj = TripParser.asObj(d, `days[${i}]`);
    const dayIndex: number = TripParser.reqInt(o['dayIndex'], `days[${i}].dayIndex`);
    if (dayIndex !== i + 1) {
      throw new AppError(ErrorCode.SCHEMA_VALIDATION_FAILED,
        `days[${i}].dayIndex=${dayIndex} 应为 ${i + 1}（必须从 1 连续递增）`);
    }
    const acts: Object[] = TripParser.reqArray(o['activities'], `days[${i}].activities`);
    const meals: Object[] = TripParser.reqArray(o['meals'], `days[${i}].meals`);
    const day: TripDay = {
      dayIndex: dayIndex,
      date: TripParser.reqStr(o['date'], `days[${i}].date`),
      theme: TripParser.reqStr(o['theme'], `days[${i}].theme`),
      intensity: TripParser.reqEnum(o['intensity'], TripSchema.INTENSITY, `days[${i}].intensity`) as IntensityLevel,
      risk: TripParser.optStr(o['risk'], `days[${i}].risk`),
      dailyCost: TripParser.reqInt(o['dailyCost'], `days[${i}].dailyCost`),
      activities: acts.map((a: Object, j: number): Activity => TripParser.readActivity(a, i, j)),
      meals: meals.map((m: Object, j: number): Meal => TripParser.readMeal(m, i, j)),
      accommodation: TripParser.optStr(o['accommodation'], `days[${i}].accommodation`)
    };
    return day;
  }

  private static readActivity(a: Object, i: number, j: number): Activity {
    const o: Obj = TripParser.asObj(a, `days[${i}].activities[${j}]`);
    const p: string = `days[${i}].activities[${j}]`;
    const act: Activity = {
      id: TripParser.reqStr(o['id'], `${p}.id`),
      time: TripParser.reqTime(o['time'], `${p}.time`),
      endTime: TripParser.reqTime(o['endTime'], `${p}.endTime`),
      title: TripParser.reqStr(o['title'], `${p}.title`),
      location: TripParser.reqStr(o['location'], `${p}.location`),
      address: TripParser.reqStr(o['address'], `${p}.address`),
      longitude: TripParser.reqNum(o['longitude'], `${p}.longitude`),
      latitude: TripParser.reqNum(o['latitude'], `${p}.latitude`),
      status: TripParser.reqEnum(o['status'], TripSchema.ACTIVITY_STATUS, `${p}.status`) as ActivityStatus,
      category: TripParser.reqEnum(o['category'], TripSchema.ACTIVITY_CATEGORY, `${p}.category`) as ActivityCategory,
      note: TripParser.optStr(o['note'], `${p}.note`),
      reason: TripParser.optStr(o['reason'], `${p}.reason`),
      transport: o['transport'] === undefined || o['transport'] === null
        ? undefined : TripParser.readTransport(o['transport'], `${p}.transport`)
    };
    if (act.endTime <= act.time) {
      throw new AppError(ErrorCode.TYPE_GUARD_FAILED,
        `${p}.endTime(${act.endTime}) 必须晚于 time(${act.time})，跨午夜的排布不予接受`);
    }
    return act;
  }

  private static readTransport(t: Object, p: string): TransportInfo {
    const o: Obj = TripParser.asObj(t, p);
    return {
      mode: TripParser.reqStr(o['mode'], `${p}.mode`),
      duration: TripParser.reqInt(o['duration'], `${p}.duration`),
      detail: TripParser.reqStr(o['detail'], `${p}.detail`)
    };
  }

  private static readMeal(m: Object, i: number, j: number): Meal {
    const o: Obj = TripParser.asObj(m, `days[${i}].meals[${j}]`);
    const p: string = `days[${i}].meals[${j}]`;
    return {
      type: TripParser.reqEnum(o['type'], TripSchema.MEAL_TYPE, `${p}.type`) as MealType,
      name: TripParser.reqStr(o['name'], `${p}.name`),
      time: TripParser.optStr(o['time'], `${p}.time`),
      location: TripParser.reqStr(o['location'], `${p}.location`),
      note: TripParser.optStr(o['note'], `${p}.note`),
      estimatedCost: TripParser.reqInt(o['estimatedCost'], `${p}.estimatedCost`)
    };
  }

  // ---- 收口原语 ----

  private static asObj(v: Object | undefined | null, p: string): Obj {
    if (typeof v === 'object' && v !== null && !Array.isArray(v)) {
      return v as Obj;
    }
    throw new AppError(ErrorCode.TYPE_GUARD_FAILED, `${p}: 期望 object`);
  }

  private static reqObj(v: Object | undefined, p: string): Obj {
    if (v === undefined) {
      throw new AppError(ErrorCode.SCHEMA_VALIDATION_FAILED, `${p}: 缺字段`);
    }
    return TripParser.asObj(v, p);
  }

  private static asArray(v: Object | undefined | null, p: string): Object[] {
    if (Array.isArray(v)) {
      return v as Object[];
    }
    throw new AppError(ErrorCode.TYPE_GUARD_FAILED, `${p}: 期望 array`);
  }

  private static reqArray(v: Object | undefined, p: string): Object[] {
    if (v === undefined) {
      throw new AppError(ErrorCode.SCHEMA_VALIDATION_FAILED, `${p}: 缺字段`);
    }
    return TripParser.asArray(v, p);
  }

  private static reqStr(v: Object | undefined, p: string): string {
    if (v === undefined) {
      throw new AppError(ErrorCode.SCHEMA_VALIDATION_FAILED, `${p}: 缺字段`);
    }
    if (typeof v !== 'string' || (v as string).length === 0) {
      throw new AppError(ErrorCode.TYPE_GUARD_FAILED, `${p}: 期望非空 string`);
    }
    return v as string;
  }

  private static optStr(v: Object | undefined, p: string): string | undefined {
    if (v === undefined || v === null) {
      return undefined;
    }
    if (typeof v !== 'string') {
      throw new AppError(ErrorCode.TYPE_GUARD_FAILED, `${p}: 期望 string`);
    }
    return (v as string).length > 0 ? v as string : undefined;
  }

  private static strArray(arr: Object[], p: string): string[] {
    return arr.map((v: Object, i: number): string => {
      if (typeof v !== 'string') {
        throw new AppError(ErrorCode.TYPE_GUARD_FAILED, `${p}[${i}]: 期望 string`);
      }
      return v as string;
    });
  }

  private static reqNum(v: Object | undefined, p: string): number {
    if (v === undefined) {
      throw new AppError(ErrorCode.SCHEMA_VALIDATION_FAILED, `${p}: 缺字段`);
    }
    if (typeof v !== 'number') {
      throw new AppError(ErrorCode.TYPE_GUARD_FAILED, `${p}: 期望 number`);
    }
    return v as number;
  }

  private static reqInt(v: Object | undefined, p: string): number {
    const n: number = TripParser.reqNum(v, p);
    if (!Number.isInteger(n)) {
      throw new AppError(ErrorCode.TYPE_GUARD_FAILED, `${p}: 期望整数`);
    }
    return n;
  }

  private static reqEnum(v: Object | undefined, allowed: string[], p: string): string {
    const s: string = TripParser.reqStr(v, p);
    if (allowed.indexOf(s) < 0) {
      throw new AppError(ErrorCode.SCHEMA_VALIDATION_FAILED,
        `${p}: '${s}' 不在枚举 [${allowed.join(',')}]`);
    }
    return s;
  }

  private static reqTime(v: Object | undefined, p: string): string {
    const s: string = TripParser.reqStr(v, p);
    if (!/^\d{2}:\d{2}$/.test(s)) {
      throw new AppError(ErrorCode.SCHEMA_VALIDATION_FAILED, `${p}: '${s}' 非 HH:mm`);
    }
    return s;
  }

  private static toDateNum(date: string): number {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
      throw new AppError(ErrorCode.SCHEMA_VALIDATION_FAILED, `日期 '${date}' 非 YYYY-MM-DD`);
    }
    return Number(date.replace(/-/g, ''));
  }
}
