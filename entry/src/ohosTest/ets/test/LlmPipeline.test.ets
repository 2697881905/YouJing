/**
 * 阶段 6 LLM 管线回归：Prompt 构造完整性 + 离线闭环（合成→守卫→Trip）
 * + 重试耗尽错误码（§4.1-5 失败策略）。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { LlmClient, LlmTransport, MockLlmTransport } from '../../../main/ets/ai/LlmClient';
import { LlmRequest, PromptBuilder } from '../../../main/ets/ai/PromptBuilder';
import { TripSchema } from '../../../main/ets/ai/TripSchema';
import { PlanParams, SelectedSpot, TravelStyle, TransitPreference, TripBasicInput, SpotPriority, PaceOption } from '../../../main/ets/model/PlanParams';
import { Spot, SpotTag } from '../../../main/ets/model/Spot';
import { Area, AreaGroup, AreaPriceTier } from '../../../main/ets/model/Area';
import { Trip, IntensityLevel, Activity } from '../../../main/ets/model/Trip';
import { DayLoad, DayLoadCalc } from '../../../main/ets/utils/DayLoad';
import { PlanAutoPick } from '../../../main/ets/utils/PlanAutoPick';
import { IcsBuilder } from '../../../main/ets/utils/IcsBuilder';
import { MockTrip } from '../../../main/ets/mock/MockTrip';
import { AppError } from '../../../main/ets/common/error/AppError';
import { ErrorCode } from '../../../main/ets/common/error/ErrorCode';

type Obj = Record<string, Object>;

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

function makeOneDayParams(): PlanParams {
  const basic: TripBasicInput = {
    destination: '西安', startDate: '2026-10-31', endDate: '2026-10-31', people: 2, budget: 2000
  };
  const sel: SelectedSpot = { spotId: 't-s1', priority: SpotPriority.MUST };
  const p: PlanParams = {
    basic: basic, style: TravelStyle.CULTURE, stayTier: 'comfort',
    transit: TransitPreference.PUBLIC, paces: [PaceOption.STANDARD],
    selectedSpots: [sel], selectedArea: { areaId: 't-a1' }
  };
  return p;
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

function makeManySpots(n: number): Spot[] {
  const out: Spot[] = [];
  for (let i = 1; i <= n; i++) {
    const s: Spot = {
      id: `t-m${i}`, name: `景点${i}`, city: '北京', tags: [SpotTag.MUST_SEE], brief: 'b',
      suggestedDuration: 60, popularity: 70, nearbySpotIds: [], longitude: 116.4 + i * 0.01,
      latitude: 39.9, district: '东城区', nearestMetro: 'A', booking: { requiresBooking: false },
      provenance: { source: 'test', updatedAt: '2026-10-23' }
    };
    out.push(s);
  }
  return out;
}

function makePaceParams(paces: PaceOption[], stopCount: number): PlanParams {
  const basic: TripBasicInput = {
    destination: '北京', startDate: '2026-07-01', endDate: '2026-07-03', people: 2, budget: 8000
  };
  const sels: SelectedSpot[] = [];
  for (let i = 1; i <= stopCount; i++) {
    const s: SelectedSpot = { spotId: `t-m${i}`, priority: SpotPriority.MUST };
    sels.push(s);
  }
  const p: PlanParams = {
    basic: basic, style: TravelStyle.CULTURE, stayTier: 'comfort',
    transit: TransitPreference.PUBLIC, paces: paces,
    selectedSpots: sels, selectedArea: { areaId: 't-a1' }
  };
  return p;
}

/**
 * 种子库量级的停留（故宫 4h、八达岭 5h、颐和园 4h）。
 * 其余 fixture 一律 60/90/120 分钟——正是这个量级差让「排不下」类缺陷在测试里长期不可见。
 */
function makeLongSpots(n: number): Spot[] {
  const dwell: number[] = [240, 300, 180];
  const out: Spot[] = [];
  for (let i = 0; i < n; i++) {
    const s: Spot = {
      id: `t-l${i + 1}`, name: `大景点${i + 1}`, city: '北京', tags: [SpotTag.MUST_SEE], brief: 'b',
      suggestedDuration: dwell[i % dwell.length], popularity: 90 - i, nearbySpotIds: [],
      longitude: 116.4 + i * 0.02, latitude: 39.9, district: '东城区', nearestMetro: 'A',
      booking: { requiresBooking: false },
      provenance: { source: 'test', updatedAt: '2026-11-03' }
    };
    out.push(s);
  }
  return out;
}

/** 按给定景点 id 与天数造参数（STANDARD 节奏 = 每天上限 4）；destination 用于区分种子城与地图城 */
function makeParamsFor(spotIds: string[], days: number, destination: string = '北京'): PlanParams {
  const basic: TripBasicInput = {
    destination: destination, startDate: '2026-07-01',
    endDate: days <= 1 ? '2026-07-01' : (days === 2 ? '2026-07-02' : '2026-07-03'),
    people: 2, budget: 8000
  };
  const sels: SelectedSpot[] = [];
  for (const id of spotIds) {
    sels.push({ spotId: id, priority: SpotPriority.MUST });
  }
  const p: PlanParams = {
    basic: basic, style: TravelStyle.CULTURE, stayTier: 'comfort',
    transit: TransitPreference.PUBLIC, paces: [PaceOption.STANDARD],
    selectedSpots: sels, selectedArea: { areaId: 't-a1' }
  };
  return p;
}

class BrokenTransport implements LlmTransport {
  calls: number = 0;

  complete(idempotencyKey?: string): Promise<string> {
    this.calls += 1;
    return Promise.resolve('这不是 JSON');
  }
}

/** 1 天请求却被模型拆成两天、dayIndex 重复——2026-10-31 真机失败形态 */
class TwoDaysForOneDayTransport implements LlmTransport {
  complete(idempotencyKey?: string): Promise<string> {
    const o: Obj = JSON.parse(JSON.stringify(MockTrip.TRIP)) as Obj;
    o['startDate'] = '2026-10-31';
    o['endDate'] = '2026-10-31';
    const days: Object[] = o['days'] as Object[];
    (days[1] as Obj)['dayIndex'] = 1;
    (days[1] as Obj)['date'] = '2026-10-31';
    return Promise.resolve(JSON.stringify(o));
  }
}

/**
 * 离线闭环必须**显式**用 mock 传输，不能跟全局 `USE_MOCK_DATA` 走。
 * 2026-10-27 直连真模型后该开关翻成 false，这三条用例就去打真 DeepSeek 了：
 * 既超 hypium 5s 用例时限（报 Error: execute timeout），又花用户的钱——测试不该有账单。
 */
async function genOffline(params: PlanParams, spots: Spot[]): Promise<Trip> {
  return LlmClient.generateTrip(params, spots, makeArea(), new MockLlmTransport(params, spots, makeArea()));
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
      const trip: Trip = await genOffline(makeParams(), makeSpots());
      expect(trip.days.length).assertEqual(2);
      expect(trip.days[0].dayIndex).assertEqual(1);
      expect(trip.days[1].dayIndex).assertEqual(2);
      const totalActs: number = trip.days[0].activities.length + trip.days[1].activities.length;
      expect(totalActs).assertEqual(2);
      expect(trip.days[0].activities[0].note !== undefined).assertTrue();
      expect(trip.overview.totalCost > 0).assertTrue();
    });

    it('offline_spreads_spots_across_days', TestType.FUNCTION | Size.MEDIUMTEST | Level.LEVEL1, async () => {
      const trip: Trip = await genOffline(makeParams(), makeSpots());
      // 2 天 2 站要摊成 1 + 1。按 perDay 贪心装会变成第 1 天塞满、第 2 天空着，
      // 用户在屏6 看到的就是「三天两晚只有头一天有东西」
      expect(trip.days[0].activities.length).assertEqual(1);
      expect(trip.days[1].activities.length).assertEqual(1);
      expect(trip.days[1].activities[0].title).assertEqual('测试景点二');
      // 每天的首站没有通勤腿（当日第一段路无从算起）
      expect(trip.days[1].activities[0].transport === undefined).assertTrue();
    });

    /**
     * 两个相反方向的要求，必须成对钉住：
     * A. **用户亲手选的站一个都不能丢**（可以超窗，由屏8 的负载条与「去减一站」如实呈现）；
     * B. **自动预选的站必须装得下**（预选数量不能是空头支票）。
     *
     * 背景：种子库停留是 4h/5h（故宫 4h、八达岭 5h），而旧 fixture 全是 60/90/120 分钟，
     * 所以「生成器只挡开始时刻、不挡当日总时长」在测试里从来触发不了；
     * 2026-11-03 真机屏8 实拍到「今日 13.7h · 超建议 3.7h」。
     * 第一版只喂 6 站时 quota 摊成 2/天、负载 540min 刚好不超 ⇒ 用例绿了却什么都没证。
     */
    it('offline_places_every_selected_spot', TestType.FUNCTION | Size.MEDIUMTEST | Level.LEVEL1, async () => {
      const spots: Spot[] = makeLongSpots(12);
      const ids: string[] = [];
      for (const s of spots) {
        ids.push(s.id);
      }
      const trip: Trip = await genOffline(makeParamsFor(ids, 3), spots);
      let total: number = 0;
      let rollover: string = '';
      for (const d of trip.days) {
        total += d.activities.length;
        for (const a of d.activities) {
          if (a.endTime <= a.time) {
            rollover += `D${d.dayIndex} ${a.time}-${a.endTime} `;
          }
        }
      }
      // 12 站排 3 天**物理上放不下**：9:00 起排 + 20:00 后不再起新站，240/300/180 分钟
      // 的组合每天只装得下 3 站 ⇒ 实排 9。生成器不许为凑数把时间排穿（时间回卷更糟），
      // 少掉的 3 站由 GeneratingPage 用 toast 如实告诉用户——**不许静默丢失**。
      expect(total).assertEqual(9);
      expect(rollover).assertEqual('');
    });

    it('offline_preselected_plan_fits_window', TestType.FUNCTION | Size.MEDIUMTEST | Level.LEVEL1, async () => {
      const spots: Spot[] = makeLongSpots(12);
      const picked: SelectedSpot[] = PlanAutoPick.pickSpotsForDays(
        spots, 3, PaceOption.STANDARD, [], makeArea());
      // 12 个 4~5 小时的站 3 天装不下 ⇒ 预选阶段就要收口，屏2 才不会写「预选 12 个」
      expect(picked.length < 12).assertTrue();
      expect(picked.length > 0).assertTrue();
      const ids: string[] = [];
      for (const p of picked) {
        ids.push(p.spotId);
      }
      const trip: Trip = await genOffline(makeParamsFor(ids, 3), spots);
      let over: string = '';
      let placed: number = 0;
      for (const d of trip.days) {
        placed += d.activities.length;
        const load: DayLoad = DayLoadCalc.of(d);
        if (load.minutes > load.windowMinutes) {
          over += `D${d.dayIndex}=${load.minutes}>${load.windowMinutes} `;
        }
      }
      expect(over).assertEqual('');
      // 预选了几个就要排进去几个——这正是 B 条要保证的
      expect(placed).assertEqual(picked.length);
    });

    it('map_city_never_claims_no_booking_needed', TestType.FUNCTION | Size.MEDIUMTEST | Level.LEVEL1, async () => {
      const spots: Spot[] = makeLongSpots(2);
      const ids: string[] = ['t-l1', 't-l2'];
      // 西安不在内置种子库里 ⇒ 走地图服务取数，预约字段**从没取到**。
      // `requiresBooking=false` 在那种情况下只表示"没查过"，说「无需预约」等于替景点下结论；
      // 提示词规则 15 早已要求真模型写「以官方为准」，本地合成是唯一的漏网。
      const xi: Trip = await genOffline(makeParamsFor(ids, 1, '西安'), spots);
      const act: Activity = xi.days[0].activities[0];
      expect(act.note !== undefined && act.note.indexOf('预约信息未获取') >= 0).assertTrue();
      expect(IcsBuilder.statusLabel(act)).assertEqual('预约信息未获取，以官方为准');
      // 种子城（预约信息随种子库给出）仍走原口径，不误伤
      const bj: Trip = await genOffline(makeParamsFor(ids, 1, '北京'), spots);
      const actB: Activity = bj.days[0].activities[0];
      expect(actB.note === undefined).assertTrue();
      expect(IcsBuilder.statusLabel(actB)).assertEqual('无需预约');
    });

    it('offline_lays_selected_paces_across_day_segments', TestType.FUNCTION | Size.MEDIUMTEST | Level.LEVEL1, async () => {
      // 屏3b helper 写「可多选，按天段分别排布」：勾了轻松 + 紧凑就得真的排出松段与紧段，
      // 不能像以前那样按优先级只取一档（那样多选等于白选）
      const spots: Spot[] = makeManySpots(12);
      const mixed: Trip = await genOffline(
        makePaceParams([PaceOption.RELAXED, PaceOption.PACKED], 12), spots);
      expect(mixed.days.length).assertEqual(3);
      expect(mixed.days[0].activities.length).assertEqual(3);
      expect(mixed.days[1].activities.length).assertEqual(3);
      expect(mixed.days[2].activities.length).assertEqual(6);
      expect(mixed.days[0].intensity).assertEqual(IntensityLevel.LOW);
      expect(mixed.days[2].intensity).assertEqual(IntensityLevel.HIGH);
      // 天段顺序按档位轻→紧固定，不跟点选先后走
      const reversed: Trip = await genOffline(
        makePaceParams([PaceOption.PACKED, PaceOption.RELAXED], 12), spots);
      expect(reversed.days[0].activities.length).assertEqual(3);
      expect(reversed.days[2].activities.length).assertEqual(6);
      // 单选仍是整趟同一档
      const single: Trip = await genOffline(
        makePaceParams([PaceOption.STANDARD], 12), spots);
      expect(single.days[0].activities.length).assertEqual(4);
      expect(single.days[2].activities.length).assertEqual(4);
    });

    it('one_day_request_trims_extra_day_and_renumbers',
      TestType.FUNCTION | Size.MEDIUMTEST | Level.LEVEL1, async () => {
        const params: PlanParams = makeOneDayParams();
        const trip: Trip = await LlmClient.generateTrip(params, makeSpots(), makeArea(),
          new TwoDaysForOneDayTransport());
        expect(trip.days.length).assertEqual(1);
        expect(trip.days[0].dayIndex).assertEqual(1);
        expect(trip.days[0].date).assertEqual('2026-10-31');
        expect(trip.startDate).assertEqual('2026-10-31');
        expect(trip.endDate).assertEqual('2026-10-31');
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
