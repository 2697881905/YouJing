/**
 * 地址回填（屏8 真值来源）回归：模型按提示词第 12 条故意留空 address，
 * 落库前必须以**景点库**为准填回；匹配不上时退到目的地而不是留空或瞎猜。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { backfillActivityPlaces, backfillOpeningHours } from '../../../main/ets/utils/TripEnrich';
import { Activity, ActivityCategory, IntensityLevel, Trip, TripDay } from '../../../main/ets/model/Trip';
import { Spot } from '../../../main/ets/model/Spot';

function spot(id: string, name: string, city: string, district: string, lon: number, lat: number): Spot {
  const s: Spot = {
    id: id, name: name, city: city, tags: [], brief: '', suggestedDuration: 120, popularity: 90,
    nearbySpotIds: [], longitude: lon, latitude: lat, district: district, nearestMetro: '',
    booking: { requiresBooking: false },
    provenance: { source: 'seed', updatedAt: '2026-10-27' }
  };
  return s;
}

function act(title: string, address: string, lon: number): Activity {
  const a: Activity = {
    id: `a-${title}`, time: '09:00', endTime: '11:00', title: title, location: '北门',
    address: address, longitude: lon, latitude: 0, status: 'pending' as never, category: ActivityCategory.SIGHT
  };
  return a;
}

function tripOf(acts: Activity[]): Trip {
  const day: TripDay = { dayIndex: 1, date: '2026-11-06', theme: '', intensity: IntensityLevel.MEDIUM,
    dailyCost: 0, activities: acts, meals: [] };
  const t: Trip = { id: 't1', destination: '杨凌', startDate: '2026-11-06', endDate: '2026-11-07',
    people: 2, budget: 8000, style: 'culture', overview: { totalCost: 0, highlights: [], summary: '' },
    days: [day], tips: [] };
  return t;
}

export default function tripEnrichTest(): void {
  describe('TripEnrich', () => {
    const spots: Spot[] = [spot('s1', '西北农林科技大学博览园', '杨凌', '杨陵区', 108.072, 34.265)];

    it('empty_address_is_filled_from_the_spot_library',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
        const t: Trip = tripOf([act('西北农林科技大学博览园', '', 0)]);
        expect(backfillActivityPlaces(t, spots)).assertEqual(1);
        const a: Activity = t.days[0].activities[0];
        expect(a.address).assertEqual('杨凌 杨陵区');
        expect(a.longitude).assertEqual(108.072);
        expect(a.latitude).assertEqual(34.265);
      });

    it('model_written_address_is_overwritten_by_the_library',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
        // 模型即使写了地址也不可信：库是溯源过的真值，匹配上就以库为准
        const t: Trip = tripOf([act('西北农林科技大学博览园', '西安市某处', 999)]);
        backfillActivityPlaces(t, spots);
        expect(t.days[0].activities[0].address).assertEqual('杨凌 杨陵区');
        expect(t.days[0].activities[0].longitude).assertEqual(108.072);
      });

    it('opening_hours_go_to_sight_note_once_only',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
        const withHours: Spot = spot('s2', '西安城墙', '西安', '碑林区', 108.94, 34.26);
        withHours.openingHours = '8:00–22:00';
        const sight: Activity = act('西安城墙', '', 0);
        sight.note = '已预约';
        const food: Activity = act('西安城墙', '', 0);
        food.category = ActivityCategory.FOOD;
        const t: Trip = tripOf([sight, food]);
        expect(backfillOpeningHours(t, [withHours])).assertEqual(1);
        expect(sight.note).assertEqual('已预约 · 开放 8:00–22:00');
        expect(food.note === undefined).assertTrue();
        // 二次回填不重复
        expect(backfillOpeningHours(t, [withHours])).assertEqual(0);
        expect(sight.note).assertEqual('已预约 · 开放 8:00–22:00');
        // AI 已写「全开放」时，全天开放不重复追加
        const allDay: Spot = spot('s3', '曲江池', '西安', '雁塔区', 108.98, 34.20);
        allDay.openingHours = '全天开放';
        const park: Activity = act('曲江池', '', 0);
        park.note = '全开放，预约以官方为准';
        const t2: Trip = tripOf([park]);
        expect(backfillOpeningHours(t2, [allDay])).assertEqual(0);
        expect(park.note).assertEqual('全开放，预约以官方为准');
      });

    it('name_with_suffix_still_matches', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const t: Trip = tripOf([act('西北农林科技大学博览园景区', '', 0)]);
      expect(backfillActivityPlaces(t, spots)).assertEqual(1);
    });

    it('unmatched_activity_falls_back_to_destination_not_blank',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
        const t: Trip = tripOf([act('午餐：杨凌蘸水面', '', 0)]);
        expect(backfillActivityPlaces(t, spots)).assertEqual(0);
        // 库里没有这条活动，屏8 的 meta 行也不能空着
        expect(t.days[0].activities[0].address).assertEqual('杨凌');
      });
  });
}
