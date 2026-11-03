import { Geo, GeoPoint } from './Geo';

/**
 * 站点之间「怎么去、要多久」的唯一估算口径。
 *
 * 收成一处的原因：预选（`PlanAutoPick`）按真实直线距离算通勤来收口名额，
 * 而离线合成（`MockLlmTransport`）此前给**每一段**都写死「地铁 22 分钟 · 2 站」——
 * 中关村到八达岭 60km 与故宫到景山 1km 报的是同一句话。两边口径一分叉，
 * 预选说装得下、生成器排出来又是另一回事（2026-11-03 就是 12 站预选只排出 6 站）。
 *
 * 估法：直线距离 × 1.2（路网折绕）÷ 30km/h 均速 + 8 分钟接驳。
 * 这是**估算**，屏上文案照此写「约 X km」，不编站数——站数是查出来的，不是算出来的。
 */
export interface TransitEstimate {
  mode: string;
  minutes: number;
  detail: string;
}

export class Transit {
  /** 一段路的分钟数；任一端缺坐标时给 15 分钟兜底（与历史口径一致） */
  static minutes(a: GeoPoint | null, b: GeoPoint | null): number {
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

  /** 同上，但带展示用的方式与距离描述 */
  static of(a: GeoPoint | null, b: GeoPoint | null): TransitEstimate {
    const minutes: number = Transit.minutes(a, b);
    if (a === null || b === null || !Geo.usable(a.latitude, a.longitude)
      || !Geo.usable(b.latitude, b.longitude)) {
      return { mode: '公共交通', minutes: minutes, detail: '距离未知' };
    }
    const km: number = Geo.distanceKm(a, b);
    const mode: string = km <= 1.5 ? '步行' : (km <= 12 ? '地铁' : '打车');
    const detail: string = `约 ${km.toFixed(1)}km`;
    return { mode: mode, minutes: minutes, detail: detail };
  }

  static pointOf(latitude: number, longitude: number): GeoPoint | null {
    return Geo.usable(latitude, longitude) ? { latitude: latitude, longitude: longitude } : null;
  }
}
