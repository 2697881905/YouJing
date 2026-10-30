/**
 * 切片 5（行后回顾 / 城市套章 / 周年）纯逻辑离线断言。
 * 与 entry/src/ohosTest/ets/test/TripReview.test.ets 同源。
 */

import { Activity, ActivityCategory, ActivityStatus, Meal, Trip, TripDay } from '../entry/src/main/ets/model/Trip';
import { Badge, BadgeGroup, BadgeRecord, buildBadgeBoard } from '../entry/src/main/ets/utils/BadgeBoard';
import {
  AnniversaryTrip, ReviewView, anniversaryText, buildReview, findAnniversary, reviewTimeText
} from '../entry/src/main/ets/utils/TripReview';
import {
  CityStamp, CitySpotSet, buildCityStamps, stampMeta, stampOf, stampPercent
} from '../entry/src/main/ets/utils/CityStamps';

let passed: number = 0;

function ok(cond: boolean, label: string): void {
  if (!cond) {
    throw new Error(`FAIL ${label}`);
  }
  passed += 1;
}

function eq(actual: string | number | boolean, expected: string | number | boolean, label: string): void {
  if (actual !== expected) {
    throw new Error(`FAIL ${label}: actual=${actual} expected=${expected}`);
  }
  passed += 1;
}

function activity(id: string, time: string, title: string): Activity {
  const act: Activity = {
    id: id, time: time, endTime: time, title: title, location: title + '·入口',
    address: '测试地址', longitude: 0, latitude: 0,
    status: ActivityStatus.NO_NEED, category: ActivityCategory.SIGHT
  };
  return act;
}

function day(dayIndex: number, date: string, acts: Activity[]): TripDay {
  const meals: Meal[] = [];
  const d: TripDay = {
    dayIndex: dayIndex, date: date, theme: `第 ${dayIndex} 天主题`,
    intensity: 'medium' as TripDay['intensity'], dailyCost: 0,
    activities: acts, meals: meals
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

// ---------- 回顾视图 ----------
const t1: Trip = makeTrip('t1', '北京', '2026-10-20', '2026-10-22', [
  day(1, '2026-10-20', [activity('a1', '09:00', '故宫博物院'), activity('a2', '14:00', '天坛公园')]),
  day(2, '2026-10-21', [activity('a3', '10:00', '颐和园')])
]);
const t2: Trip = makeTrip('t2', '北京', '2026-10-24', '2026-10-24', [
  day(1, '2026-10-24', [activity('b1', '10:00', '天坛公园')])
]);
const records: BadgeRecord[] = [
  rec('t1', 'a1', '故宫博物院', '北京', 1000, true),
  rec('t1', 'a2', '天坛公园', '北京', 2000, false),
  rec('t1', 'ghost', '已删除的节点', '北京', 2500, false),
  rec('t2', 'b1', '天坛公园', '北京', 3000, false)
];
const groups: BadgeGroup[] = buildBadgeBoard(records);
const view: ReviewView = buildReview(t1, records, groups, 880);

eq(view.tripId, 't1', 'review.tripId');
eq(view.city, '北京', 'review.city');
eq(view.dayCount, 2, 'review.dayCount');
eq(view.spotTotal, 3, 'review.spotTotal');
eq(view.checkedTotal, 2, 'review.checkedTotal');
eq(view.arrivalTotal, 1, 'review.arrivalTotal');
eq(view.expenseTotal, 880, 'review.expenseTotal');
eq(view.firstCheckedAt, 1000, 'review.firstCheckedAt');
eq(view.lastCheckedAt, 2000, 'review.lastCheckedAt');
eq(view.days.length, 2, 'review.days.length');
eq(view.days[0].checked.length, 2, 'review.day1.checked');
eq(view.days[0].checked[0].title, '故宫博物院', 'review.day1.firstTitle');
eq(view.days[0].checked[0].arrival, true, 'review.day1.firstArrival');
eq(view.days[0].checked[1].arrival, false, 'review.day1.secondArrival');
eq(view.days[1].checked.length, 0, 'review.day2.empty');
eq(view.newBadges.length, 2, 'review.newBadges');
eq(view.newBadges[0].spotName, '故宫博物院', 'review.newBadges.first');
eq(view.newBadges[1].spotName, '天坛公园', 'review.newBadges.second');
eq(view.newBadges[1].visits, 2, 'review.newBadges.secondVisits');
eq(view.summary, '一句总结', 'review.summary');
eq(view.highlights.length, 1, 'review.highlights');

const emptyView: ReviewView = buildReview(t2, [], [], 0);
eq(emptyView.checkedTotal, 0, 'review.empty.checked');
eq(emptyView.newBadges.length, 0, 'review.empty.badges');
eq(emptyView.firstCheckedAt, 0, 'review.empty.first');
eq(emptyView.days[0].total, 1, 'review.empty.dayTotal');

const otherTrip: ReviewView = buildReview(t2, records, groups, 0);
eq(otherTrip.checkedTotal, 1, 'review.otherTrip.checked');
eq(otherTrip.newBadges.length, 0, 'review.otherTrip.repeatBadge');
eq(otherTrip.days[0].checked[0].arrival, false, 'review.otherTrip.arrival');

const pad: number = new Date(2026, 9, 20, 9, 5).getTime();
eq(reviewTimeText(pad), '09:05', 'review.timeText');

// ---------- 周年 ----------
const trips: AnniversaryTrip[] = [
  { id: 'old', destination: '北京', startDate: '2025-10-30', endDate: '2025-11-02' },
  { id: 'sameYear', destination: '上海', startDate: '2026-10-25', endDate: '2026-10-27' },
  { id: 'endingToday', destination: '广州', startDate: '2025-10-28', endDate: '2026-10-31' },
  { id: 'latest', destination: '深圳', startDate: '2025-10-31', endDate: '2025-10-31' }
];
const hit: AnniversaryTrip | null = findAnniversary(trips, '2026-10-31');
ok(hit !== null, 'anniversary.hit');
eq(hit!.id, 'latest', 'anniversary.latest');
eq(anniversaryText(hit!, '2026-10-31'), '去年的今天，你在深圳', 'anniversary.text');
eq(anniversaryText({ id: 'older', destination: '成都', startDate: '2024-10-31', endDate: '2024-10-31' },
  '2026-10-31'), '2024 年的今天，你在成都', 'anniversary.olderText');
eq(findAnniversary(trips, '2026-10-31') !== null, true, 'anniversary.repeatable');

const missSameYear: AnniversaryTrip | null =
  findAnniversary([{ id: 'sameYear', destination: '上海', startDate: '2026-10-25', endDate: '2026-10-27' }], '2026-10-31');
ok(missSameYear === null, 'anniversary.sameYearNull');

const wrap: AnniversaryTrip | null =
  findAnniversary([{ id: 'wrap', destination: '杭州', startDate: '2024-12-30', endDate: '2025-01-02' }], '2026-01-01');
ok(wrap !== null, 'anniversary.wrap');
eq(wrap!.id, 'wrap', 'anniversary.wrap.id');
eq(anniversaryText(wrap!, '2026-01-01'), '去年的今天，你在杭州', 'anniversary.wrap.text');

ok(findAnniversary(trips, '2026-02-30') === null, 'anniversary.invalidToday');
ok(findAnniversary([], '2026-10-31') === null, 'anniversary.empty');

// ---------- 城市套章 ----------
const sets: CitySpotSet[] = [
  { city: '北京', names: ['故宫博物院', '天坛公园', '颐和园', '八达岭长城'] },
  { city: '上海', names: ['外滩', '豫园'] }
];
const stampRecords: BadgeRecord[] = [
  rec('t1', 'a1', '故宫博物院', '北京', 1000, true),
  rec('t1', 'a2', ' 天坛公园 ', '北京', 2000, false),
  rec('t1', 'a9', '未收录景点', '北京', 2100, false),
  rec('t2', 'b1', '外滩', '上海', 3000, false),
  rec('t2', 'b2', '豫园', '上海', 3100, false),
  rec('t3', 'c1', '白云山', '广州', 3200, false)
];
const stampGroups: BadgeGroup[] = buildBadgeBoard(stampRecords);
const stamps: CityStamp[] = buildCityStamps(sets, stampGroups);
eq(stamps.length, 3, 'stamp.count');
const bj: CityStamp | null = stampOf(stamps, '北京');
ok(bj !== null, 'stamp.bj');
eq(bj!.collected, 2, 'stamp.bj.collected');
eq(bj!.total, 4, 'stamp.bj.total');
eq(bj!.complete, false, 'stamp.bj.complete');
eq(stampPercent(bj!), 50, 'stamp.bj.percent');
eq(stampMeta(bj!, 3), '2 / 4 枚', 'stamp.bj.meta');
const sh: CityStamp | null = stampOf(stamps, '上海');
ok(sh !== null, 'stamp.sh');
eq(sh!.collected, 2, 'stamp.sh.collected');
eq(sh!.complete, true, 'stamp.sh.complete');
eq(stampPercent(sh!), 100, 'stamp.sh.percent');
const gz: CityStamp | null = stampOf(stamps, '广州');
ok(gz !== null, 'stamp.gz');
eq(gz!.total, 0, 'stamp.gz.total');
eq(stampMeta(gz!, 1), '1 枚', 'stamp.gz.meta');
ok(stampOf(stamps, '成都') === null, 'stamp.missing');
ok(buildCityStamps([], stampGroups).length === 3, 'stamp.setsEmpty');
eq(buildCityStamps([], stampGroups)[0].total, 0, 'stamp.setsEmpty.total');

console.log(`PASS ${passed}/${passed}`);
