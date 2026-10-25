/**
 * Prompt 构造（开发文档 §3.3 第三层 / §4.3 第一层防线）。
 * 系统指令内嵌完整 JSON Schema（与 TripParser/TripSchema 同源常量），
 * 用户消息带 SelectedSpot 完整信息 + 区域通勤 + 基础参数。
 */

import { TripSchema } from './TripSchema';
import { PlanParams, SelectedSpot } from '../model/PlanParams';
import { Spot } from '../model/Spot';
import { Area } from '../model/Area';

export interface LlmRequest {
  system: string;
  user: string;
  /** response_format: { type:'json_schema', strict:true }（§4.3 第二层防线） */
  jsonSchemaStrict: boolean;
}

export class PromptBuilder {
  static buildRequest(params: PlanParams, spots: Spot[], area: Area): LlmRequest {
    const req: LlmRequest = {
      system: PromptBuilder.systemPrompt(),
      user: PromptBuilder.userPrompt(params, spots, area),
      jsonSchemaStrict: true
    };
    return req;
  }

  static systemPrompt(): string {
    const days: string[] = [];
    days.push('你是旅行行程规划引擎。只输出一个符合给定 JSON Schema 的 JSON 对象，禁止输出任何其他文字、注释或代码围栏。');
    days.push('规则：');
    days.push('1. days 数组长度必须等于用户给定的天数，dayIndex 从 1 连续递增；date 按 startDate 逐日 +1。');
    days.push('2. 每个活动 time/endTime 为 HH:mm；相邻活动间如有通勤，写入后一活动的 transport（mode/duration分钟/detail）。');
    days.push('3. status 只能取 booked|not_booked|full|pending|no_need；category 只能取 transport|sight|food|shop|rest|hotel|other。');
    days.push('4. 必须覆盖用户标记为 must 的全部景点；want 尽量覆盖；optional 视时间取舍。餐饮每天至少午餐、晚餐各一条（meals）。');
    days.push('5. 景点的预约信息（booking）必须体现在对应活动的 note 或 reason 中，并注明「以官方为准」。');
    days.push('6. reason 字段：为节奏紧张或清晨/夜间安排给出一句中文理由。');
    days.push('7. 金额一律整数人民币元；overview.totalCost 约等于各天 dailyCost 之和。');
    days.push('8. 每餐 meals[].time 给 HH:mm 用餐时刻（早餐 07:00–09:00、午餐 11:30–13:30、晚餐 17:30–20:30 之间取整），屏15 会把餐次与节点按时间并排。');
    days.push('9. 活动的 location 填「到访点位/入口别称」（如「山脚入口」「北门」「正殿前」），不得与 title 或 address 重复；没有明确入口信息时留空串。');
    days.push('JSON Schema:');
    days.push(TripSchema.TRIP_JSON_SCHEMA);
    return days.join('\n');
  }

  static userPrompt(params: PlanParams, spots: Spot[], area: Area): string {
    const lines: string[] = [];
    const b = params.basic;
    lines.push(`目的地：${b.destination}；日期：${b.startDate} 至 ${b.endDate}；人数：${b.people}；预算：${b.budget} 元/人。`);
    lines.push(`风格：${params.style}；住宿档位：${params.stayTier}；交通偏好：${params.transit}；节奏：${params.paces.join('/') || 'standard'}。`);
    lines.push(`住宿区域：${area.name}（价格档位 ${area.priceTier}，` +
      `${area.metroLines.join('/')}，锚定站 ${area.anchorStations.join('/')}，` +
      `到机场 ${area.airportMinutes} 分钟、火车站 ${area.trainStationMinutes} 分钟）。`);
    lines.push('已选景点（含完整规划信息）：');
    for (const sel of params.selectedSpots) {
      const spot: Spot | undefined = spots.find((s: Spot): boolean => s.id === sel.spotId);
      if (spot === undefined) {
        continue;
      }
      const bk: string = spot.booking.requiresBooking
        ? `需预约(${spot.booking.bookingMethod ?? '官方渠道'}${spot.booking.advanceDays !== undefined ? ` 提前${spot.booking.advanceDays}天` : ''}${spot.booking.closedDay !== undefined ? ` 闭馆:${spot.booking.closedDay}` : ''})`
        : '无需预约';
      lines.push(`- [${sel.priority}] ${spot.name}｜${spot.district}｜建议${spot.suggestedDuration}分钟｜` +
        `坐标(${spot.longitude.toFixed(4)},${spot.latitude.toFixed(4)})｜${bk}｜周边:${spot.nearbySpotIds.join(',') || '无'}` +
        `${sel.userNote !== undefined ? `｜用户备注:${sel.userNote}` : ''}`);
    }
    return lines.join('\n');
  }
}
