/**
 * 切片 5 回归：行后回顾 / 城市套章 / 周年。
 * 与 tools/trip_review_check.ts 同源；这里跑真机 hypium 侧，不碰 @kit。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import {
  Activity, ActivityCategory, ActivityStatus, IntensityLevel, Trip, TripDay
} from '../../../main/ets/model/Trip';
import { BadgeGroup, BadgeRecord, buildBadgeBoard } from '../../../main/ets/utils/BadgeBoard';
import {
  AnniversaryTrip, ReviewView, anniversaryText, buildReview, findAnniversary, reviewTimeText
} from '../../../main/ets/utils/TripReview';
import {
  CitySpotSet, CityStamp, buildCityStamps, stampMeta, stampOf, stampPercent
} from '../../../main/ets/utils/CityStamps';

function activity(id: string, time: string, title: string): Activity {
  const act: Activity = {
    id: id, time: time, endTime: time, title: title, location: title + '·入口',
    address: '测试地址', longitude: 0, latitude: 0,
    status: ActivityStatus.NO_NEED, category: ActivityCategory.SIGHT
  };
  return act;
}

function day(dayIndex: number, date: string, acts: Activity[]): TripDay {
  const d: TripDay = {
    dayIndex: dayIndex, date: date, theme: `第 ${dayIndex} 天主题`,
    intensity: IntensityLevel.MEDIUM, dailyCost: 0, activities: acts, meals: []
  };
  return d;
}

function makeTrip(id: string, city: string, start: string, end: string, days: TripDay[]): Trip {
  const trip: Trip = {
    id: id, destination: city, startDate: start, endDate: end, people: 2, budget: 8000,
    style: 'culture',
    overview: { totalCost: 1000, highlights: ['亮点一'], summary: '一句总结' },
    days: days, tips: []
  };
  return trip;
}

function rec(tripId: string, activityId: string, spotName: string, city: string,
  earnedAt: number, arrival: boolean): BadgeRecord {
  const record: BadgeRecord = {
    id: `${tripId}:${activityId}`, tripId: tripId, spotName: spotName, city: city,
    tripStartDate: '2026-10-20', tripEndDate: '2026-10-22',
    earnedAt: earnedAt, arrival: arrival, distanceM: arrival ? 120 : 0
  };
  return record;
}

const T1: Trip = makeTrip('t1', '北京', '2026-10-20', '2026-10-22', [
  day(1, '2026-10-20', [activity('a1', '09:00', '故宫博物院'), activity('a2', '14:00', '天坛公园')]),
  day(2, '2026-10-21', [activity('a3', '10:00', '颐和园')])
]);
const RECORDS: BadgeRecord[] = [
  rec('t1', 'a1', '故宫博物院', '北京', 1000, true),
  rec('t1', 'a2', '天坛公园', '北京', 2000, false),
  rec('t1', 'ghost', '已删除的节点', '北京', 2500, false)
];
const GROUPS: BadgeGroup[] = buildBadgeBoard(RECORDS);

export default function tripReviewTest(): void {
  describe('TripReview', () => {
    it('review_counts_and_new_badges', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const view: ReviewView = buildReview(T1, RECORDS, GROUPS, 880);
      expect(view.city).assertEqual('北京');
      expect(view.dayCount).assertEqual(2);
      expect(view.spotTotal).assertEqual(3);
      expect(view.checkedTotal).assertEqual(2);
      expect(view.arrivalTotal).assertEqual(1);
      expect(view.expenseTotal).assertEqual(880);
      expect(view.firstCheckedAt).assertEqual(1000);
      expect(view.lastCheckedAt).assertEqual(2000);
      expect(view.days[0].checked.length).assertEqual(2);
      expect(view.days[0].checked[0].title).assertEqual('故宫博物院');
      expect(view.days[0].checked[0].arrival).assertTrue();
      expect(view.days[1].checked.length).assertEqual(0);
      expect(view.newBadges.length).assertEqual(2);
      expect(view.newBadges[0].spotName).assertEqual('故宫博物院');
      expect(view.summary).assertEqual('一句总结');
    });

    it('review_ignores_orphan_and_other_trip', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const t2: Trip = makeTrip('t2', '北京', '2026-10-24', '2026-10-24', [
        day(1, '2026-10-24', [activity('b1', '10:00', '天坛公园')])
      ]);
      const other: ReviewView = buildReview(t2, RECORDS, GROUPS, 0);
      expect(other.checkedTotal).assertEqual(0);
      expect(other.newBadges.length).assertEqual(0);
      const empty: ReviewView = buildReview(t2, [], [], 0);
      expect(empty.checkedTotal).assertEqual(0);
      expect(empty.firstCheckedAt).assertEqual(0);
      expect(empty.days[0].total).assertEqual(1);
    });

    it('review_time_text', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const at: number = new Date(2026, 9, 20, 9, 5).getTime();
      expect(reviewTimeText(at)).assertEqual('09:05');
    });

    it('anniversary_hits_latest_cross_year', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const trips: AnniversaryTrip[] = [
        { id: 'old', destination: '北京', startDate: '2025-10-30', endDate: '2025-11-02' },
        { id: 'sameYear', destination: '上海', startDate: '2026-10-25', endDate: '2026-10-27' },
        { id: 'endingToday', destination: '广州', startDate: '2025-10-28', endDate: '2026-10-31' },
        { id: 'latest', destination: '深圳', startDate: '2025-10-31', endDate: '2025-10-31' }
      ];
      const hit: AnniversaryTrip | null = findAnniversary(trips, '2026-10-31');
      expect(hit !== null).assertTrue();
      expect(hit === null ? '' : hit.id).assertEqual('latest');
      expect(hit === null ? '' : anniversaryText(hit, '2026-10-31')).assertEqual('去年的今天，你在深圳');
      const older: AnniversaryTrip = {
        id: 'older', destination: '成都', startDate: '2024-10-31', endDate: '2024-10-31'
      };
      expect(anniversaryText(older, '2026-10-31')).assertEqual('2024 年的今天，你在成都');
      expect(findAnniversary([], '2026-10-31') === null).assertTrue();
      expect(findAnniversary(trips, '2026-02-30') === null).assertTrue();
    });

    it('anniversary_wraps_year_end', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const trips: AnniversaryTrip[] = [
        { id: 'wrap', destination: '杭州', startDate: '2024-12-30', endDate: '2025-01-02' }
      ];
      const hit: AnniversaryTrip | null = findAnniversary(trips, '2026-01-01');
      expect(hit !== null).assertTrue();
      expect(hit === null ? '' : hit.id).assertEqual('wrap');
      expect(hit === null ? '' : anniversaryText(hit, '2026-01-01')).assertEqual('去年的今天，你在杭州');
    });

    it('city_stamps_progress_and_complete', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const sets: CitySpotSet[] = [
        { city: '北京', names: ['故宫博物院', '天坛公园', '颐和园', '八达岭长城'] },
        { city: '上海', names: ['外滩', '豫园'] }
      ];
      const rows: BadgeRecord[] = [
        rec('t1', 'a1', '故宫博物院', '北京', 1000, true),
        rec('t1', 'a2', ' 天坛公园 ', '北京', 2000, false),
        rec('t1', 'a9', '未收录景点', '北京', 2100, false),
        rec('t2', 'b1', '外滩', '上海', 3000, false),
        rec('t2', 'b2', '豫园', '上海', 3100, false),
        rec('t3', 'c1', '白云山', '广州', 3200, false)
      ];
      const stamps: CityStamp[] = buildCityStamps(sets, buildBadgeBoard(rows));
      expect(stamps.length).assertEqual(3);
      const bj: CityStamp | null = stampOf(stamps, '北京');
      expect(bj !== null).assertTrue();
      expect(bj === null ? -1 : bj.collected).assertEqual(2);
      expect(bj === null ? -1 : bj.total).assertEqual(4);
      expect(bj !== null && bj.complete).assertFalse();
      expect(bj === null ? -1 : stampPercent(bj)).assertEqual(50);
      expect(stampMeta(bj, 3)).assertEqual('2 / 4 枚');
      const sh: CityStamp | null = stampOf(stamps, '上海');
      expect(sh !== null).assertTrue();
      expect(sh !== null && sh.complete).assertTrue();
      expect(sh === null ? -1 : stampPercent(sh)).assertEqual(100);
      const gz: CityStamp | null = stampOf(stamps, '广州');
      expect(gz !== null).assertTrue();
      expect(gz === null ? -1 : gz.total).assertEqual(0);
      expect(stampMeta(gz, 1)).assertEqual('1 枚');
      expect(stampOf(stamps, '成都') === null).assertTrue();
    });
  });
}
