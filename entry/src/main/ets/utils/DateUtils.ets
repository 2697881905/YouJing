/**
 * 日期纯函数（utils 层，禁依赖 @kit）。
 * 全工程日期串统一 ISO `YYYY-MM-DD`（与 Trip/TripDay 契约一致）。
 */

const ISO_DATE: RegExp = /^\d{4}-\d{2}-\d{2}$/;

export class DateUtils {
  /**
   * 合法 ISO 日期 = 格式对 + 真实日历日存在。
   * 只过正则不够：`2026-02-30` 会被 JS Date 规范化成 3 月，
   * 放它过去就会产出 startDate=2026-02-30 / endDate=2026-03-xx 的撕裂行程。
   * 与 PlanTripSkill 的入参回检同一口径（小艺 Skill 清单承诺「2026-02-30 会被拒」）。
   */
  static isValidIsoDate(text: string): boolean {
    if (!ISO_DATE.test(text)) {
      return false;
    }
    const parts: string[] = text.split('-');
    const year: number = Number(parts[0]);
    const month: number = Number(parts[1]);
    const day: number = Number(parts[2]);
    const date: Date = new Date(year, month - 1, day);
    return date.getFullYear() === year && date.getMonth() === month - 1 && date.getDate() === day;
  }

  /** ISO 日期加减天数，越界自动进位；入参非法返回空串 */
  static addDays(iso: string, days: number): string {
    if (!DateUtils.isValidIsoDate(iso)) {
      return '';
    }
    const parts: string[] = iso.split('-');
    const base: Date = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
    base.setDate(base.getDate() + days);
    return DateUtils.toIso(base);
  }

  static toIso(date: Date): string {
    const m: string = `${date.getMonth() + 1}`;
    const d: string = `${date.getDate()}`;
    return `${date.getFullYear()}-${m.length < 2 ? `0${m}` : m}-${d.length < 2 ? `0${d}` : d}`;
  }

  /** 含首尾的天数差，至少 1 */
  static spanDays(startIso: string, endIso: string): number {
    if (!DateUtils.isValidIsoDate(startIso) || !DateUtils.isValidIsoDate(endIso)) {
      return 1;
    }
    const s: number = Date.parse(`${startIso}T00:00:00`);
    const e: number = Date.parse(`${endIso}T00:00:00`);
    return Math.max(1, Math.round((e - s) / 86400000) + 1);
  }

  /** 今天（本机时区）的 ISO 日期 */
  static todayIso(): string {
    return DateUtils.toIso(new Date());
  }
}
