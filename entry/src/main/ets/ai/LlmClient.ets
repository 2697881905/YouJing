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
import { Transit, TransitEstimate } from '../utils/Transit';
import { GeoPoint } from '../utils/Geo';
import { DateUtils } from '../utils/DateUtils';
import { ApiConfig } from '../common/config/ApiConfig';
import { isMapCity } from '../common/constants/Cities';
import { GenerationChannel } from '../utils/GenerationChannel';
import { DeviceTokenStore } from '../data/DeviceTokenStore';
import { DeviceActivator } from '../data/DeviceActivator';
import { EntitlementStore, Entitlement, PassInfo, SubscriptionInfo, QuotaSnapshot, mergeQuotaSnapshot } from '../data/EntitlementStore';
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
    // 地图来源的城市（西安/成都这类非内置库）**从没取过预约信息**：
    // 不能因为 `requiresBooking=false` 就说「无需预约」——那是没查过，不是查过了不需要。
    // 提示词规则 15 早已对真模型这么要求，本地合成这里是唯一的漏网。
    const mapCity: boolean = isMapCity(b.destination);
    const dayCount: number = Math.max(1, this.daysBetween(b.startDate, b.endDate) + 1);
    const caps: number[] = this.dayCaps(dayCount);
    const chosen: SelectedSpot[] = this.params.selectedSpots;
    const days: TripDay[] = [];
    let cursor: number = 0;
    let total: number = 0;
    for (let d = 0; d < dayCount; d++) {
      const perDay: number = caps[d];
      // 每天的名额按「剩余量摊到剩余天」算，而不是一律吃满当日上限：
      // 2 个景点排 3 天时若按 perDay 贪心装，第 1 天就全塞完、后两天空着（真机拍到过），
      // 用户看到的就是「三天两晚只有头一天有东西」。上限仍是当日档，不放松节奏。
      const left: number = chosen.length - cursor;
      const quota: number = Math.max(1, Math.min(perDay, Math.ceil(left / (dayCount - d))));
      const acts: Activity[] = [];
      let slot: number = 9 * 60;
      // 上一站的坐标：通勤段按真实直线距离估算（与预选同一套口径），不再写死 22 分钟 2 站
      let prevPoint: GeoPoint | null = null;
      for (let k = 0; k < quota && cursor < chosen.length; k++) {
        if (slot > 20 * 60) {
          // 太晚就不硬塞：跨午夜会让 endTime 回卷成比 time 早，剩余站点顺延到次日
          break;
        }
        const sel: SelectedSpot = chosen[cursor];
        cursor += 1;
        const spot: Spot | undefined = this.spots.find((s: Spot): boolean => s.id === sel.spotId);
        if (spot === undefined) {
          continue;
        }
        const end: number = slot + spot.suggestedDuration;
        const act: Activity = {
          id: `d${d + 1}-a${k + 1}`,
          time: MockLlmTransport.hhmm(slot),
          endTime: MockLlmTransport.hhmm(end),
          title: spot.name,
          location: `${spot.city} ${spot.district}`,
          address: `${spot.city} ${spot.district}`,
          longitude: spot.longitude,
          latitude: spot.latitude,
          status: spot.booking.requiresBooking ? ActivityStatus.NOT_BOOKED : ActivityStatus.NO_NEED,
          category: ActivityCategory.SIGHT,
          note: spot.booking.requiresBooking
            ? `预约：${spot.booking.bookingMethod ?? '官方渠道'}（以官方为准）`
            : (mapCity ? '预约信息未获取，以官方为准' : undefined),
          reason: k === 0 ? '当日首站安排在最开阔时段，动线由近及远。' : undefined,
          transport: k === 0 ? undefined : MockLlmTransport.legTo(prevPoint, spot)
        };
        acts.push(act);
        prevPoint = Transit.pointOf(spot.latitude, spot.longitude);
        slot = end + 15;
      }
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

  /** 离线合成的通勤段：按真实直线距离估（与预选/收口同一套 Transit 口径）。
   *  原来这里是「步行/地铁/打车」三个写死的 15/22/18 分钟，中关村→八达岭 60km
   *  与故宫→景山 1km 报同一句「地铁 22 分钟 · 2 站」，属于凭空编造。 */
  private static legTo(from: GeoPoint | null, to: Spot): TransportInfo {
    const target: GeoPoint | null = Transit.pointOf(to.latitude, to.longitude);
    const est: TransitEstimate = Transit.of(from, target);
    const info: TransportInfo = { mode: est.mode, duration: est.minutes, detail: est.detail };
    return info;
  }
}

/** BFF /v1/trip/generate 响应格式 */
interface BffQuotaResponse extends QuotaSnapshot {
  source?: string;
  subscription?: SubscriptionInfo | null;
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
      this.params, this.spots, this.area, this.passId);

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
        // 5xx 是**服务端/上游**出问题，不是用户网络：BFF 对上游 4xx、模型输出校验失败、
        // JSON 解析失败都回 502。此前一律报 NETWORK_REQUEST_FAILED，屏7 会说「网络不通或超时」，
        // 用户会去切 WiFi 而真正该做的是等一会儿重试或改用本机生成。
        if (code >= 500) {
          throw new AppError(ErrorCode.LLM_UNAVAILABLE, `BFF ${code}: ${respBody}`);
        }
        throw new AppError(ErrorCode.NETWORK_REQUEST_FAILED, `BFF HTTP ${code}: ${respBody}`);
      }

      // BFF 返回 { trip, quota } 格式：trip 是已解析的 JSON 对象，quota 是更新后的权益快照
      const env: BffTripResponse = JSON.parse(String(resp.result)) as BffTripResponse;
      if (env.trip === undefined || env.trip === null) {
        throw new AppError(ErrorCode.SCHEMA_VALIDATION_FAILED, 'BFF 响应缺 trip 字段');
      }

      // 用 quota 快照更新权益缓存（BFF 返回的 remainingToday 实为 usedToday）。
      // subscription 以服务端为准：到期/退款后服务端回 null，端上必须跟着清掉（D9）。
      if (env.quota !== undefined && env.quota !== null) {
        const current: Entitlement = EntitlementStore.get();
        const updated: Entitlement = mergeQuotaSnapshot(current, env.quota);
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
        // 行程主键由端侧重新生成：模型给的 id 不保证唯一，而 `TripDao.saveTrip` 是
        // 「按 id 先删后插」——两次生成撞上同一个 id 会把前一条行程连同它的天/活动整片删掉。
        // 2026-11-03 端到端联调时模型返回固定 id `trip-test`，这个碰撞面当场就露出来了。
        // 解析器本身不改（它对外部输入保持忠实），只在落库前的这一个漏斗收口。
        trip.id = `trip-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
        // 用户输入优先于模型自述：人数/预算/目的地/风格是用户在屏2/屏3 选的，模型只负责排行程。
        // 费用页的预算总额 = trip.budget × trip.people，模型把「2 人 / 8000」echo 成「4 人 / 5000」
        // 会让预算直接错一倍；ICS 分享也会带错人数。日期已在 TripParser.normalizeDays 收口，
        // 这里补齐同一类字段（2026-11-03 读码发现，此前只有 id 与日期做了归一）。
        trip.people = params.basic.people;
        trip.budget = params.basic.budget;
        trip.destination = params.basic.destination;
        trip.style = params.style;
        // 规则 18 的结构性兜底：模型偶发仍把午/晚餐写成 food 活动（2026-11-03 MapKit 变体实测
        // 出现「书院门附近午餐」），屏8 的当日序列是活动 ∪ 餐次，会出现两行同一顿饭。
        // meals 已被校验器要求午/晚各一条，所以「标题以餐次词结尾」的 food 活动一定是重复行；
        // 只砍这一种形态，真正的游览餐饮（回民街小吃巡游、晚餐后逛夜市）不动。
        const mealTitle = /(早餐|午餐|晚餐|早饭|午饭|晚饭)$/;
        let dropped: number = 0;
        for (const day of trip.days) {
          const kept: Activity[] = day.activities.filter((a: Activity): boolean => {
            const isDup: boolean = a.category === ActivityCategory.FOOD && mealTitle.test(a.title.trim());
            if (isDup) {
              dropped += 1;
            }
            return !isDup;
          });
          day.activities = kept;
        }
        if (dropped > 0) {
          Logger.info(TAG, `剔除与餐次重复的 food 活动 ${dropped} 条`);
        }
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
    // 「两次都没成」这个包装会把真实原因埋掉：服务端 5xx / 网络不通 / 限流 各自都有
    // 更可操作的文案（屏7 的 FailureCopy），而「试了两次都没排通」只告诉用户"没成"。
    // 所以这类**外部原因**在重试耗尽后原样上抛；只有"模型给的行程不合格"这类
    // 内容问题才归到 RETRY_EXHAUSTED（用户能做的事确实只是再试一次）。
    if (lastErr instanceof AppError) {
      const c: number = (lastErr as AppError).code;
      if (c === ErrorCode.LLM_UNAVAILABLE || c === ErrorCode.NETWORK_REQUEST_FAILED ||
        c === ErrorCode.NETWORK_TIMEOUT || c === ErrorCode.CLOUD_RATE_LIMITED) {
        throw lastErr;
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
