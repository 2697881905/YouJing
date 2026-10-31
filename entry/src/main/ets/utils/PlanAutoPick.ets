/**
 * 一句话成行程的自动预选（纯函数，不碰 @kit，可离线断言）。
 *
 * 自动选点不是新规则：名额与屏3b 的节奏档一一对应（轻松3/标准4/紧凑6），
 * 排序退回屏4 的默认口径（热度降序），兴趣标签只做前置加权；
 * 住宿区与屏5 列表共用 rankAreas 一条规则（地图区县按酒店供给、种子片区按平均距离），
 * 这样「直接生成」得到的行程
 * 与用户手工走完四屏选出来的是同一套规则，不会出现第二条暗规则。
 */

import { Spot, SpotTag } from '../model/Spot';
import { Area, AreaPriceTier } from '../model/Area';
import { SelectedSpot, SpotPriority, PaceOption } from '../model/PlanParams';
import { Geo, GeoPoint } from './Geo';
import { isMapArea } from './MapCityMapper';

/** 片区与到所选景点集合的平均直线距离（km） */
interface AreaDistance {
  area: Area;
  dist: number;
}

export class PlanAutoPick {
  /** 节奏 → 每天景点上限；与 LlmClient 的 capOf 同源口径 */
  static dailyCap(pace: string): number {
    if (pace === PaceOption.RELAXED) {
      return 3;
    }
    return pace === PaceOption.PACKED ? 6 : 4;
  }

  /** 单日建议在场窗口，与 utils/DayLoad.WINDOW_MINUTES 同源（600min） */
  static readonly SINGLE_DAY_WINDOW_MIN: number = 600;
  /** 600min 窗口 − 120min 两餐，留给景点停留 + 往返通勤 */
  static readonly SINGLE_DAY_SIGHT_BUDGET_MIN: number = 480;

  /**
   * 选 N = 天数 × 每日上限 个景点：命中所选标签的按热度优先排前面，
   * 其余按热度补齐；前 min(天数, N) 个标「必去」，保证每天至少有一站是强推荐。
   * 单日请走 pickSpotsForSingleDay：它会把通勤吃掉的时长也算进名额。
   */
  static pickSpots(spots: Spot[], dayCount: number, pace: string, tags: string[]): SelectedSpot[] {
    const days: number = Math.max(1, dayCount);
    const want: number = Math.min(spots.length, days * PlanAutoPick.dailyCap(pace));
    if (want <= 0) {
      return [];
    }
    const ordered: Spot[] = PlanAutoPick.orderedCandidates(spots, tags).slice(0, want);
    return PlanAutoPick.toSelected(ordered, Math.min(days, ordered.length));
  }

  /**
   * 单日预选：先按节奏上限取候选，再以住宿区为起点估算「停留 + 往返通勤」，
   * 按优先级逐个试装——**装不下就跳过这一站继续看下一站**，全装不下时才保留首站。
   *
   * 不能从尾部砍：重庆 1 天实测（2026-10-31）首候选是大足石刻（离渝中区约 120km，
   * 单站吃掉 490min），从尾部砍会把洪崖洞/磁器口这些同城景点全砍光，只剩一个远郊站。
   * 一天的行程该是一个片区，不是「全国最出名的那个 POI 在哪就去哪」。
   */
  static pickSpotsForSingleDay(spots: Spot[], pace: string, tags: string[],
    area: Area | null): SelectedSpot[] {
    const cap: number = PlanAutoPick.dailyCap(pace);
    const ordered: Spot[] = PlanAutoPick.orderedCandidates(spots, tags)
      .slice(0, Math.min(spots.length, cap));
    if (ordered.length <= 1) {
      return PlanAutoPick.toSelected(ordered, 1);
    }
    const origin: GeoPoint | null = area !== null && Geo.usable(area.latitude, area.longitude)
      ? { latitude: area.latitude, longitude: area.longitude } : null;
    const kept: Spot[] = [];
    for (const c of ordered) {
      const trial: Spot[] = kept.concat([c]);
      if (PlanAutoPick.routeMinutes(trial, origin) <= PlanAutoPick.SINGLE_DAY_SIGHT_BUDGET_MIN) {
        kept.push(c);
      }
    }
    if (kept.length === 0) {
      kept.push(ordered[0]);
    }
    return PlanAutoPick.toSelected(kept, 1);
  }

  /**
   * 按价格档位收候选，再取 rankAreas 的第一片。
   * 档位无候选时退回全量（不因为「舒适」没铺满而让用户无区可选）；
   * 片区或景点都缺坐标时退回候选首位，保持种子库顺序。
   */
  static pickArea(areas: Area[], spots: Spot[], selected: SelectedSpot[], stayTier: string): Area | null {
    if (areas.length === 0) {
      return null;
    }
    let candidates: Area[] = areas;
    if (stayTier.length > 0) {
      const tiered: Area[] = areas.filter((a: Area): boolean => a.priceTier === stayTier);
      if (tiered.length > 0) {
        candidates = tiered;
      }
    }
    const points: GeoPoint[] = PlanAutoPick.spotPoints(spots, selected);
    const nearest: Area | null = PlanAutoPick.nearestArea(candidates, points);
    return nearest !== null ? nearest : candidates[0];
  }

  /**
   * 住宿区统一排序——屏5 列表与屏2 预选共用这一条，避免两边各排一次给出不同第一名。
   * · 地图区县：入参顺序本身就是酒店供给降序，那是我们最强的「适合住」信号，不再按距离重排。
   *   丽江实测（2026-10-31）：按平均距离重排会把 139 家酒店的玉龙县城顶到
   *   467 家酒店的古城区前面，而游客住的是古城区。
   * · 种子片区：没有住宿库存，只能按到所选景点的平均直线距离升序；缺坐标的排最后。
   * 没有景点坐标时原样返回——不把「算不出距离」当成「最近」。
   */
  static rankAreas(areas: Area[], targets: GeoPoint[]): Area[] {
    if (areas.length === 0 || targets.length === 0 || isMapArea(areas[0])) {
      return areas;
    }
    const withDist: AreaDistance[] = [];
    const noGeo: Area[] = [];
    for (const a of areas) {
      if (Geo.usable(a.latitude, a.longitude)) {
        const g: GeoPoint = { latitude: a.latitude, longitude: a.longitude };
        withDist.push({ area: a, dist: Geo.meanDistanceKm(g, targets) });
      } else {
        noGeo.push(a);
      }
    }
    withDist.sort((x: AreaDistance, y: AreaDistance): number => x.dist - y.dist);
    const ranked: Area[] = [];
    for (const w of withDist) {
      ranked.push(w.area);
    }
    return ranked.concat(noGeo);
  }

  /** 排序后的第一片；无候选、无坐标或没有景点坐标时返回 null，由调用方决定回退口径 */
  static nearestArea(areas: Area[], targets: GeoPoint[]): Area | null {
    if (areas.length === 0 || targets.length === 0) {
      return null;
    }
    const ranked: Area[] = PlanAutoPick.rankAreas(areas, targets);
    for (const a of ranked) {
      if (Geo.usable(a.latitude, a.longitude)) {
        return a;
      }
    }
    return null;
  }

  /** 预选结果的一句理由；空结果也要说明为什么空 */
  static describe(picked: SelectedSpot[], area: Area | null, dayCount: number, pace: string): string {
    if (picked.length === 0) {
      return '这座城市还没有可预选的景点';
    }
    const cap: number = PlanAutoPick.dailyCap(pace);
    const areaName: string = area !== null ? area.name : '未定';
    if (dayCount === 1) {
      return `按单日 ${PlanAutoPick.SINGLE_DAY_WINDOW_MIN / 60} 小时窗口预选 ` +
        `${picked.length} 个景点 · 住宿区 ${areaName}`;
    }
    return `按每天 ${cap} 站预选 ${picked.length} 个景点 · 住宿区 ${areaName}`;
  }

  /** 标签命中的按热度优先，其余按热度补齐 */
  private static orderedCandidates(spots: Spot[], tags: string[]): Spot[] {
    const matched: Spot[] = [];
    const rest: Spot[] = [];
    for (const s of spots) {
      if (tags.length > 0 && PlanAutoPick.hasTag(s, tags)) {
        matched.push(s);
      } else {
        rest.push(s);
      }
    }
    PlanAutoPick.sortByPopularity(matched);
    PlanAutoPick.sortByPopularity(rest);
    return matched.concat(rest);
  }

  private static toSelected(ordered: Spot[], mustCount: number): SelectedSpot[] {
    const picked: SelectedSpot[] = [];
    for (let i = 0; i < ordered.length; i++) {
      const p: SelectedSpot = {
        spotId: ordered[i].id,
        priority: i < mustCount ? SpotPriority.MUST : SpotPriority.WANT
      };
      picked.push(p);
    }
    return picked;
  }

  /** 估算「住宿区 → 各站 → 住宿区」的停留 + 通勤总分钟数 */
  static routeMinutesOf(ordered: Spot[], area: Area | null): number {
    const origin: GeoPoint | null = area !== null && Geo.usable(area.latitude, area.longitude)
      ? { latitude: area.latitude, longitude: area.longitude } : null;
    return PlanAutoPick.routeMinutes(ordered, origin);
  }

  /** 单日收口的候选清单（未截断），供调用方打「丢了几站、为什么」的轨迹日志 */
  static singleDayCandidates(spots: Spot[], pace: string, tags: string[]): Spot[] {
    return PlanAutoPick.orderedCandidates(spots, tags)
      .slice(0, Math.min(spots.length, PlanAutoPick.dailyCap(pace)));
  }

  private static routeMinutes(ordered: Spot[], origin: GeoPoint | null): number {
    let total: number = 0;
    let prev: GeoPoint | null = origin;
    for (const s of ordered) {
      total += s.suggestedDuration;
      const point: GeoPoint | null = PlanAutoPick.pointOf(s);
      total += PlanAutoPick.legMinutes(prev, point);
      prev = point;
    }
    total += PlanAutoPick.legMinutes(prev, origin);
    return total;
  }

  private static pointOf(s: Spot): GeoPoint | null {
    if (!Geo.usable(s.latitude, s.longitude)) {
      return null;
    }
    const p: GeoPoint = { latitude: s.latitude, longitude: s.longitude };
    return p;
  }

  /**
   * 直线距离 * 1.2 道路系数 / 30km/h 平均时速 + 8min 等车；
   * 缺坐标的腿按 15min 估，宁可多算不漏算。
   */
  private static legMinutes(a: GeoPoint | null, b: GeoPoint | null): number {
    if (a === null && b === null) {
      return 0;
    }
    if (a === null || b === null) {
      return 15;
    }
    if (!Geo.usable(a.latitude, a.longitude) || !Geo.usable(b.latitude, b.longitude)) {
      return 15;
    }
    const km: number = Geo.distanceKm(a, b);
    return Math.round(km * 1.2 / 30 * 60) + 8;
  }

  private static hasTag(s: Spot, tags: string[]): boolean {
    for (const t of s.tags) {
      if (tags.indexOf(t) >= 0) {
        return true;
      }
    }
    return false;
  }

  private static sortByPopularity(list: Spot[]): void {
    list.sort((a: Spot, b: Spot): number => {
      if (b.popularity !== a.popularity) {
        return b.popularity - a.popularity;
      }
      return a.id < b.id ? -1 : (a.id > b.id ? 1 : 0);
    });
  }

  private static spotPoints(spots: Spot[], selected: SelectedSpot[]): GeoPoint[] {
    const points: GeoPoint[] = [];
    for (const sel of selected) {
      for (const s of spots) {
        if (s.id === sel.spotId && Geo.usable(s.latitude, s.longitude)) {
          const p: GeoPoint = { latitude: s.latitude, longitude: s.longitude };
          points.push(p);
        }
      }
    }
    return points;
  }
}

/** 屏2 预览与屏5 展示共用的档位文案（避免两处各写一套中文） */
export function tierLabel(tier: string): string {
  if (tier === AreaPriceTier.ECONOMY) {
    return '经济';
  }
  if (tier === AreaPriceTier.LUXURY) {
    return '豪华';
  }
  return '舒适';
}

/** 标签 → 屏4 展示文案（四个封闭值，未知返回空串） */
export function tagLabel(tag: string): string {
  if (tag === SpotTag.MUST_SEE) {
    return '必去';
  }
  if (tag === SpotTag.CLASSIC) {
    return '经典';
  }
  if (tag === SpotTag.NICHE) {
    return '小众';
  }
  return tag === SpotTag.FAMILY ? '亲子' : '';
}
