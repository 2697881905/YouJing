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
import { SelectedSpot, SpotPriority, PaceRule } from '../model/PlanParams';
import { Geo, GeoPoint } from './Geo';
import { Transit } from './Transit';
import { isMapArea } from './MapCityMapper';
import { DayLoadCalc } from './DayLoad';

/** 单日在场窗口 = 当日负载窗口（DayLoad 是这个口径的唯一持有者） */
const DAY_WINDOW_MIN: number = DayLoadCalc.WINDOW_MINUTES;
/** 两餐固定占用的分钟数，不给景点 */
const MEAL_MINUTES: number = 120;

/** 片区与到所选景点集合的平均直线距离（km） */
interface AreaDistance {
  area: Area;
  dist: number;
}

export class PlanAutoPick {
  /** 节奏 → 每天景点上限：唯一实现在 model/PlanParams 的 PaceRule，这里只是转发给调用方 */
  static dailyCap(pace: string): number {
    return PaceRule.dailyCap(pace);
  }

  /**
   * 单日在场窗口：直接取 utils/DayLoad 的当日负载窗口，不再各写一份 600。
   * 两处数字一旦漂移，屏2 会按 10 小时预选、屏8 却按别的窗口报「排太满」。
   */
  static readonly SINGLE_DAY_WINDOW_MIN: number = DAY_WINDOW_MIN;
  /** 窗口减去两餐固定占用，才是留给景点停留 + 往返通勤的预算 */
  static readonly SINGLE_DAY_SIGHT_BUDGET_MIN: number = DAY_WINDOW_MIN - MEAL_MINUTES;
  /** 单日候选池下限：一个远郊站就可能白占一个名额，池子要比上限宽 */
  static readonly SINGLE_DAY_POOL_MIN: number = 8;

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
   * 单日预选：从比上限更宽的候选池里，以住宿区为起点按「停留 + 往返通勤」预算
   * 逐个试装——**装不下就跳过这一站继续看下一站**，装够节奏档上限就停；
   * 全装不下时才保留首站。
   *
   * 两件事都是真机逼出来的（重庆 1 天，2026-10-31）：
   * · 不能从尾部砍——首候选是大足石刻（离渝中区约 120km，单站吃掉 490min），
   *   从尾部砍会把洪崖洞/磁器口这些同城景点全砍光，只剩一个远郊站；
   * · 池子不能只取上限——池子只有 4 个候选时，远郊站一占位就只剩 2 站；
   *   放宽到 8 个才排得出更多同城站。挑中的站数仍不超过节奏档，不替用户改节奏。
   */
  static pickSpotsForSingleDay(spots: Spot[], pace: string, tags: string[],
    area: Area | null): SelectedSpot[] {
    const cap: number = PlanAutoPick.dailyCap(pace);
    const ordered: Spot[] = PlanAutoPick.singleDayCandidates(spots, pace, tags);
    if (ordered.length <= 1) {
      return PlanAutoPick.toSelected(ordered, 1);
    }
    const origin: GeoPoint | null = area !== null && Geo.usable(area.latitude, area.longitude)
      ? { latitude: area.latitude, longitude: area.longitude } : null;
    const kept: Spot[] = [];
    for (const c of ordered) {
      if (kept.length >= cap) {
        break;
      }
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
    // 多日这句原来写「按每天 N 站预选 M 个」，读者会把它理解成「M = 天数 × N」的承诺；
    // 实际 N 只是节奏档**上限**，真正装得下几个受停留与通勤约束（见 pickSpotsForDays）。
    return `预选 ${picked.length} 个景点 · 每天 ≤${cap} 站 · 住宿区 ${areaName}`;
  }

  /**
   * 多日预选：按「每天实际装得下多少」收口，而不是 `天数 × 节奏上限` 一把切。
   *
   * 为什么要它：屏2 曾写「按每天 4 站预选 12 个景点」，而 12 站摊 3 天时**排不下**
   * （种子库停留是 4h/5h），实测三天各只落 2 站 ⇒ 6 站被静默丢弃，预选数量成了空头支票。
   * 名额上限仍是节奏档（不放松用户选的节奏），时间可行性是硬约束：装不下就不选它。
   *
   * 计费口径与 `pickSpotsForSingleDay` 同一套（停留 + 直线启发式通勤），差别只有预算：
   * 单日要扣两餐（480），多日不扣——生成器把餐次单列，`DayLoad` 只统活动与通勤，
   * 两边同一把尺。首站永远装（`placed === 0` 不设预算门），空白天比超载天更糟。
   */
  static pickSpotsForDays(spots: Spot[], dayCount: number, pace: string, tags: string[],
    area: Area | null): SelectedSpot[] {
    const days: number = Math.max(1, dayCount);
    const cap: number = PlanAutoPick.dailyCap(pace);
    const pool: Spot[] = PlanAutoPick.daysCandidates(spots, days, pace, tags);
    if (pool.length === 0) {
      return [];
    }
    const origin: GeoPoint | null = area !== null && Geo.usable(area.latitude, area.longitude)
      ? { latitude: area.latitude, longitude: area.longitude } : null;
    // 先把候选池按「就近成串」重排（同区域内连成一串），再做 N 搜索。
    // 只按热度排会把八达岭（离鼓楼 60km）排到第 2 位，把第 1 天直接撑爆，
    // 于是 N 只能收到 3——三天各一站，虽然可行但把行程做空了。
    // 重排的是**池子本身的顺序**，所以分块规则在预选与生成器两边仍然一致。
    const order: Spot[] = PlanAutoPick.clusterOrder(pool, origin);
    // 从候选池最大可用量往下试，取「按**生成器同一套分天规则**也装得下」的最大 N。
    // 必须模拟同一套 chunk 规则：预选自己按另一套分组、生成器再按 quota 切一次，
    // 两次分组一旦错位，同一批景点会被拆进不同天、通勤翻倍——2026-11-03 实测
    // 预选 8 站、生成器排 6 站，且 D2/D3 各 15.4h（超建议 5.4h）。
    for (let n = order.length; n > 0; n--) {
      if (PlanAutoPick.daysFit(order, n, days, cap, origin)) {
        return PlanAutoPick.toSelected(order.slice(0, n), Math.min(days, n));
      }
    }
    return [];
  }

  /**
   * 就近成串：从住宿区出发，每次取「离上一站最近」的候选（同距离时保留原有热度顺序）。
   *
   * 这样同一片区的景点会连在一起，按天切开时每一天都在小范围内活动；
   * 远郊站（八达岭这类）要么和同向的站成串，要么自然落到最后。
   */
  private static clusterOrder(pool: Spot[], origin: GeoPoint | null): Spot[] {
    const ordered: Spot[] = [];
    const used: boolean[] = [];
    for (let i = 0; i < pool.length; i++) {
      used.push(false);
    }
    let prev: GeoPoint | null = origin;
    while (ordered.length < pool.length) {
      let best: number = -1;
      let bestLeg: number = 0;
      for (let i = 0; i < pool.length; i++) {
        if (used[i]) {
          continue;
        }
        const leg: number = PlanAutoPick.legMinutes(prev, PlanAutoPick.pointOf(pool[i]));
        if (best < 0 || leg < bestLeg) {
          best = i;
          bestLeg = leg;
        }
      }
      used[best] = true;
      ordered.push(pool[best]);
      prev = PlanAutoPick.pointOf(pool[best]);
    }
    return ordered;
  }

  /**
   * 把前 n 个候选按生成器的分天规则切开，逐天核算「停留 + 通勤」是否落在窗口内。
   *
   * 生成器每天首站不算腿（当日第一段路无从算起），这里对每天首站**也**算一段到住宿区的腿
   * ——预选比实排更严是安全的方向：严出来的差值只会让实排更松，不会反过来超窗。
   */
  private static daysFit(pool: Spot[], n: number, days: number, cap: number,
    origin: GeoPoint | null): boolean {
    let cursor: number = 0;
    for (let d = 0; d < days; d++) {
      const left: number = n - cursor;
      if (left <= 0) {
        return true;
      }
      const quota: number = Math.max(1, Math.min(cap, Math.ceil(left / (days - d))));
      let load: number = 0;
      let prev: GeoPoint | null = origin;
      for (let k = 0; k < quota && cursor < n; k++) {
        const s: Spot = pool[cursor];
        const point: GeoPoint | null = PlanAutoPick.pointOf(s);
        load += s.suggestedDuration + PlanAutoPick.legMinutes(prev, point);
        prev = point;
        cursor += 1;
      }
      if (load > DAY_WINDOW_MIN) {
        return false;
      }
    }
    return true;
  }

  /** 多日候选池：名额的 2 倍，给「远站吃预算被跳过」留余量（单日池同理由） */
  static daysCandidates(spots: Spot[], dayCount: number, pace: string, tags: string[]): Spot[] {
    const pool: number = Math.max(1, dayCount) * PlanAutoPick.dailyCap(pace) * 2;
    return PlanAutoPick.orderedCandidates(spots, tags).slice(0, Math.min(spots.length, pool));
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

  /**
   * 单日候选池：`max(8, 2×节奏上限)` 个，按优先级排好。
   * 既是要装的名的 2 倍，也是给调用方打「丢了几站、为什么」轨迹日志的同一份清单。
   */
  static singleDayCandidates(spots: Spot[], pace: string, tags: string[]): Spot[] {
    const pool: number = Math.max(PlanAutoPick.SINGLE_DAY_POOL_MIN,
      PlanAutoPick.dailyCap(pace) * 2);
    return PlanAutoPick.orderedCandidates(spots, tags).slice(0, Math.min(spots.length, pool));
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
    // 与离线合成的通勤段同一口径（utils/Transit）：预选说装得下、生成器就必须排得下
    return Transit.minutes(a, b);
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
