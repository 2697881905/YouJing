/**
 * 行程回填（纯逻辑，可离线断言）。
 *
 * 为什么要有这一步：真模型会把景点地址整段重写一遍（「北京市延庆区八达岭镇八达岭长城景区」），
 * 而这些字段**景点库里本来就有**——模型重写既烧输出 token（按 token 计费的那一刀），
 * 又引入"写错地址"的幻觉面。所以提示词侧要求它留空，落库前由这里按库回填真值。
 *
 * 匹配口径：先精确同名，再退到"一方完整包含另一方"（模型常加「北门」「景区」这类后缀）。
 * 匹配不上就**原样保留**模型给的值，不做二次猜测——宁缺勿假。
 */

import { Spot } from '../model/Spot';
import { Activity, ActivityCategory, Trip } from '../model/Trip';

/** 名称归一：去掉空白与常见连接符，让「八达岭长城景区」能对上「八达岭长城」 */
function normalize(name: string): string {
  return name.replace(/[\s·\-—()（）】】【]/g, '');
}

/** 找该活动对应的景点；返回 undefined 表示库里没有可回填的真值 */
function matchSpot(act: Activity, spots: Spot[]): Spot | undefined {
  const key: string = normalize(act.title);
  if (key.length === 0) {
    return undefined;
  }
  for (const s of spots) {
    if (normalize(s.name) === key) {
      return s;
    }
  }
  for (const s of spots) {
    const n: string = normalize(s.name);
    if (n.length < 2) {
      continue;
    }
    if (key.indexOf(n) >= 0 || n.indexOf(key) >= 0) {
      return s;
    }
  }
  return undefined;
}

/**
 * 回填活动的坐标与地址。
 * 只覆盖"模型留空或留零"的字段吗？不是——**匹配上就以库为准覆盖**，
 * 因为库是溯源过的真值，模型写的那份即使非空也不可信。
 * 返回被回填的活动条数（屏6 日志与用量对照要用）。
 */
export function backfillActivityPlaces(trip: Trip, spots: Spot[]): number {
  let filled: number = 0;
  const city: string = trip.destination;
  for (const day of trip.days) {
    for (const act of day.activities) {
      const spot: Spot | undefined = matchSpot(act, spots);
      if (spot === undefined) {
        continue;
      }
      act.longitude = spot.longitude;
      act.latitude = spot.latitude;
      const addr: string = spot.city.length > 0 && spot.district.length > 0
        ? `${spot.city} ${spot.district}` : spot.district;
      if (addr.length > 0) {
        act.address = addr;
      }
      filled += 1;
    }
  }
  // 库里没有对应景点（模型自己加的活动，如「午餐：杨凌蘸水面」）时，
  // 地址至少给到目的地，屏8 的 meta 行不留空
  for (const day of trip.days) {
    for (const act of day.activities) {
      if (act.address.length === 0 && city.length > 0) {
        act.address = city;
      }
    }
  }
  return filled;
}

/**
 * 把 MapKit 景点的「每日一致开放时段」写进对应 sight 活动的 note。
 * 只处理 category=sight；餐次/交通/酒店不写。note 已有同一时段时不重复追加。
 * 返回被写入的活动条数。
 */
export function backfillOpeningHours(trip: Trip, spots: Spot[]): number {
  let filled: number = 0;
  for (const day of trip.days) {
    for (const act of day.activities) {
      if (act.category !== ActivityCategory.SIGHT) {
        continue;
      }
      const spot: Spot | undefined = matchSpot(act, spots);
      if (spot === undefined || spot.openingHours === undefined || spot.openingHours.length === 0) {
        continue;
      }
      if (act.note !== undefined && act.note.indexOf(spot.openingHours) >= 0) {
        continue;
      }
      const hours: string = `开放 ${spot.openingHours}`;
      act.note = act.note !== undefined && act.note.length > 0 ? `${act.note} · ${hours}` : hours;
      filled += 1;
    }
  }
  return filled;
}
