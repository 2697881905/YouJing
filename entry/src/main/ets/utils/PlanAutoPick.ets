/**
 * 一句话成行程的自动预选（纯函数，不碰 @kit，可离线断言）。
 *
 * 自动选点不是新规则：名额与屏3b 的节奏档一一对应（轻松3/标准4/紧凑6），
 * 排序退回屏4 的默认口径（热度降序），兴趣标签只做前置加权；
 * 住宿区退回屏5「帮我选」的平均直线距离口径。这样「直接生成」得到的行程
 * 与用户手工走完四屏选出来的是同一套规则，不会出现第二条暗规则。
 */

import { Spot, SpotTag } from '../model/Spot';
import { Area, AreaPriceTier } from '../model/Area';
import { SelectedSpot, SpotPriority, PaceOption } from '../model/PlanParams';
import { Geo, GeoPoint } from './Geo';

export class PlanAutoPick {
  /** 节奏 → 每天景点上限；与 LlmClient 的 capOf 同源口径 */
  static dailyCap(pace: string): number {
    if (pace === PaceOption.RELAXED) {
      return 3;
    }
    return pace === PaceOption.PACKED ? 6 : 4;
  }

  /**
   * 选 N = 天数 × 每日上限 个景点：命中所选标签的按热度优先排前面，
   * 其余按热度补齐；前 min(天数, N) 个标「必去」，保证每天至少有一站是强推荐。
   */
  static pickSpots(spots: Spot[], dayCount: number, pace: string, tags: string[]): SelectedSpot[] {
    const days: number = Math.max(1, dayCount);
    const want: number = Math.min(spots.length, days * PlanAutoPick.dailyCap(pace));
    if (want <= 0) {
      return [];
    }
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
    const ordered: Spot[] = matched.concat(rest).slice(0, want);
    const mustCount: number = Math.min(days, ordered.length);
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

  /**
   * 按价格档位收候选，再取到景点平均直线距离最近的一片。
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

  /** 候选里到 targets 平均距离最近的一片；无可算候选返回 null */
  static nearestArea(areas: Area[], targets: GeoPoint[]): Area | null {
    if (areas.length === 0) {
      return null;
    }
    const usable: Area[] = [];
    const points: GeoPoint[] = [];
    for (const a of areas) {
      if (Geo.usable(a.latitude, a.longitude)) {
        usable.push(a);
        const p: GeoPoint = { latitude: a.latitude, longitude: a.longitude };
        points.push(p);
      }
    }
    if (targets.length === 0 || usable.length === 0) {
      return null;
    }
    const at: number = Geo.argminMean(points, targets);
    return at < 0 ? null : usable[at];
  }

  /** 预选结果的一句理由；空结果也要说明为什么空 */
  static describe(picked: SelectedSpot[], area: Area | null, dayCount: number, pace: string): string {
    if (picked.length === 0) {
      return '这座城市还没有可预选的景点';
    }
    const cap: number = PlanAutoPick.dailyCap(pace);
    const areaName: string = area !== null ? area.name : '未定';
    return `按每天 ${cap} 站预选 ${picked.length} 个景点 · 住宿区 ${areaName}`;
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
