/**
 * 切片 4 回归：一句话意图解析 + 自动选点/住宿区。
 * 与 tools/trip_intent_check.ts 同源；这里跑真机 hypium 侧，不碰 @kit。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { TripIntent, TripIntentParser } from '../../../main/ets/utils/TripIntentParser';
import { PlanAutoPick } from '../../../main/ets/utils/PlanAutoPick';
import { Spot, SpotTag } from '../../../main/ets/model/Spot';
import { Area, AreaGroup, AreaPriceTier } from '../../../main/ets/model/Area';
import { SelectedSpot, SpotPriority } from '../../../main/ets/model/PlanParams';
import { GeoPoint } from '../../../main/ets/utils/Geo';

const TODAY: string = '2026-10-30'; // 周五

function spot(id: string, popularity: number, tags: SpotTag[], lat: number, lng: number): Spot {
  const s: Spot = {
    id: id, name: id, city: '测试', tags: tags, brief: '',
    suggestedDuration: 120, popularity: popularity, nearbySpotIds: [],
    longitude: lng, latitude: lat, district: '', nearestMetro: '',
    booking: { requiresBooking: false },
    provenance: { source: 'test', updatedAt: '2026-10-30' }
  };
  return s;
}

function area(id: string, tier: AreaPriceTier, lat: number, lng: number): Area {
  const a: Area = {
    id: id, name: id, city: '测试', longitude: lng, latitude: lat, description: '',
    anchorStations: [], metroLines: [], airportMinutes: 0, trainStationMinutes: 0,
    commerceTags: [], diningDensity: '中', suitableCrowds: [], priceTier: tier,
    group: AreaGroup.CORE, source: 'test', updatedAt: '2026-10-30'
  };
  return a;
}

function sel(id: string): SelectedSpot {
  const s: SelectedSpot = { spotId: id, priority: SpotPriority.MUST };
  return s;
}

export default function tripIntentTest(): void {
  describe('TripIntent', () => {
    it('parse_full_sentence', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const intent: TripIntent =
        TripIntentParser.parse('下周五去上海玩三天，两个人，喜欢历史和美食', TODAY);
      expect(intent.city).assertEqual('上海');
      expect(intent.startDate).assertEqual('2026-11-06');
      expect(intent.dayCount).assertEqual(3);
      expect(intent.people).assertEqual(2);
      expect(intent.style).assertEqual('foodie');
      expect(intent.tags.indexOf(SpotTag.CLASSIC) >= 0).assertTrue();
      expect(intent.notes.length).assertEqual(0);
    });

    it('parse_budget_and_preferences', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const intent: TripIntent =
        TripIntentParser.parse('明天去北京，一家三口，预算1.5万，想住得舒服点，坐地铁', TODAY);
      expect(intent.city).assertEqual('北京');
      expect(intent.startDate).assertEqual('2026-10-31');
      expect(intent.people).assertEqual(3);
      expect(intent.budgetAmount).assertEqual(15000);
      expect(intent.budgetIsPerPerson).assertFalse();
      expect(intent.stayTier).assertEqual('comfort');
      expect(intent.transit).assertEqual('public');
      expect(TripIntentParser.budgetPerPerson(intent.budgetAmount, intent.budgetIsPerPerson,
        intent.people)).assertEqual(5000);
    });

    it('unsupported_city_is_honest', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const intent: TripIntent = TripIntentParser.parse('11月15日去西安玩4天', TODAY);
      expect(intent.city).assertEqual('');
      expect(intent.unsupportedCity).assertEqual('西安');
      expect(intent.startDate).assertEqual('2026-11-15');
      expect(intent.dayCount).assertEqual(4);
      const fromTo: TripIntent = TripIntentParser.parse('从北京去西安玩三天', TODAY);
      expect(fromTo.unsupportedCity).assertEqual('西安');
      const full: TripIntent =
        TripIntentParser.parse('下周五去西安玩三天，两个人，预算一万', TODAY);
      expect(full.unsupportedCity).assertEqual('西安');
      expect(full.startDate).assertEqual('2026-11-06');
      expect(full.dayCount).assertEqual(3);
      expect(full.people).assertEqual(2);
      expect(full.budgetAmount).assertEqual(10000);
    });

    it('duration_and_date_edges', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const ordinal: TripIntent =
        TripIntentParser.parse('第3天去故宫，去北京玩五天', TODAY);
      expect(ordinal.dayCount).assertEqual(5);
      const nights: TripIntent = TripIntentParser.parse('去广州住4晚', TODAY);
      expect(nights.dayCount).assertEqual(5);
      const rollover: TripIntent = TripIntentParser.parse('1月5日去北京', '2026-12-30');
      expect(rollover.startDate).assertEqual('2027-01-05');
      expect(rollover.notes.length).assertEqual(1);
      const badDate: TripIntent = TripIntentParser.parse('2月30日去北京', TODAY);
      expect(badDate.startDate).assertEqual('');
      expect(badDate.notes.length).assertEqual(1);
    });

    it('budget_per_person_clamps', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(TripIntentParser.budgetPerPerson(8000, false, 4)).assertEqual(3000);
      expect(TripIntentParser.budgetPerPerson(100000, false, 1)).assertEqual(12000);
      expect(TripIntentParser.budgetPerPerson(8100, false, 2)).assertEqual(4000);
      expect(TripIntentParser.budgetPerPerson(0, false, 2)).assertEqual(0);
    });

    it('auto_pick_spots_follows_pace_and_tags', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const spots: Spot[] = [
        spot('s1', 90, [SpotTag.CLASSIC], 34.27, 108.07),
        spot('s2', 80, [SpotTag.NICHE], 34.28, 108.08),
        spot('s3', 70, [SpotTag.FAMILY], 34.29, 108.09),
        spot('s4', 60, [SpotTag.CLASSIC], 34.30, 108.10),
        spot('s5', 50, [], 34.31, 108.11),
        spot('s6', 40, [], 34.32, 108.12)
      ];
      expect(PlanAutoPick.dailyCap('relaxed')).assertEqual(3);
      expect(PlanAutoPick.dailyCap('standard')).assertEqual(4);
      expect(PlanAutoPick.dailyCap('packed')).assertEqual(6);
      expect(PlanAutoPick.dailyCap('')).assertEqual(4);
      const oneDay: SelectedSpot[] = PlanAutoPick.pickSpots(spots, 1, 'standard', ['classic']);
      expect(oneDay.length).assertEqual(4);
      expect(oneDay[0].spotId).assertEqual('s1');
      expect(oneDay[1].spotId).assertEqual('s4');
      expect(oneDay[2].spotId).assertEqual('s2');
      expect(oneDay[0].priority).assertEqual(SpotPriority.MUST);
      expect(oneDay[1].priority).assertEqual(SpotPriority.WANT);
      const twoDays: SelectedSpot[] = PlanAutoPick.pickSpots(spots, 2, 'relaxed', []);
      expect(twoDays.length).assertEqual(6);
      expect(twoDays[1].priority).assertEqual(SpotPriority.MUST);
      expect(twoDays[2].priority).assertEqual(SpotPriority.WANT);
    });

    it('auto_pick_area_by_tier_and_distance', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const spots: Spot[] = [spot('s6', 40, [], 34.32, 108.12)];
      const areas: Area[] = [
        area('a1', AreaPriceTier.ECONOMY, 34.00, 108.00),
        area('a2', AreaPriceTier.COMFORT, 34.10, 108.10),
        area('a3', AreaPriceTier.COMFORT, 34.20, 108.20)
      ];
      const near: GeoPoint[] = [{ latitude: 34.19, longitude: 108.19 }];
      const nearest: Area | null = PlanAutoPick.nearestArea(areas, near);
      expect(nearest !== null && nearest.id === 'a3').assertTrue();
      expect(PlanAutoPick.nearestArea(areas, []) === null).assertTrue();
      const comfort: Area | null = PlanAutoPick.pickArea(areas, spots, [sel('s6')], 'comfort');
      expect(comfort !== null && comfort.id === 'a3').assertTrue();
      const economy: Area | null = PlanAutoPick.pickArea(areas, spots, [sel('s6')], 'economy');
      expect(economy !== null && economy.id === 'a1').assertTrue();
      const fallback: Area | null = PlanAutoPick.pickArea(areas, spots, [sel('s6')], 'luxury');
      expect(fallback !== null && fallback.id === 'a3').assertTrue();
      expect(PlanAutoPick.pickArea([], spots, [sel('s1')], 'comfort') === null).assertTrue();
      expect(PlanAutoPick.describe([], null, 1, 'standard').indexOf('没有可预选') >= 0).assertTrue();
    });
  });
}
