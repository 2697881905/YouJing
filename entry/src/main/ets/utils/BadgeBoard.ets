/**
 * 勋章墙的纯逻辑（禁依赖 @kit；可离线 tsc + 断言验证）。
 *
 * 口径：勋章从打卡证据派生，不新建表——checkin 自 v8 起就带 uuid / 时刻 / 坐标 / 来源，
 * 将来做同步也以它为凭。一枚章 = 「同一城市 + 同一景点名」的第一次打卡；同景点重复到访
 * 合并成一枚（记 visits），其中任一次是到站打卡就把这枚标成到站章。
 *
 * 餐次打卡没有 activity 行（其主键是派生 key `meal-day-type`），联表自然落在勋章之外；
 * 这里再按「查不到活动就丢弃」兜底，不靠调用方过滤。
 */

export interface BadgeRecord {
  /** `${tripId}:${activityId}`，与 activity 行主键同构 */
  id: string;
  tripId: string;
  spotName: string;
  city: string;
  tripStartDate: string;
  tripEndDate: string;
  /** 打卡时刻（epoch ms） */
  earnedAt: number;
  /** 该笔是否到站打卡（source='arrival'） */
  arrival: boolean;
  /** 该笔打卡时距站点的距离（m）；手动打卡为 0 */
  distanceM: number;
}

/** 合并后的勋章：同名同城只留一枚，earnedAt 取首次 */
export interface Badge {
  spotName: string;
  city: string;
  earnedAt: number;
  lastAt: number;
  visits: number;
  /** 任一次到站打卡即 true */
  arrival: boolean;
  /** 首次打卡所在的行程与活动，用来打开行程、也是「这枚章是不是本次收下」的判据 */
  firstCheckinId: string;
  firstTripId: string;
  tripStartDate: string;
  tripEndDate: string;
  /** 到站章里最小的一次到站距离（m）；无到站记录为 0 */
  distanceM: number;
}

export interface BadgeGroup {
  city: string;
  /** 按首次打卡时刻倒序 */
  badges: Badge[];
}

function norm(text: string): string {
  return text.trim().replace(/\s+/g, ' ');
}

/** 打卡记录 → 按城市分组的勋章墙；输入顺序无关，空输入返回空数组 */
export function buildBadgeBoard(rows: BadgeRecord[]): BadgeGroup[] {
  const merged: Map<string, Badge> = new Map<string, Badge>();
  for (const row of rows) {
    const name: string = norm(row.spotName);
    if (name.length === 0) {
      continue;
    }
    const key: string = `${row.city}\u0001${name}`;
    const existed: Badge | undefined = merged.get(key);
    if (existed === undefined) {
      const badge: Badge = {
        spotName: name, city: row.city, earnedAt: row.earnedAt, lastAt: row.earnedAt,
        visits: 1, arrival: row.arrival, firstCheckinId: row.id, firstTripId: row.tripId,
        tripStartDate: row.tripStartDate, tripEndDate: row.tripEndDate,
        distanceM: row.arrival ? row.distanceM : 0
      };
      merged.set(key, badge);
      continue;
    }
    existed.visits += 1;
    if (row.earnedAt < existed.earnedAt) {
      existed.earnedAt = row.earnedAt;
      existed.firstCheckinId = row.id;
      existed.firstTripId = row.tripId;
      existed.tripStartDate = row.tripStartDate;
      existed.tripEndDate = row.tripEndDate;
    }
    if (row.earnedAt > existed.lastAt) {
      existed.lastAt = row.earnedAt;
    }
    if (row.arrival) {
      existed.arrival = true;
      if (row.distanceM > 0 && (existed.distanceM <= 0 || row.distanceM < existed.distanceM)) {
        existed.distanceM = row.distanceM;
      }
    }
  }
  const byCity: Map<string, Badge[]> = new Map<string, Badge[]>();
  merged.forEach((badge: Badge, key: string): void => {
    const list: Badge[] | undefined = byCity.get(badge.city);
    if (list === undefined) {
      const created: Badge[] = [badge];
      byCity.set(badge.city, created);
    } else {
      list.push(badge);
    }
  });
  const groups: BadgeGroup[] = [];
  byCity.forEach((badges: Badge[], city: string): void => {
    badges.sort((a: Badge, b: Badge): number => b.earnedAt - a.earnedAt);
    const group: BadgeGroup = { city: city, badges: badges };
    groups.push(group);
  });
  groups.sort((a: BadgeGroup, b: BadgeGroup): number => {
    const aTop: number = a.badges.length > 0 ? a.badges[0].earnedAt : 0;
    const bTop: number = b.badges.length > 0 ? b.badges[0].earnedAt : 0;
    return bTop - aTop;
  });
  return groups;
}

/** 同城同名的一枚章；找不到返回 null（调用方据此决定要不要弹「收下」） */
export function findBadge(groups: BadgeGroup[], city: string, spotName: string): Badge | null {
  const name: string = norm(spotName);
  for (const group of groups) {
    if (group.city !== city) {
      continue;
    }
    for (const badge of group.badges) {
      if (badge.spotName === name) {
        return badge;
      }
    }
  }
  return null;
}

export function badgeTotal(groups: BadgeGroup[]): number {
  let n: number = 0;
  for (const group of groups) {
    n += group.badges.length;
  }
  return n;
}

export function badgeCityCount(groups: BadgeGroup[]): number {
  return groups.length;
}

/** 本地时区的「10月30日」；跨年补年份（2025年12月31日） */
export function badgeDateText(earnedAt: number): string {
  const d: Date = new Date(earnedAt);
  const month: number = d.getMonth() + 1;
  const day: number = d.getDate();
  const thisYear: number = new Date().getFullYear();
  const year: number = d.getFullYear();
  return year === thisYear ? `${month}月${day}日` : `${year}年${month}月${day}日`;
}

export function badgeSourceText(badge: Badge): string {
  return badge.arrival ? '到站打卡' : '手动打卡';
}

/** 行内说明：日期 · 来源 ·（重复到访时）到访次数 */
export function badgeMeta(badge: Badge): string {
  const head: string = `${badgeDateText(badge.earnedAt)} · ${badgeSourceText(badge)}`;
  return badge.visits > 1 ? `${head} · 到访 ${badge.visits} 次` : head;
}

/** 这枚章来自哪次行程：今天在行程区间内就进旅行中，否则进行程详情 */
export function badgeRoute(badge: Badge, todayIso: string): string {
  if (todayIso >= badge.tripStartDate && todayIso <= badge.tripEndDate) {
    return 'OnTrip';
  }
  return 'Itinerary';
}
