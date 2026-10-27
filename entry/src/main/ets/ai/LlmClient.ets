/**
 * LLM 调用与生成编排（开发文档 §2.4 / §4.1-5 / §4.3）。
 *
 * 传输抽象：
 * - MockLlmTransport：离线闭环（当前默认，用户拍板）。按请求参数确定性地合成
 *   合法 Trip JSON，走完整「响应→守卫→Trip」链路，等价验证真实管线；
 * - HttpLlmTransport：直连备选。端点与超时取 ApiConfig 单点；Key 开发期走 ApiConfig
 *   （skip-worktree 防误提交，禁止硬编码进逻辑），上架前迁系统凭据存储。小艺 Skill 通道在阶段 9 接入。
 *
 * 失败策略（§4.1-5）：解析失败重试一次，再失败抛 TRIP_GENERATE_RETRY_EXHAUSTED，
 * 由调用方进屏7降级。
 */

import { http } from '@kit.NetworkKit';
import { buffer } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { LlmRequest, PromptBuilder } from './PromptBuilder';
import { TripParser } from './TripParser';
import { TripSchema } from './TripSchema';
import { Trip, TripDay, Activity, Meal, MealType, ActivityCategory, ActivityStatus, IntensityLevel, TransportInfo } from '../model/Trip';
import { PlanParams, SelectedSpot, TripBasicInput, PaceOption } from '../model/PlanParams';
import { Spot } from '../model/Spot';
import { Area } from '../model/Area';
import { ApiConfig } from '../common/config/ApiConfig';
import { MockConfig } from '../common/config/MockConfig';
import { Logger } from '../common/logger/Logger';
import { AppError } from '../common/error/AppError';
import { ErrorCode } from '../common/error/ErrorCode';

const TAG: string = 'Ai.LlmClient';

export interface LlmTransport {
  complete(req: LlmRequest): Promise<string>;
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

  complete(req: LlmRequest): Promise<string> {
    Logger.info(TAG, `MockTransport system=${req.system.length}B user=${req.user.length}B`);
    return Promise.resolve(this.synthesize());
  }

  private static capOf(pace: PaceOption): number {
    if (pace === PaceOption.RELAXED) {
      return 3;
    }
    return pace === PaceOption.PACKED ? 6 : 4;
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
      caps.push(MockLlmTransport.capOf(list[seg]));
    }
    return caps;
  }

  private synthesize(): string {
    const b: TripBasicInput = this.params.basic;
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
          note: spot.booking.requiresBooking ? `预约：${spot.booking.bookingMethod ?? '官方渠道'}（以官方为准）` : undefined,
          reason: k === 0 ? '当日首站安排在最开阔时段，动线由近及远。' : undefined,
          transport: k === 0 ? undefined : MockLlmTransport.legMock(k)
        };
        acts.push(act);
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

/**
 * 直连备选传输：端点未就绪即抛 LLM_UNAVAILABLE（禁止硬编码，配置单点）。
 * 鉴权与超时同走 ApiConfig：Key 为空时请求不带 Authorization 头（只告警），
 * 超时参数显式下发，真超时报 NETWORK_TIMEOUT、其余报 NETWORK_REQUEST_FAILED。
 */
/** OpenAI 兼容 chat/completions 响应信封（只声明本端点用得到的字段） */
interface ChatError {
  message?: string;
}

interface ChatMessage {
  role?: string;
  content?: string;
}

interface ChatChoice {
  index?: number;
  message?: ChatMessage;
  finish_reason?: string;
}

interface ChatUsage {
  prompt_tokens?: number;
  completion_tokens?: number;
  prompt_cache_hit_tokens?: number;
}

interface ChatCompletion {
  id?: string;
  model?: string;
  choices?: ChatChoice[];
  error?: ChatError;
  usage?: ChatUsage;
}

export class HttpLlmTransport implements LlmTransport {
  async complete(req: LlmRequest): Promise<string> {
    if (ApiConfig.BASE_URL.length === 0 || ApiConfig.LLM_CHAT_ENDPOINT.length === 0) {
      throw new AppError(ErrorCode.LLM_UNAVAILABLE, 'LLM 端点未配置（ApiConfig 占位）');
    }
    const body: Record<string, Object> = {};
    // 消息字面量带具名 Record 标注（工程纪律：对象字面量必须对应具名类型）
    const messages: Object[] = [
      { 'role': 'system', 'content': req.system } as Record<string, string>,
      { 'role': 'user', 'content': req.user } as Record<string, string>
    ];
    body['messages'] = messages;
    // OpenAI 兼容端点缺 model 会直接 400（2026-10-27 直连实测）；本地网关不需要时留空不发
    if (ApiConfig.LLM_MODEL.length > 0) {
      body['model'] = ApiConfig.LLM_MODEL;
    }
    // §4.3 第二层防线：response_format 强制模型遵循 Schema（strict），
    // schema 本体与第一层 Prompt 内嵌、第三层 TripParser 守卫同源（TripSchema.TRIP_JSON_SCHEMA）
    // 端点不支持 strict Schema 时降级为 json_object：第二层防线让位给第一、三层，
    // 而不是每次都吃 400（DeepSeek 实测 json_schema 不可用）
    if (req.jsonSchemaStrict && ApiConfig.SUPPORTS_JSON_SCHEMA) {
      const jsonSchema: Record<string, Object> = {};
      jsonSchema['name'] = 'Trip';
      jsonSchema['schema'] = JSON.parse(TripSchema.TRIP_JSON_SCHEMA);
      jsonSchema['strict'] = true;
      const responseFormat: Record<string, Object> = {};
      responseFormat['type'] = 'json_schema';
      responseFormat['json_schema'] = jsonSchema;
      body['response_format'] = responseFormat;
    } else {
      const responseFormat: Record<string, Object> = {};
      responseFormat['type'] = 'json_object';
      body['response_format'] = responseFormat;
    }
    const reqHandle = http.createHttp();
    try {
      // 鉴权注入点：Key 走 ApiConfig 单点（上架前迁系统凭据存储，见接入方案 §三-2）。
      // Key 为空只告警不阻断——留出免鉴权本地网关的调试通路，误配会以 HTTP 401 露出。
      const headers: Record<string, string> = {};
      headers['Content-Type'] = 'application/json';
      if (ApiConfig.API_KEY.length > 0) {
        headers['Authorization'] = `Bearer ${ApiConfig.API_KEY}`;
      } else {
        Logger.warn(TAG, 'LLM Key 未配置（ApiConfig.API_KEY 为空），本次请求不带鉴权头');
      }
      const resp: http.HttpResponse = await reqHandle.request(
        `${ApiConfig.BASE_URL}${ApiConfig.LLM_CHAT_ENDPOINT}`, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: ApiConfig.CONNECT_TIMEOUT_MS,
        readTimeout: ApiConfig.READ_TIMEOUT_MS
      });
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        throw new AppError(ErrorCode.NETWORK_REQUEST_FAILED,
          `LLM HTTP ${resp.responseCode}: ${String(resp.result).slice(0, 160)}`);
      }
      // 返回的是 **chat/completions 信封**，模型文本在 choices[0].message.content 里。
      // 此前这里直接把整个 resp.result 交出去，TripParser 拿到的顶层键是
      // id/model/choices/usage → 必然报「days: 期望 array」，真机两次实测都是这个形状。
      const env: ChatCompletion = JSON.parse(String(resp.result)) as ChatCompletion;
      const choices: ChatChoice[] | undefined = env.choices;
      if (choices === undefined || choices.length === 0) {
        const errEnv: ChatError | undefined = env.error;
        const msg: string = errEnv !== undefined && errEnv.message !== undefined ? errEnv.message : '';
        throw new AppError(ErrorCode.SCHEMA_VALIDATION_FAILED,
          msg.length > 0 ? `LLM 返回错误: ${msg}` : 'LLM 响应里没有 choices');
      }
      // 用量必须落日志：按 token 计费的通道，端上不记用量就没法回答「这次花了多少钱」，
      // 也没法定位「贵在哪一段」（缓存命中数直接决定输入侧单价）
      const u: ChatUsage | undefined = env.usage;
      if (u !== undefined) {
        Logger.info(TAG, `LLM 用量 model=${env.model === undefined ? '?' : env.model} ` +
          `in=${u.prompt_tokens === undefined ? 0 : u.prompt_tokens} ` +
          `(cache 命中 ${u.prompt_cache_hit_tokens === undefined ? 0 : u.prompt_cache_hit_tokens}) ` +
          `out=${u.completion_tokens === undefined ? 0 : u.completion_tokens}`);
      }
      const message: ChatMessage | undefined = choices[0].message;
      const content: string | undefined = message === undefined ? undefined : message.content;
      if (content === undefined || content.length === 0) {
        throw new AppError(ErrorCode.SCHEMA_VALIDATION_FAILED, 'LLM 响应缺 choices[0].message.content');
      }
      return content;
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
  /** 全链路：Prompt → transport → 守卫 → Trip；失败重试一次 */
  static async generateTrip(params: PlanParams, spots: Spot[], area: Area,
    transport?: LlmTransport): Promise<Trip> {
    const t: LlmTransport = transport !== undefined ? transport
      : (MockConfig.USE_MOCK_DATA ? new MockLlmTransport(params, spots, area) : new HttpLlmTransport());
    const req: LlmRequest = PromptBuilder.buildRequest(params, spots, area);
    let lastErr: Error | null = null;
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        const raw: string = await t.complete(req);
        const trip: Trip = TripParser.parseTrip(raw);
        Logger.info(TAG, `生成成功 attempt=${attempt + 1} days=${trip.days.length}`);
        return trip;
      } catch (err) {
        lastErr = err as Error;
        Logger.warn(TAG, `第 ${attempt + 1} 次生成失败: ${lastErr.message}`);
      }
    }
    throw new AppError(ErrorCode.TRIP_GENERATE_RETRY_EXHAUSTED,
      `两次生成均失败: ${lastErr !== null ? lastErr.message : ''}`);
  }
}
