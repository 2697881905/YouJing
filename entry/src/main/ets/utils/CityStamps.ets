/**
 * 城市套章的纯逻辑（禁依赖 @kit；可离线 tsc + 断言验证）。
 *
 * 「套」的定义不做阈值暗规则：一座城市的套 = 该城种子景点全集（北京/上海/广州/深圳各 32、
 * 杨凌 10）。集齐整套才算城市套章；进度只统计名字精确落在该城种子里的景点章，
 * 名字对不上（AI 改写过标题、非种子节点）的章仍留在勋章墙，但不冒充套章进度。
 *
 * 不建表：套章完全由打卡证据派生的勋章组 + 只读的种子景点名现算。
 */

import { BadgeGroup } from './BadgeBoard';

/** 一座城市的种子景点名（只读快照） */
export interface CitySpotSet {
  city: string;
  names: string[];
}

export interface CityStamp {
  city: string;
  /** 名字命中种子景点的勋章数 */
  collected: number;
  /** 种子景点总数；0 表示没有该城数据，进度不可算 */
  total: number;
  complete: boolean;
}

function norm(text: string): string {
  return text.trim().replace(/\s+/g, ' ');
}

/** 勋章组 + 种子名 → 每座已到访城市的套章进度；顺序跟随勋章组（最近收章的城市在前） */
export function buildCityStamps(sets: CitySpotSet[], groups: BadgeGroup[]): CityStamp[] {
  const wanted: Map<string, Set<string>> = new Map<string, Set<string>>();
  for (const set of sets) {
    let bucket: Set<string> | undefined = wanted.get(set.city);
    if (bucket === undefined) {
      bucket = new Set<string>();
      wanted.set(set.city, bucket);
    }
    for (const name of set.names) {
      const key: string = norm(name);
      if (key.length > 0) {
        bucket.add(key);
      }
    }
  }

  const out: CityStamp[] = [];
  for (const group of groups) {
    const names: Set<string> | undefined = wanted.get(group.city);
    if (names === undefined || names.size === 0) {
      const unknown: CityStamp = { city: group.city, collected: 0, total: 0, complete: false };
      out.push(unknown);
      continue;
    }
    const have: Set<string> = new Set<string>();
    for (const badge of group.badges) {
      have.add(norm(badge.spotName));
    }
    let collected: number = 0;
    names.forEach((name: string): void => {
      if (have.has(name)) {
        collected += 1;
      }
    });
    const stamp: CityStamp = {
      city: group.city, collected: collected, total: names.size,
      complete: collected >= names.size
    };
    out.push(stamp);
  }
  return out;
}

/** 按城市取套章进度；没有该城数据或未到访返回 null */
export function stampOf(stamps: CityStamp[], city: string): CityStamp | null {
  for (const stamp of stamps) {
    if (stamp.city === city) {
      return stamp;
    }
  }
  return null;
}

/** 进度百分比（0~100）；无数据的城市返回 0 */
export function stampPercent(stamp: CityStamp): number {
  if (stamp.total <= 0) {
    return 0;
  }
  return Math.min(100, Math.round((stamp.collected / stamp.total) * 100));
}

/** 组头文案：有数据时「3 / 32 枚」，无数据时退回「3 枚」 */
export function stampMeta(stamp: CityStamp | null, badgeCount: number): string {
  if (stamp === null || stamp.total <= 0) {
    return `${badgeCount} 枚`;
  }
  return `${stamp.collected} / ${stamp.total} 枚`;
}
