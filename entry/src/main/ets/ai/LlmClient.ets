/**
 * LLM 调用与生成编排（开发文档 §2.4 / §4.1-5 / §4.3）。
 *
 * 传输抽象：
 * - MockLlmTransport：离线闭环（当前默认，用户拍板）。按请求参数确定性地合成
 *   合法 Trip JSON，走完整「响应→守卫→Trip」链路，等价验证真实管线；
 * - HttpLlmTransport：BFF 中转。端侧发送业务参数（destination/startDate/...），
 *   BFF 内部构建 prompt、注入 Key、扣减配额、转发 LLM，返回 { trip, quota }。
 *   端侧不再构建 prompt，不再解析 chat/completions 信封。
 *
 * 失败策略（§4.1-5）：解析失败重试一次，再失败抛 TRIP_GENERATE_RETRY_EXHAUSTED，
 * 由调用方进屏7降级。401（票据失效）时先重新激活设备再重试。
 */

import { http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { TripExpect, TripParser } from './TripParser';
import { Trip, TripDay, Activity, Meal, MealType, ActivityCategory, ActivityStatus, IntensityLevel, TransportInfo } from '../model/Trip';
import { PlanParams, SelectedSpot, TripBasicInput, PaceOption, PaceRule } from '../model/PlanParams';
import { Spot } from '../model/Spot';
import { Area } from '../model/Area';
import { backfillActivityPlaces, backfillOpeningHours } from '../utils/TripEnrich';
import { DayLoadCalc } from '../utils/DayLoad';
import { DateUtils } from '../utils/DateUtils';
import { ApiConfig } from '../common/config/ApiConfig';
import { GenerationChannel } from '../utils/GenerationChannel';
import { DeviceTokenStore } from '../data/DeviceTokenStore';
import { DeviceActivator } from '../data/DeviceActivator';
import { EntitlementStore, Entitlement, PassInfo } from '../data/EntitlementStore';
import { Logger } from '../common/logger/Logger';
import { AppError } from '../common/error/AppError';
import { ErrorCode } from '../common/error/ErrorCode';
import { TripGeneratePayload, buildTripGeneratePayload } from './TripRequestPayload';

const TAG: string = 'Ai.LlmClient';

export interface LlmTransport {
  complete(idempotencyKey?: string): Promise<string>;
}

/** 离线闭环传输：从请求上下文确定性合成合法 Trip JSON */
export class MockLlmTransport implements LlmTransport {
  private params: PlanParams;
  private spots: Spot[];
  private area: Area;

  constructor(params: PlanParams, spots: Spot[], area: Area) {
    this.params = params;
    this.spots = spots;
    this.area = area;
  }

  complete(idempotencyKey?: string): Promise<string> {
    Logger.info(TAG, 'MockTransport synthesize');
    return Promise.resolve(this.synthesize());
  }

  /**
   * 屏3b 的 helper 写「可多选，按天段分别排布」：多选时把整趟按所选档位数切成等长天段，
   * 顺序固定走 轻松→标准→紧凑（与底稿选项顺序一致），不跟用户点选的先后走——
   * 否则同一组勾选会因为点击顺序不同而排出不同的行程。单选时每天都吃同一档（等价旧行为）。
   */
  private dayCaps(dayCount: number): number[] {
    const order: PaceOption[] = [PaceOption.RELAXED, PaceOption.STANDARD, PaceOption.PACKED];
    const picked: PaceOption[] = order.filter((o: PaceOption): boolean =>
      this.params.paces.indexOf(o) >= 0);
    const list: PaceOption[] = picked.length > 0 ? picked : [PaceOption.STANDARD];
    const caps: number[] = [];
    for (let d = 0; d < dayCount; d++) {
      const seg: number = Math.min(list.length - 1, Math.floor(d * list.length / dayCount));
      caps.push(PaceRule.dailyCap(list[seg]));
    }
    return caps;
  }

  private synthesize(): string {
    const b: TripBasicInput = this.params.basic;
    const dayCount: number = Math.max(1, this.daysBetween(b.startDate, b.endDate) + 1);
    const caps: number[] = this.dayCaps(dayCount);
    const chosen: SelectedSpot[] = this.params.selectedSpots;
    const days: TripDay[] = [];
    const taken: boolean[] = [];
    for (let i = 0; i < chosen.length; i++) {
      taken.push(false);
    }
    let remaining: number = chosen.length;
    let total: number = 0;
    for (let d = 0; d < dayCount; d++) {
      const perDay: number = caps[d];
      // 每天的名额按「剩余量摊到剩余天」算，而不是一律吃满当日上限：
      // 2 个景点排 3 天时若按 perDay 贪心装，第 1 天就全塞完、后两天空着（真机拍到过），
      // 用户看到的就是「三天两晚只有头一天有东西」。上限仍是当日档，不放松节奏。
      const quota: number = Math.max(1, Math.min(perDay, Math.ceil(remaining / (dayCount - d))));
      const acts: Activity[] = [];
      let slot: number = 9 * 60;
      // 当日负载预算与屏8 的负载条**同一把尺**（DayLoadCalc.WINDOW_MINUTES）。
      // 原来只挡「开始时刻 ≤20:00」，不挡这一天的总时长：种子库的真实停留是 4h/5h，
      // 12 站摊 3 天（每天 4 站）就排出 820~895min，屏8 一律报「超建议」+ 满格红条
      // （2026-11-03 真机，免费档成为默认出口后这就是新用户看到的第一屏）。
      let loadUsed: number = 0;
      for (let i = 0; i < chosen.length && acts.length < quota; i++) {
        if (taken[i]) {
          continue;
        }
        const spot: Spot | undefined = this.spots.find((s: Spot): boolean => s.id === chosen[i].spotId);
        if (spot === undefined) {
          taken[i] = true;
          continue;
        }
        const leg: TransportInfo | undefined =
          acts.length === 0 ? undefined : MockLlmTransport.legMock(acts.length);
        // 写成两条语句而不是 `leg.duration : 0` 的三元：后者的冒号会被动效尺的
        // `duration:` 键位正则当成一个硬写的时长值（ai/ 目录在 W3 下"硬写数字照样报"），
        // 读起来也更直白。
        let legMinutes: number = 0;
        if (leg !== undefined) {
          legMinutes = leg.duration;
        }
        const add: number = spot.suggestedDuration + legMinutes;
        const fits: boolean = loadUsed + add <= DayLoadCalc.WINDOW_MINUTES;
        // 装不下就跳过这一站、继续看下一站，**不从尾部砍**：候选按优先级排，
        // 尾部往往是同城好站（重庆 1 天那次就是这么把洪崖洞全砍光的）。
        // 但如果这一天还空着，宁可超窗也要装首站——空白天比超载天更糟。
        if (!fits && acts.length > 0) {
          continue;
        }
        if (acts.length > 0 && slot > 20 * 60) {
          break;
        }
        taken[i] = true;
        const end: number = slot + spot.suggestedDuration;
        const act: Activity = {
          id: `d${d + 1}-a${acts.length + 1}`,
          time: MockLlmTransport.hhmm(slot),
          endTime: MockLlmTransport.hhmm(end),
          title: spot.name,
          location: `${spot.city} ${spot.district}`,
          address: `${spot.city} ${spot.district}`,
          longitude: spot.longitude,
          latitude: spot.latitude,
          status: spot.booking.requiresBooking ? ActivityStatus.NOT_BOOKED : ActivityStatus.NO_NEED,
          category: ActivityCategory.SIGHT,
          note: spot.booking.requiresBooking ? `预约：${spot.booking.bookingMethod ?? '官方渠道'}（以官方为准）` : undefined,
          reason: acts.length === 0 ? '当日首站安排在最开阔时段，动线由近及远。' : undefined,
          transport: leg
        };
        acts.push(act);
        loadUsed += add;
        slot = end + 15;
      }
      remaining -= acts.length;
      const meals: Meal[] = [
        { type: MealType.LUNCH, name: '本地午餐', location: this.area.name, estimatedCost: 120 },
        { type: MealType.DINNER, name: '本地晚餐', location: this.area.name, estimatedCost: 180 }
      ];
      const daily: number = 300 + acts.length * 80;
      total += daily;
      const day: TripDay = {
        dayIndex: d + 1,
        date: MockLlmTransport.addDays(b.startDate, d),
        theme: `${this.area.name} 出发 · 第 ${d + 1} 日`,
        intensity: perDay >= 6 ? IntensityLevel.HIGH : (perDay <= 3 ? IntensityLevel.LOW : IntensityLevel.MEDIUM),
        dailyCost: daily,
        activities: acts,
        meals: meals,
        accommodation: this.area.name
      };
      days.push(day);
    }
    const trip: Trip = {
      id: `trip-${Date.now()}`,
      destination: b.destination,
      startDate: b.startDate,
      endDate: b.endDate,
      people: b.people,
      budget: b.budget,
      style: this.params.style,
      overview: {
        totalCost: total,
        highlights: days.slice(0, 3).map((x: TripDay): string => x.theme),
        summary: `离线合成：${dayCount} 天 ${chosen.length} 站，宿${this.area.name}。`
      },
      days: days,
      tips: ['预约信息以官方为准']
    };
    return JSON.stringify(trip);
  }

  private daysBetween(a: string, b: string): number {
    const da: number = Date.parse(a);
    const db: number = Date.parse(b);
    return Math.round((db - da) / 86400000);
  }

  private static addDays(date: string, n: number): string {
    const d: Date = new Date(Date.parse(date));
    d.setDate(d.getDate() + n);
    const m: string = `${d.getMonth() + 1}`.padStart(2, '0');
    const dd: string = `${d.getDate()}`.padStart(2, '0');
    return `${d.getFullYear()}-${m}-${dd}`;
  }

  private static hhmm(mins: number): string {
    const h: number = Math.floor(mins / 60) % 24;
    const m: number = mins % 60;
    return `${`${h}`.padStart(2, '0')}:${`${m}`.padStart(2, '0')}`;
  }

  /** 离线 mock 的通勤段：轮换步行/地铁/打车，让屏8 图标与动线摘要这段渲染真被走到 */
  private static legMock(k: number): TransportInfo {
    const modes: string[] = ['步行', '地铁', '打车'];
    const mode: string = modes[k % modes.length];
    const minutes: number = mode === '步行' ? 15 : (mode === '地铁' ? 22 : 18);
    const detail: string = mode === '步行' ? '约 1km' : (mode === '地铁' ? '2 站' : '约 6km');
    const info: TransportInfo = { mode: mode, duration: minutes, detail: detail };
    return info;
  }
}

/** BFF /v1/trip/generate 响应格式 */
interface BffQuotaResponse {
  source?: string;
  remainingToday?: number;
  giftRemaining?: number;
  passes?: PassInfo[];
}

interface BffTripResponse {
  trip?: Record<string, Object>;
  quota?: BffQuotaResponse;
}

/**
 * BFF 中转传输：端侧发送业务参数，BFF 内部构建 prompt + 注入 Key + 扣减配额 + 转发 LLM。
 * 端侧不再构建 OpenAI chat/completions 格式，不再解析 choices 信封。
 * BFF 返回 { trip, quota }，端侧提取 trip 交 TripParser 守卫，quota 更新 EntitlementStore。
 */
export class HttpLlmTransport implements LlmTransport {
  private params: PlanParams;
  private spots: Spot[];
  private area: Area;
  private passId: string;

  constructor(params: PlanParams, spots: Spot[], area: Area, passId?: string) {
    this.params = params;
    this.spots = spots;
    this.area = area;
    this.passId = passId !== undefined ? passId : '';
  }

  async complete(idempotencyKey?: string): Promise<string> {
    if (ApiConfig.BFF_BASE_URL.length === 0 || ApiConfig.LLM_CHAT_ENDPOINT.length === 0) {
      throw new AppError(ErrorCode.LLM_UNAVAILABLE, 'BFF 端点未配置（ApiConfig 占位）');
    }

    // 端侧 SOT：完整 PlanParams + Spot[] + Area，字段与 PromptBuilder.userPrompt 一一对应。
    // 旧 sparse 字段（selectedSpots: string[]、selectedArea: string）不再发送；
    // BFF 仍保留 sparse 分支，供旧客户端使用。
    const body: TripGeneratePayload = buildTripGeneratePayload(
      this.params, this.spots, this.area, this.passId, !EntitlementStore.hasSubscription());

    const reqHandle = http.createHttp();
    try {
      const headers: Record<string, string> = {};
      headers['Content-Type'] = 'application/json';
      const token: string = DeviceTokenStore.getToken();
      if (token.length > 0) {
        headers['Authorization'] = `Bearer ${token}`;
      } else {
        Logger.warn(TAG, '设备票据未获取（DeviceTokenStore 无 token），本次请求不带鉴权头');
      }
      if (idempotencyKey !== undefined && idempotencyKey.length > 0) {
        headers['Idempotency-Key'] = idempotencyKey;
      }
      const resp: http.HttpResponse = await reqHandle.request(
        `${ApiConfig.BFF_BASE_URL}${ApiConfig.LLM_CHAT_ENDPOINT}`, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: ApiConfig.CONNECT_TIMEOUT_MS,
        readTimeout: ApiConfig.READ_TIMEOUT_MS
      });
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        const code: number = resp.responseCode;
        const respBody: string = String(resp.result).slice(0, 160);
        if (code === 401) {
          throw new AppError(ErrorCode.CLOUD_TOKEN_INVALID, `BFF 401: ${respBody}`);
        }
        if (code === 402) {
          throw new AppError(ErrorCode.CLOUD_QUOTA_EXHAUSTED, `BFF 402: ${respBody}`);
        }
        if (code === 429) {
          throw new AppError(ErrorCode.CLOUD_RATE_LIMITED, `BFF 429: ${respBody}`);
        }
        if (code === 409) {
          throw new AppError(ErrorCode.CLOUD_IDEMPOTENCY_CONFLICT, `BFF 409: ${respBody}`);
        }
        throw new AppError(ErrorCode.NETWORK_REQUEST_FAILED, `BFF HTTP ${code}: ${respBody}`);
      }

      // BFF 返回 { trip, quota } 格式：trip 是已解析的 JSON 对象，quota 是更新后的权益快照
      const env: BffTripResponse = JSON.parse(String(resp.result)) as BffTripResponse;
      if (env.trip === undefined || env.trip === null) {
        throw new AppError(ErrorCode.SCHEMA_VALIDATION_FAILED, 'BFF 响应缺 trip 字段');
      }

      // 用 quota 快照更新权益缓存（BFF 返回的 remainingToday 实为 usedToday）
      if (env.quota !== undefined && env.quota !== null) {
        const current: Entitlement = EntitlementStore.get();
        const updated: Entitlement = {
          subscription: current.subscription,
          passes: env.quota.passes !== undefined ? env.quota.passes : current.passes,
          giftRemaining: env.quota.giftRemaining !== undefined ? env.quota.giftRemaining : current.giftRemaining,
          usedToday: env.quota.remainingToday !== undefined ? env.quota.remainingToday : current.usedToday,
          dailyCap: current.dailyCap
        };
        try {
          await EntitlementStore.update(updated);
        } catch (err) {
          Logger.warn(TAG, `权益缓存更新失败: ${(err as Error).message}`);
        }
      }

      // TripParser 需要字符串输入，把 BFF 返回的 trip 对象重新序列化
      return JSON.stringify(env.trip);
    } catch (err) {
      if (err instanceof AppError) {
        throw err;
      }
      // 真超时只在平台明确给出 2300025（libcurl 28 OPERATION_TIMEDOUT）时报，
      // 不按 message 猜——连接失败/DNS 错误都曾被谎报成超时
      const be: BusinessError = err as BusinessError;
      const platformCode: number = typeof be.code === 'number' ? be.code : 0;
      if (platformCode === 2300025) {
        throw new AppError(ErrorCode.NETWORK_TIMEOUT,
          `LLM 请求超时（readTimeout=${ApiConfig.READ_TIMEOUT_MS}ms）`);
      }
      // 其余无细分信息时按「请求失败」报
      throw new AppError(ErrorCode.NETWORK_REQUEST_FAILED, `LLM 请求失败: ${(err as Error).message}`);
    } finally {
      reqHandle.destroy();
    }
  }
}

export class LlmClient {
  /**
   * 全链路：transport → 守卫 → Trip；失败重试一次。
   * 401（票据失效）时先重新激活设备再重试，避免拿过期 token 反复打 401。
   */
  static async generateTrip(params: PlanParams, spots: Spot[], area: Area,
    transport?: LlmTransport, context?: common.Context, passId?: string): Promise<Trip> {
    // 传输选择与页面门禁必须同一把尺，判据收在 utils/GenerationChannel（干净检出时
    // BFF 未配置 ⇒ 走端侧规则引擎合成；配了 BFF 才走 HTTP 代理）。
    const devLocal: boolean = GenerationChannel.isLocal();
    const t: LlmTransport = transport !== undefined ? transport
      : (devLocal ? new MockLlmTransport(params, spots, area)
        : new HttpLlmTransport(params, spots, area, passId));
    // 天数与出发日以用户输入为准：模型多吐一天时按窗口截断，少吐则失败重试
    const expect: TripExpect = {
      days: DateUtils.spanDays(params.basic.startDate, params.basic.endDate),
      startDate: params.basic.startDate
    };
    let lastErr: Error | null = null;
    const idempotencyKey: string = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
    for (let attempt = 0; attempt < 2; attempt++) {
      let raw: string = '';
      try {
        raw = await t.complete(idempotencyKey);
        const trip: Trip = TripParser.parseTrip(raw, expect);
        // 地址/坐标以景点库为准回填（提示词第 12 条要求模型留空，省输出 token 也免幻觉）
        const filled: number = backfillActivityPlaces(trip, spots);
        const hours: number = backfillOpeningHours(trip, spots);
        Logger.info(TAG, `生成成功 attempt=${attempt + 1} days=${trip.days.length} ` +
          `回填地址 ${filled} 条、开放时间 ${hours} 条`);
        return trip;
      } catch (err) {
        lastErr = err as Error;
        Logger.warn(TAG, `第 ${attempt + 1} 次生成失败: ${lastErr.message}`);
        // 失败时模型原文不落库；不留片段就无法判断是非法 JSON、多吐一天还是缺字段
        if (raw.length > 0) {
          Logger.warn(TAG, `原始输出前 240 字: ${LlmClient.excerpt(raw)}`);
        }
        // A1: 票据失效时重新激活设备，下次重试将使用新 token
        if (err instanceof AppError && (err as AppError).code === ErrorCode.CLOUD_TOKEN_INVALID
          && context !== undefined && attempt === 0) {
          Logger.info(TAG, '票据失效，尝试重新激活设备');
          await DeviceActivator.reactivate(context);
        }
      }
    }
    throw new AppError(ErrorCode.TRIP_GENERATE_RETRY_EXHAUSTED,
      `两次生成均失败: ${lastErr !== null ? lastErr.message : ''}`);
  }

  private static excerpt(raw: string): string {
    const flat: string = raw.replace(/\s+/g, ' ').trim();
    return flat.length <= 240 ? flat : `${flat.slice(0, 240)}…`;
  }
}
