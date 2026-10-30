/**
 * 行后回顾的纯逻辑（禁依赖 @kit；可离线 tsc + 断言验证）。
 *
 * 口径：回顾不是第二份真相——打卡取 checkin 证据（BadgeRecord），
 * 勋章取勋章墙的合并结果（谁第一次收下这枚章），花费取 expense 合计，
 * 节点与日期取 trip 聚合根本身。任何一项缺失都如实留空，不编造。
 *
 * 餐次打卡（派生主键 `meal-{day}-{type}`）没有 activity 行，与勋章同口径不进回顾；
 * 这里按「活动 id 在行程里找不到就丢弃」兜底，不靠调用方过滤。
 */

import { Trip } from '../model/Trip';
import { Badge, BadgeGroup, BadgeRecord } from './BadgeBoard';
import { DateUtils } from './DateUtils';

export interface ReviewItem {
  activityId: string;
  /** 行程里排定的时刻（HH:mm），不是打卡时刻 */
  time: string;
  title: string;
  /** 实际打卡时刻（epoch ms） */
  checkedAt: number;
  /** 到站打卡（有位置凭证） */
  arrival: boolean;
}

export interface ReviewDay {
  dayIndex: number;
  date: string;
  theme: string;
  /** 当天排定的活动总数 */
  total: number;
  /** 当天真实打卡过的活动，按行程排期顺序 */
  checked: ReviewItem[];
}

export interface ReviewView {
  tripId: string;
  city: string;
  startDate: string;
  endDate: string;
  dayCount: number;
  people: number;
  /** 全行程排定的活动总数 */
  spotTotal: number;
  /** 真实打卡的活动数 */
  checkedTotal: number;
  /** 其中带位置凭证的到站打卡数 */
  arrivalTotal: number;
  /** 本次行程第一次收下的章（同名同城跨行程合并后） */
  newBadges: Badge[];
  /** 本行程记账合计（元）；0 表示没有记账，不代表没花钱 */
  expenseTotal: number;
  /** 首次/末次打卡时刻；无打卡为 0 */
  firstCheckedAt: number;
  lastCheckedAt: number;
  days: ReviewDay[];
  summary: string;
  highlights: string[];
}

/** 只用于周年命中的最小行程字段（避免 utils 反向依赖 data 层） */
export interface AnniversaryTrip {
  id: string;
  destination: string;
  startDate: string;
  endDate: string;
}

function activityIdOf(record: BadgeRecord): string {
  const prefix: string = `${record.tripId}:`;
  return record.id.startsWith(prefix) ? record.id.substring(prefix.length) : record.id;
}

/**
 * 行程 + 打卡证据 + 勋章墙 + 花费合计 → 回顾视图。输入顺序无关，缺数据不抛错。
 */
export function buildReview(trip: Trip, records: BadgeRecord[], groups: BadgeGroup[],
  expenseTotal: number): ReviewView {
  const realIds: Set<string> = new Set<string>();
  for (const day of trip.days) {
    for (const act of day.activities) {
      realIds.add(act.id);
    }
  }
  const byActivity: Map<string, BadgeRecord> = new Map<string, BadgeRecord>();
  for (const record of records) {
    if (record.tripId !== trip.id) {
      continue;
    }
    const activityId: string = activityIdOf(record);
    if (!realIds.has(activityId)) {
      continue;
    }
    byActivity.set(activityId, record);
  }

  const days: ReviewDay[] = [];
  let spotTotal: number = 0;
  let checkedTotal: number = 0;
  let arrivalTotal: number = 0;
  let firstCheckedAt: number = 0;
  let lastCheckedAt: number = 0;
  for (const day of trip.days) {
    const checked: ReviewItem[] = [];
    for (const act of day.activities) {
      const record: BadgeRecord | undefined = byActivity.get(act.id);
      if (record === undefined) {
        continue;
      }
      const item: ReviewItem = {
        activityId: act.id,
        time: act.time,
        title: act.title,
        checkedAt: record.earnedAt,
        arrival: record.arrival
      };
      checked.push(item);
      checkedTotal += 1;
      if (record.arrival) {
        arrivalTotal += 1;
      }
      if (firstCheckedAt === 0 || record.earnedAt < firstCheckedAt) {
        firstCheckedAt = record.earnedAt;
      }
      if (record.earnedAt > lastCheckedAt) {
        lastCheckedAt = record.earnedAt;
      }
    }
    spotTotal += day.activities.length;
    const view: ReviewDay = {
      dayIndex: day.dayIndex, date: day.date, theme: day.theme,
      total: day.activities.length, checked: checked
    };
    days.push(view);
  }

  const newBadges: Badge[] = [];
  for (const group of groups) {
    for (const badge of group.badges) {
      if (badge.firstTripId !== trip.id) {
        continue;
      }
      // 首次打卡的节点可能已被用户从行程里删掉：这类孤儿证据不进回顾，
      // 否则海报上会多出一枚点不开的章
      const prefix: string = `${trip.id}:`;
      const firstActId: string = badge.firstCheckinId.startsWith(prefix)
        ? badge.firstCheckinId.substring(prefix.length) : badge.firstCheckinId;
      if (!byActivity.has(firstActId)) {
        continue;
      }
      newBadges.push(badge);
    }
  }
  newBadges.sort((a: Badge, b: Badge): number => a.earnedAt - b.earnedAt);

  const review: ReviewView = {
    tripId: trip.id,
    city: trip.destination,
    startDate: trip.startDate,
    endDate: trip.endDate,
    dayCount: trip.days.length,
    people: trip.people,
    spotTotal: spotTotal,
    checkedTotal: checkedTotal,
    arrivalTotal: arrivalTotal,
    newBadges: newBadges,
    expenseTotal: expenseTotal,
    firstCheckedAt: firstCheckedAt,
    lastCheckedAt: lastCheckedAt,
    days: days,
    summary: trip.overview.summary,
    highlights: trip.overview.highlights
  };
  return review;
}

/** 打卡时刻 → 本地 HH:mm（回顾时间线里与排定时刻区分开） */
export function reviewTimeText(epochMs: number): string {
  const d: Date = new Date(epochMs);
  const h: string = `${d.getHours()}`.padStart(2, '0');
  const m: string = `${d.getMinutes()}`.padStart(2, '0');
  return `${h}:${m}`;
}

/**
 * 「去年的今天」命中：取今天月日落在某条**已结束且跨年**行程区间内的最近一条。
 *
 * 用月日比较而不是把行程平移整年：跨年行程（12-30 → 01-02）平移后区间会倒挂，
 * 月日比较天然支持环绕。结束日 ≥ 今天的不算——还在旅途中或刚结束当天，
 * 不该被叫成「去年」。
 */
export function findAnniversary(trips: AnniversaryTrip[], todayIso: string): AnniversaryTrip | null {
  if (!DateUtils.isValidIsoDate(todayIso)) {
    return null;
  }
  const todayMd: string = todayIso.substring(5);
  const todayYear: number = Number(todayIso.substring(0, 4));
  let best: AnniversaryTrip | null = null;
  for (const trip of trips) {
    if (!DateUtils.isValidIsoDate(trip.startDate) || !DateUtils.isValidIsoDate(trip.endDate)) {
      continue;
    }
    if (trip.endDate >= todayIso) {
      continue;
    }
    if (Number(trip.startDate.substring(0, 4)) >= todayYear) {
      continue;
    }
    const startMd: string = trip.startDate.substring(5);
    const endMd: string = trip.endDate.substring(5);
    const hit: boolean = startMd <= endMd
      ? (todayMd >= startMd && todayMd <= endMd)
      : (todayMd >= startMd || todayMd <= endMd);
    if (!hit) {
      continue;
    }
    if (best === null || trip.startDate > best.startDate) {
      best = trip;
    }
  }
  return best;
}

/** 周年横幅文案：去年的今天 / 2024 年的今天（跨年行程按今天落在的那一段年份算） */
export function anniversaryText(trip: AnniversaryTrip, todayIso: string): string {
  const todayYear: number = Number(todayIso.substring(0, 4));
  const startYear: number = Number(trip.startDate.substring(0, 4));
  const startMd: string = trip.startDate.substring(5);
  const endMd: string = trip.endDate.substring(5);
  const todayMd: string = todayIso.substring(5);
  // 12-30 → 01-02 这类跨年行程：今天落在尾段时应算到次年，不能念成「2024 年」
  const year: number = (startMd > endMd && todayMd <= endMd) ? startYear + 1 : startYear;
  return todayYear - year === 1
    ? `去年的今天，你在${trip.destination}`
    : `${year} 年的今天，你在${trip.destination}`;
}
