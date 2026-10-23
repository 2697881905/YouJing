/**
 * LLM 调用与生成编排（开发文档 §2.4 / §4.1-5 / §4.3）。
 *
 * 传输抽象：
 * - MockLlmTransport：离线闭环（当前默认，用户拍板）。按请求参数确定性地合成
 *   合法 Trip JSON，走完整「响应→守卫→Trip」链路，等价验证真实管线；
 * - HttpLlmTransport：直连备选。端点取 ApiConfig 单点；Key 走 HUKS（阶段 9 前
 *   端点为空即抛 LLM_UNAVAILABLE，禁止硬编码）。小艺 Skill 通道在阶段 9 接入。
 *
 * 失败策略（§4.1-5）：解析失败重试一次，再失败抛 TRIP_GENERATE_RETRY_EXHAUSTED，
 * 由调用方进屏7降级。
 */

import { http } from '@kit.NetworkKit';
import { buffer } from '@kit.ArkTS';
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

  private synthesize(): string {
    const b: TripBasicInput = this.params.basic;
    const dayCount: number = Math.max(1, this.daysBetween(b.startDate, b.endDate) + 1);
    const perDay: number = this.params.paces.indexOf(PaceOption.RELAXED) >= 0 ? 3 :
      (this.params.paces.indexOf(PaceOption.PACKED) >= 0 ? 6 : 4);
    const chosen: SelectedSpot[] = this.params.selectedSpots;
    const days: TripDay[] = [];
    let cursor: number = 0;
    let total: number = 0;
    for (let d = 0; d < dayCount; d++) {
      const acts: Activity[] = [];
      let slot: number = 9 * 60;
      for (let k = 0; k < perDay && cursor < chosen.length; k++) {
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

/** 直连备选传输：端点/Key 未就绪即抛 LLM_UNAVAILABLE（禁止硬编码，配置单点） */
export class HttpLlmTransport implements LlmTransport {
  async complete(req: LlmRequest): Promise<string> {
    if (ApiConfig.BASE_URL.length === 0 || ApiConfig.LLM_CHAT_ENDPOINT.length === 0) {
      throw new AppError(ErrorCode.LLM_UNAVAILABLE, 'LLM 端点未配置（ApiConfig 占位）');
    }
    const body: Record<string, Object> = {};
    body['messages'] = [
      { 'role': 'system', 'content': req.system } as Record<string, string>,
      { 'role': 'user', 'content': req.user } as Record<string, string>
    ] as Object;
    body['response_format'] = req.jsonSchemaStrict
      ? { 'type': 'json_schema' } as Record<string, string> as Object
      : { 'type': 'json_object' } as Record<string, string> as Object;
    const reqHandle = http.createHttp();
    try {
      const resp: http.HttpResponse = await reqHandle.request(
        `${ApiConfig.BASE_URL}${ApiConfig.LLM_CHAT_ENDPOINT}`, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json' } as Record<string, string>,
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.STRING
      });
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        throw new AppError(ErrorCode.NETWORK_REQUEST_FAILED, `LLM HTTP ${resp.responseCode}`);
      }
      return resp.result as string;
    } catch (err) {
      if (err instanceof AppError) {
        throw err;
      }
      throw new AppError(ErrorCode.NETWORK_TIMEOUT, `LLM 请求失败: ${(err as Error).message}`);
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

  /** 校验枚举白名单与 Schema 同源（测试辅助） */
  static schemaStatuses(): string[] {
    return TripSchema.ACTIVITY_STATUS;
  }
}
