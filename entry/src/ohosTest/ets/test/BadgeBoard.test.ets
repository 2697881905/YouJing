/**
 * 勋章墙纯逻辑回归：合并口径（同城同名一枚、重复到访计数、到站章升级）、
 * 分组与排序、总数、日期文案与行程落点。数据只造最小集合，不依赖 RDB。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { Badge, BadgeGroup, BadgeRecord, badgeCityCount, badgeDateText, badgeMeta,
  badgeRoute, badgeSourceText, badgeTotal, buildBadgeBoard, findBadge } from '../../../main/ets/utils/BadgeBoard';

function rec(id: string, city: string, name: string, at: number, arrival: boolean,
  distance: number, trip: string): BadgeRecord {
  const r: BadgeRecord = {
    id: id, tripId: trip, spotName: name, city: city,
    tripStartDate: '2026-10-29', tripEndDate: '2026-10-31',
    earnedAt: at, arrival: arrival, distanceM: distance
  };
  return r;
}

export default function badgeBoardTest(): void {
  describe('BadgeBoard', () => {
    it('empty_input_gives_empty_board', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const groups: BadgeGroup[] = buildBadgeBoard([]);
      expect(groups.length).assertEqual(0);
      expect(badgeTotal(groups)).assertEqual(0);
      expect(badgeCityCount(groups)).assertEqual(0);
    });

    it('same_city_and_name_merge_into_one_badge', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const rows: BadgeRecord[] = [
        rec('t2:a', '北京', '故宫博物院', 2000, true, 120, 't2'),
        rec('t1:a', '北京', '故宫博物院', 1000, false, 0, 't1')
      ];
      const groups: BadgeGroup[] = buildBadgeBoard(rows);
      expect(badgeTotal(groups)).assertEqual(1);
      const badge: Badge = groups[0].badges[0];
      expect(badge.visits).assertEqual(2);
      // 首次收下：取更早那笔的行程与时刻
      expect(badge.earnedAt).assertEqual(1000);
      expect(badge.firstCheckinId).assertEqual('t1:a');
      expect(badge.firstTripId).assertEqual('t1');
      expect(badge.lastAt).assertEqual(2000);
      // 任一次到站即算到站章，距离取最小的一次
      expect(badge.arrival).assertTrue();
      expect(badge.distanceM).assertEqual(120);
    });

    it('different_cities_are_different_badges', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const rows: BadgeRecord[] = [
        rec('t1:a', '北京', '钟楼', 1000, false, 0, 't1'),
        rec('t2:a', '西安', '钟楼', 2000, false, 0, 't2')
      ];
      const groups: BadgeGroup[] = buildBadgeBoard(rows);
      expect(badgeTotal(groups)).assertEqual(2);
      expect(badgeCityCount(groups)).assertEqual(2);
    });

    it('names_are_trimmed_before_merging', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const rows: BadgeRecord[] = [
        rec('t1:a', '北京', ' 故宫博物院 ', 1000, false, 0, 't1'),
        rec('t2:a', '北京', '故宫博物院', 2000, false, 0, 't2')
      ];
      const groups: BadgeGroup[] = buildBadgeBoard(rows);
      expect(badgeTotal(groups)).assertEqual(1);
      expect(groups[0].badges[0].spotName).assertEqual('故宫博物院');
    });

    it('empty_names_are_dropped', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const rows: BadgeRecord[] = [rec('t1:a', '北京', '   ', 1000, false, 0, 't1')];
      expect(buildBadgeBoard(rows).length).assertEqual(0);
    });

    it('groups_by_newest_badge_and_sorts_within_group', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const rows: BadgeRecord[] = [
        rec('t1:a', '北京', 'A', 1000, false, 0, 't1'),
        rec('t1:b', '北京', 'B', 3000, false, 0, 't1'),
        rec('t2:a', '西安', 'C', 2000, false, 0, 't2')
      ];
      const groups: BadgeGroup[] = buildBadgeBoard(rows);
      expect(groups[0].city).assertEqual('北京');
      expect(groups[0].badges[0].spotName).assertEqual('B');
      expect(groups[0].badges[1].spotName).assertEqual('A');
      expect(groups[1].city).assertEqual('西安');
    });

    it('find_badge_requires_same_city', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const rows: BadgeRecord[] = [rec('t1:a', '北京', '钟楼', 1000, false, 0, 't1')];
      const groups: BadgeGroup[] = buildBadgeBoard(rows);
      expect(findBadge(groups, '北京', '钟楼') !== null).assertTrue();
      expect(findBadge(groups, '西安', '钟楼') === null).assertTrue();
      expect(findBadge(groups, '北京', '鼓楼') === null).assertTrue();
    });

    it('source_and_meta_copy', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const manual: Badge = {
        spotName: 'A', city: '北京', earnedAt: new Date(2026, 9, 30, 12).getTime(),
        lastAt: new Date(2026, 9, 30, 12).getTime(), visits: 1, arrival: false,
        firstCheckinId: 't1:a', firstTripId: 't1', tripStartDate: '2026-10-30',
        tripEndDate: '2026-10-30', distanceM: 0
      };
      expect(badgeSourceText(manual)).assertEqual('手动打卡');
      expect(badgeMeta(manual)).assertEqual('10月30日 · 手动打卡');
      const arrival: Badge = {
        spotName: 'A', city: '北京', earnedAt: manual.earnedAt, lastAt: manual.earnedAt,
        visits: 3, arrival: true, firstCheckinId: 't1:a', firstTripId: 't1',
        tripStartDate: '2026-10-30', tripEndDate: '2026-10-30', distanceM: 80
      };
      expect(badgeSourceText(arrival)).assertEqual('到站打卡');
      expect(badgeMeta(arrival)).assertEqual('10月30日 · 到站打卡 · 到访 3 次');
    });

    it('route_follows_trip_range', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const badge: Badge = {
        spotName: 'A', city: '北京', earnedAt: 0, lastAt: 0, visits: 1, arrival: false,
        firstCheckinId: 't1:a', firstTripId: 't1', tripStartDate: '2026-10-29',
        tripEndDate: '2026-10-31', distanceM: 0
      };
      expect(badgeRoute(badge, '2026-10-28')).assertEqual('Itinerary');
      expect(badgeRoute(badge, '2026-10-30')).assertEqual('OnTrip');
      expect(badgeRoute(badge, '2026-11-01')).assertEqual('Itinerary');
    });

    it('date_text_keeps_local_day', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const at: number = new Date(2026, 9, 30, 12, 0, 0).getTime();
      expect(badgeDateText(at)).assertEqual('10月30日');
    });
  });
}
