/**
 * 阶段 6 LLM 管线回归：Prompt 构造完整性 + 离线闭环（合成→守卫→Trip）
 * + 重试耗尽错误码（§4.1-5 失败策略）。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { LlmClient, LlmTransport } from '../../../main/ets/ai/LlmClient';
import { LlmRequest, PromptBuilder } from '../../../main/ets/ai/PromptBuilder';
import { TripSchema } from '../../../main/ets/ai/TripSchema';
import { PlanParams, SelectedSpot, TravelStyle, TransitPreference, TripBasicInput, SpotPriority, PaceOption } from '../../../main/ets/model/PlanParams';
import { Spot, SpotTag } from '../../../main/ets/model/Spot';
import { Area, AreaGroup, AreaPriceTier } from '../../../main/ets/model/Area';
import { Trip } from '../../../main/ets/model/Trip';
import { AppError } from '../../../main/ets/common/error/AppError';
import { ErrorCode } from '../../../main/ets/common/error/ErrorCode';

function makeSpots(): Spot[] {
  const s1: Spot = {
    id: 't-s1', name: '测试景点一', city: '北京', tags: [SpotTag.MUST_SEE], brief: 'b',
    suggestedDuration: 120, popularity: 90, nearbySpotIds: [], longitude: 116.4, latitude: 39.9,
    district: '东城区', nearestMetro: 'A', booking: { requiresBooking: true, bookingMethod: '官网', advanceDays: 7 }
    , provenance: { source: 'test', updatedAt: '2026-10-23' }
  };
  const s2: Spot = {
    id: 't-s2', name: '测试景点二', city: '北京', tags: [SpotTag.CLASSIC], brief: 'b',
    suggestedDuration: 90, popularity: 80, nearbySpotIds: [], longitude: 116.5, latitude: 39.95,
    district: '朝阳区', nearestMetro: 'B', booking: { requiresBooking: false }
    , provenance: { source: 'test', updatedAt: '2026-10-23' }
  };
  return [s1, s2];
}

function makeArea(): Area {
  const a: Area = {
    id: 't-a1', name: '王府井', city: '北京', longitude: 116.41, latitude: 39.92,
    description: 'd', anchorStations: ['东单'], metroLines: ['1号线'], airportMinutes: 45,
    trainStationMinutes: 12, commerceTags: [], diningDensity: '高', suitableCrowds: [],
    priceTier: AreaPriceTier.COMFORT, group: AreaGroup.CORE, source: 'test', updatedAt: '2026-10-23'
  };
  return a;
}

function makeParams(): PlanParams {
  const basic: TripBasicInput = {
    destination: '北京', startDate: '2026-07-01', endDate: '2026-07-02', people: 2, budget: 8000
  };
  const sel1: SelectedSpot = { spotId: 't-s1', priority: SpotPriority.MUST };
  const sel2: SelectedSpot = { spotId: 't-s2', priority: SpotPriority.WANT };
  const p: PlanParams = {
    basic: basic, style: TravelStyle.CULTURE, stayTier: 'comfort',
    transit: TransitPreference.PUBLIC, paces: [PaceOption.STANDARD],
    selectedSpots: [sel1, sel2], selectedArea: { areaId: 't-a1' }
  };
  return p;
}

class BrokenTransport implements LlmTransport {
  calls: number = 0;

  complete(req: LlmRequest): Promise<string> {
    this.calls += 1;
    return Promise.resolve('这不是 JSON');
  }
}

export default function llmPipelineTest(): void {
  describe('LlmPipeline', () => {
    it('prompt_contains_schema_and_spots', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const req: LlmRequest = PromptBuilder.buildRequest(makeParams(), makeSpots(), makeArea());
      expect(req.jsonSchemaStrict).assertTrue();
      expect(req.system.indexOf(TripSchema.TRIP_JSON_SCHEMA.substring(0, 40)) >= 0).assertTrue();
      expect(req.system.indexOf('以官方为准') >= 0).assertTrue();
      expect(req.user.indexOf('测试景点一') >= 0).assertTrue();
      expect(req.user.indexOf('需预约(官网 提前7天)') >= 0).assertTrue();
      expect(req.user.indexOf('[must]') >= 0).assertTrue();
    });

    it('offline_closed_loop', TestType.FUNCTION | Size.MEDIUMTEST | Level.LEVEL1, async () => {
      const trip: Trip = await LlmClient.generateTrip(makeParams(), makeSpots(), makeArea());
      expect(trip.days.length).assertEqual(2);
      expect(trip.days[0].dayIndex).assertEqual(1);
      expect(trip.days[1].dayIndex).assertEqual(2);
      const totalActs: number = trip.days[0].activities.length + trip.days[1].activities.length;
      expect(totalActs).assertEqual(2);
      expect(trip.days[0].activities[0].note !== undefined).assertTrue();
      expect(trip.overview.totalCost > 0).assertTrue();
    });

    it('offline_spreads_spots_across_days', TestType.FUNCTION | Size.MEDIUMTEST | Level.LEVEL1, async () => {
      const trip: Trip = await LlmClient.generateTrip(makeParams(), makeSpots(), makeArea());
      // 2 天 2 站要摊成 1 + 1。按 perDay 贪心装会变成第 1 天塞满、第 2 天空着，
      // 用户在屏6 看到的就是「三天两晚只有头一天有东西」
      expect(trip.days[0].activities.length).assertEqual(1);
      expect(trip.days[1].activities.length).assertEqual(1);
      expect(trip.days[1].activities[0].title).assertEqual('测试景点二');
      // 每天的首站没有通勤腿（当日第一段路无从算起）
      expect(trip.days[1].activities[0].transport === undefined).assertTrue();
    });

    it('retry_exhausted', TestType.FUNCTION | Size.MEDIUMTEST | Level.LEVEL1, async () => {
      const broken: BrokenTransport = new BrokenTransport();
      try {
        await LlmClient.generateTrip(makeParams(), makeSpots(), makeArea(), broken);
        expect('NO_THROW').assertEqual('THROW');
      } catch (err) {
        const e: AppError = err as AppError;
        expect(e.code).assertEqual(ErrorCode.TRIP_GENERATE_RETRY_EXHAUSTED);
        expect(broken.calls).assertEqual(2);
      }
    });
  });
}
