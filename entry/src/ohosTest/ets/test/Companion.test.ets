/**
 * 伴随助手核心逻辑回归（companion/CompanionPrefs + CompanionEngine）。
 * 纯逻辑、无 UI、无 @kit，可离线断言（tools/verify_companion_logic.sh）。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { CompanionPrefs } from '../../../main/ets/companion/CompanionPrefs';
import { CompanionEngine } from '../../../main/ets/companion/CompanionEngine';
import { UnplannedInput } from '../../../main/ets/companion/CompanionTypes';
import { Activity, ActivityCategory, ActivityStatus, IntensityLevel, TripDay } from '../../../main/ets/model/Trip';
import { Spot } from '../../../main/ets/model/Spot';
import { GeoPoint } from '../../../main/ets/utils/Geo';

function act(id: string, time: string, endTime: string, cat: ActivityCategory): Activity {
  const a: Activity = {
    id: id, time: time, endTime: endTime, title: id, location: id, address: '',
    longitude: 0, latitude: 0, status: ActivityStatus.NO_NEED, category: cat
  };
  return a;
}

function dayOf(acts: Activity[]): TripDay {
  const d: TripDay = {
    dayIndex: 1, date: '2026-11-11', theme: '测试', intensity: IntensityLevel.MEDIUM,
    dailyCost: 0, activities: acts, meals: []
  };
  return d;
}

function input(recognized: boolean, estVisitMin: number, day: TripDay, nowMin: number): UnplannedInput {
  const u: UnplannedInput = {
    recognized: recognized, placeName: recognized ? '什刹海' : '', estVisitMin: estVisitMin,
    day: day, nowMin: nowMin
  };
  return u;
}

function spot(id: string, name: string, lat: number, lng: number, dur: number): Spot {
  const s: Spot = {
    id: id, name: name, city: '北京', tags: [], brief: '', suggestedDuration: dur,
    popularity: 0, nearbySpotIds: [], longitude: lng, latitude: lat,
    district: '', nearestMetro: '', booking: { requiresBooking: false },
    provenance: { source: 'test', updatedAt: '2026-11-11' }
  };
  return s;
}

function pt(lat: number, lng: number): GeoPoint {
  const p: GeoPoint = { latitude: lat, longitude: lng };
  return p;
}

export default function companionTest(): void {
  describe('CompanionPrefs', () => {
    it('degrade_after_three_consistent_recommended', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const p = new CompanionPrefs();
      expect(p.modeFor('k')).assertEqual('ask');
      p.recordChoice('k', 'rec', 'rec');
      p.recordChoice('k', 'rec', 'rec');
      expect(p.modeFor('k')).assertEqual('ask');
      p.recordChoice('k', 'rec', 'rec');
      expect(p.modeFor('k')).assertEqual('notify');
    });

    it('correction_restores_ask_immediately', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const p = new CompanionPrefs();
      p.recordChoice('k', 'rec', 'rec');
      p.recordChoice('k', 'rec', 'rec');
      p.recordChoice('k', 'rec', 'rec');
      expect(p.modeFor('k')).assertEqual('notify');
      p.correct('k');
      expect(p.modeFor('k')).assertEqual('ask');
    });

    it('non_recommended_choice_resets_streak', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const p = new CompanionPrefs();
      p.recordChoice('k', 'rec', 'rec');
      p.recordChoice('k', 'rec', 'rec');
      p.recordChoice('k', 'other', 'rec');
      p.recordChoice('k', 'rec', 'rec');
      expect(p.modeFor('k')).assertEqual('ask');
    });
  });

  describe('CompanionEngine', () => {
    it('unrecognized_place_asks_lightly', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const day = dayOf([act('next', '11:00', '12:00', ActivityCategory.SIGHT)]);
      const p = CompanionEngine.unplannedArrival(input(false, 60, day, 600), new CompanionPrefs());
      expect(p !== null).assertTrue();
      expect(p!.kind).assertEqual('unknown_place');
      expect(p!.stake).assertEqual('low');
      expect(p!.options.length >= 2).assertTrue();
    });

    it('no_consequence_stays_silent', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // 10:00 + 30min = 10:30 < 下一站 11:00 → 塞得下，安静吸收
      const day = dayOf([act('next', '11:00', '12:00', ActivityCategory.SIGHT)]);
      const p = CompanionEngine.unplannedArrival(input(true, 30, day, 600), new CompanionPrefs());
      expect(p === null).assertTrue();
    });

    it('consequence_offers_consultative_options', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // 10:00 + 90min = 11:30 > 下一站 11:00 → 挤占，给三选项
      const day = dayOf([act('next', '11:00', '12:00', ActivityCategory.SIGHT)]);
      const p = CompanionEngine.unplannedArrival(input(true, 90, day, 600), new CompanionPrefs());
      expect(p !== null).assertTrue();
      expect(p!.kind).assertEqual('unplanned_arrival');
      expect(p!.options.length).assertEqual(3);
      expect(p!.recommendedIndex).assertEqual(0);
      expect(p!.stake).assertEqual('low');
      expect(p!.options[0].action.kind).assertEqual('move_tomorrow');
      expect(p!.options[0].action.targetId).assertEqual('next');
    });

    it('skips_transport_and_hotel_when_finding_next', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // 下一站是交通腿（不算挤占对象），真正的下一景点在 12:00；10:00+90=11:30<12:00 → 静默
      const day = dayOf([
        act('leg', '10:30', '11:00', ActivityCategory.TRANSPORT),
        act('sight', '12:00', '13:00', ActivityCategory.SIGHT)
      ]);
      const p = CompanionEngine.unplannedArrival(input(true, 90, day, 600), new CompanionPrefs());
      expect(p === null).assertTrue();
    });

    it('degraded_preference_yields_notify_mode', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const prefs = new CompanionPrefs();
      prefs.recordChoice('unplanned_move_tomorrow', 'move_tomorrow', 'move_tomorrow');
      prefs.recordChoice('unplanned_move_tomorrow', 'move_tomorrow', 'move_tomorrow');
      prefs.recordChoice('unplanned_move_tomorrow', 'move_tomorrow', 'move_tomorrow');
      const day = dayOf([act('next', '11:00', '12:00', ActivityCategory.SIGHT)]);
      const p = CompanionEngine.unplannedArrival(input(true, 90, day, 600), prefs);
      expect(p !== null).assertTrue();
      expect(p!.mode).assertEqual('notify');
    });
  });

  describe('CompanionEngine.detectUnplanned', () => {
    it('recognizes_unplanned_spot_after_dwell', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // 计划站在远处（34.5,108.5），fix 落在规划外景点什刹海（34.27,108.07），停够 5min
      const day = dayOf([act('plan', '11:00', '12:00', ActivityCategory.SIGHT)]);
      day.activities[0].latitude = 34.5;
      day.activities[0].longitude = 108.5;
      const spots: Spot[] = [spot('s1', '什刹海', 34.27, 108.07, 90)];
      const u = CompanionEngine.detectUnplanned(pt(34.27, 108.07), day, spots, 600, 5);
      expect(u !== null).assertTrue();
      expect(u!.recognized).assertTrue();
      expect(u!.placeName).assertEqual('什刹海');
      expect(u!.estVisitMin).assertEqual(90);
    });

    it('passing_by_without_dwell_is_null', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const day = dayOf([act('plan', '11:00', '12:00', ActivityCategory.SIGHT)]);
      day.activities[0].latitude = 34.5;
      day.activities[0].longitude = 108.5;
      const spots: Spot[] = [spot('s1', '什刹海', 34.27, 108.07, 90)];
      const u = CompanionEngine.detectUnplanned(pt(34.27, 108.07), day, spots, 600, 1);
      expect(u === null).assertTrue();
    });

    it('planned_arrival_is_null', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // fix 落在计划内站点附近 → 不是规划外
      const day = dayOf([act('plan', '11:00', '12:00', ActivityCategory.SIGHT)]);
      day.activities[0].latitude = 34.27;
      day.activities[0].longitude = 108.07;
      const spots: Spot[] = [spot('s1', '什刹海', 34.27, 108.07, 90)];
      const u = CompanionEngine.detectUnplanned(pt(34.27, 108.07), day, spots, 600, 5);
      expect(u === null).assertTrue();
    });

    it('spot_already_in_plan_is_null', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // 景点名已在计划（按名匹配）→ 不算规划外
      const day = dayOf([act('什刹海', '11:00', '12:00', ActivityCategory.SIGHT)]);
      day.activities[0].latitude = 34.5;
      day.activities[0].longitude = 108.5;
      const spots: Spot[] = [spot('s1', '什刹海', 34.27, 108.07, 90)];
      const u = CompanionEngine.detectUnplanned(pt(34.27, 108.07), day, spots, 600, 5);
      expect(u === null).assertTrue();
    });

    it('fix_near_no_known_spot_is_null', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const day = dayOf([act('plan', '11:00', '12:00', ActivityCategory.SIGHT)]);
      day.activities[0].latitude = 34.5;
      day.activities[0].longitude = 108.5;
      const spots: Spot[] = [spot('s1', '什刹海', 34.27, 108.07, 90)];
      const u = CompanionEngine.detectUnplanned(pt(35.0, 109.0), day, spots, 600, 5);
      expect(u === null).assertTrue();
    });
  });
}