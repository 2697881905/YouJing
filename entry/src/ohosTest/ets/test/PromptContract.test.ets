/**
 * 提示词 / Schema / 模型枚举 三者同源的回归（ai/PromptBuilder + ai/TripSchema）。
 *
 * TripSchema 头注释声明「Schema、接口、守卫三者同源：改枚举只改这里」——
 * 这句话此前没有任何用例在守。真漂移起来是静默的：
 * 模型多一个枚举值而 schema 没跟上，AI 就不产该值；schema 多而解析器不认，
 * 整份行程被判非法走屏7。所以这里把三对关系都钉住。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { PromptBuilder } from '../../../main/ets/ai/PromptBuilder';
import { TripSchema } from '../../../main/ets/ai/TripSchema';
import { ActivityCategory, ActivityStatus, IntensityLevel, MealType } from '../../../main/ets/model/Trip';
import { Spot, SpotTag } from '../../../main/ets/model/Spot';
import { Area, AreaGroup, AreaPriceTier } from '../../../main/ets/model/Area';
import {
  PaceOption, PlanParams, SelectedSpot, SpotPriority, TransitPreference, TravelStyle
} from '../../../main/ets/model/PlanParams';

export default function promptContractTest(): void {
  describe('提示词与 Schema 同源', () => {
    it('system_prompt_carries_the_schema', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const sp: string = PromptBuilder.systemPrompt();
      expect(sp.indexOf(TripSchema.TRIP_JSON_SCHEMA) >= 0).assertTrue();
      // 天数与日期规则是解析器硬校验项，提示词里必须明说
      expect(sp.indexOf('days 数组长度必须等于') >= 0).assertTrue();
      expect(sp.indexOf('HH:mm') >= 0).assertTrue();
    });

    it('schema_names_every_key_the_parser_requires',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
        // TripParser 里 reqXxx 的键，少一个就会拿到「AI 产出但解析失败」的静默降级
        const required: string[] = ['days', 'activities', 'meals', 'time', 'endTime',
          'title', 'status', 'category', 'transport', 'summary', 'note', 'reason'];
        for (const k of required) {
          expect(TripSchema.TRIP_JSON_SCHEMA.indexOf(k) >= 0).assertTrue();
        }
      });

    it('map_spot_prompt_is_honest_about_booking_and_hours',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
        const spot: Spot = {
          id: 'mk:西安:x1', name: '西安城墙', city: '西安', tags: [SpotTag.CLASSIC],
          brief: '', suggestedDuration: 90, openingHours: '8:30–17:00', popularity: 100,
          nearbySpotIds: [], longitude: 108.94, latitude: 34.26, district: '碑林区',
          nearestMetro: '', booking: { requiresBooking: false },
          provenance: { source: 'MapKit 地点检索', updatedAt: '2026-10-31', confidence: '中' }
        };
        const area: Area = {
          id: 'mk-area:西安:碑林区', name: '碑林区', city: '西安',
          longitude: 108.94, latitude: 34.26, description: '',
          anchorStations: [], metroLines: [], airportMinutes: 0, trainStationMinutes: 0,
          commerceTags: ['地图服务'], diningDensity: '', suitableCrowds: [],
          priceTier: AreaPriceTier.COMFORT, group: AreaGroup.CORE,
          source: 'MapKit', updatedAt: '2026-10-31'
        };
        const selected: SelectedSpot = { spotId: spot.id, priority: SpotPriority.MUST };
        const params: PlanParams = {
          basic: { destination: '西安', startDate: '2026-11-06', endDate: '2026-11-08',
            people: 2, budget: 8000 },
          style: TravelStyle.LEISURE, stayTier: 'comfort', transit: TransitPreference.PUBLIC,
          paces: [PaceOption.STANDARD], selectedSpots: [selected],
          selectedArea: { areaId: area.id }
        };
        const text: string = PromptBuilder.userPrompt(params, [spot], area);
        expect(text.indexOf('计划天数：3 天') >= 0).assertTrue();
        expect(text.indexOf('预约信息未获取，以官方为准') >= 0).assertTrue();
        expect(text.indexOf('无需预约') >= 0).assertFalse();
        expect(text.indexOf('开放:8:30–17:00') >= 0).assertTrue();
        expect(text.indexOf('到机场 0 分钟') >= 0).assertFalse();
        expect(text.indexOf('地图服务区县') >= 0).assertTrue();
        expect(PromptBuilder.systemPrompt().indexOf('排期必须落在该时段内') >= 0).assertTrue();
        expect(PromptBuilder.systemPrompt().indexOf('禁止编造预约方式') >= 0).assertTrue();
        expect(PromptBuilder.systemPrompt().indexOf('不要再给它填 transport 字段') >= 0).assertTrue();
      });

    it('single_day_prompt_states_one_day_and_bans_split',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
        // 2026-10-31 真机：1 天行程模型拆成「抵达日 + 游玩日」两天，dayIndex 重复
        const area: Area = {
          id: 't-area', name: '碑林区', city: '西安', longitude: 108.94, latitude: 34.26,
          description: '', anchorStations: [], metroLines: [], airportMinutes: 0,
          trainStationMinutes: 0, commerceTags: [], diningDensity: '', suitableCrowds: [],
          priceTier: AreaPriceTier.COMFORT, group: AreaGroup.CORE, source: 'test',
          updatedAt: '2026-10-31'
        };
        const params: PlanParams = {
          basic: { destination: '西安', startDate: '2026-10-31', endDate: '2026-10-31',
            people: 2, budget: 2000 },
          style: TravelStyle.LEISURE, stayTier: 'comfort', transit: TransitPreference.PUBLIC,
          paces: [PaceOption.STANDARD], selectedSpots: [], selectedArea: { areaId: area.id }
        };
        const text: string = PromptBuilder.userPrompt(params, [], area);
        expect(text.indexOf('计划天数：1 天') >= 0).assertTrue();
        const sp: string = PromptBuilder.systemPrompt();
        expect(sp.indexOf('不得把行程拆成') >= 0).assertTrue();
        expect(sp.indexOf('最后一天等于 endDate') >= 0).assertTrue();
        // 规则 17 的措辞在 2026-11-03 改过两次（先去掉自相矛盾的 21:00 边界，再对齐 480 预算）：
        // 这里钉「语义」而不钉旧句子——当日活动+通勤的预算与「末站 = 首站 + 10 小时」两条都要在。
        expect(sp.indexOf('各段通勤之和不超过 **8 小时（480 分钟）**') >= 0).assertTrue();
        expect(sp.indexOf('最后一站结束时间 ≤ 第一站开始时间 + 10 小时') >= 0).assertTrue();
      });

    it('schema_enums_match_model_enums_both_ways',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
        const statuses: string[] = [ActivityStatus.BOOKED, ActivityStatus.NOT_BOOKED,
          ActivityStatus.FULL, ActivityStatus.PENDING, ActivityStatus.NO_NEED];
        expect(statuses.length).assertEqual(TripSchema.ACTIVITY_STATUS.length);
        for (const s of statuses) {
          expect(TripSchema.ACTIVITY_STATUS.indexOf(s) >= 0).assertTrue();
        }
        const cats: string[] = [ActivityCategory.TRANSPORT, ActivityCategory.SIGHT,
          ActivityCategory.FOOD, ActivityCategory.SHOP, ActivityCategory.REST,
          ActivityCategory.HOTEL, ActivityCategory.OTHER];
        expect(cats.length).assertEqual(TripSchema.ACTIVITY_CATEGORY.length);
        for (const c of cats) {
          expect(TripSchema.ACTIVITY_CATEGORY.indexOf(c) >= 0).assertTrue();
        }
        const levels: string[] = [IntensityLevel.LOW, IntensityLevel.MEDIUM,
          IntensityLevel.HIGH];
        expect(levels.length).assertEqual(TripSchema.INTENSITY.length);
        for (const v of levels) {
          expect(TripSchema.INTENSITY.indexOf(v) >= 0).assertTrue();
        }
        const meals: string[] = [MealType.BREAKFAST, MealType.LUNCH,
          MealType.DINNER];
        expect(meals.length).assertEqual(TripSchema.MEAL_TYPE.length);
        for (const v of meals) {
          expect(TripSchema.MEAL_TYPE.indexOf(v) >= 0).assertTrue();
        }
      });
  });
}
