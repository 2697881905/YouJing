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

  /**
   * 出发日是否在今天（含）之后——**预填入口的过去日期守卫**。
   *
   * 为什么需要它：出发日在过去的行程没法真的去玩，屏2 的日期选择器也不允许选过去。
   * 外部预填（小艺 Skill / 深链 Want）若带着过去日期进来，必须在入口就判出来，
   * 否则会出现「小艺说已记下 8 月 1 日、界面却显示 11 月 13 日」的两边对不上
   * （2026-11-13 真机实测：预填 2026-08-01，屏2 实拍 11月13日 – 11月15日）。
   *
   * 比较用字符串字典序：ISO 日期定长且零填充，字典序即时间序（不引入时区与 Date 解析）。
   * 两个入参都必须先过 isValidIsoDate，否则空串/畸形串会得到假结论。
   */
  static isUpcoming(iso: string, today: string): boolean {
    if (!DateUtils.isValidIsoDate(iso) || !DateUtils.isValidIsoDate(today)) {
      return false;
    }
    return iso >= today;
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

  /** HH:mm → 当日分钟数；格式/范围非法返回 -1（调用方决定回退口径） */
  static minutesOf(hhmm: string): number {
    if (!/^\d{2}:\d{2}$/.test(hhmm)) {
      return -1;
    }
    const parts: string[] = hhmm.split(':');
    const h: number = Number(parts[0]);
    const m: number = Number(parts[1]);
    if (h > 23 || m > 59) {
      return -1;
    }
    return h * 60 + m;
  }

  /** 当日分钟数 → HH:mm；越界夹到 [00:00, 23:59] */
  static hhmmOf(minutes: number): string {
    const clamped: number = Math.max(0, Math.min(1439, Math.round(minutes)));
    const h: string = `${Math.floor(clamped / 60)}`.padStart(2, '0');
    const m: string = `${clamped % 60}`.padStart(2, '0');
    return `${h}:${m}`;
  }
}
