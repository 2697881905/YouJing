/* AUTO-GENERATED from entry/src/main/ets/utils/DateUtils.ets by bff/scripts/sync-prompt-contract.mjs. Do not edit. */
"use strict";
/**
 * 日期纯函数（utils 层，禁依赖 @kit）。
 * 全工程日期串统一 ISO `YYYY-MM-DD`（与 Trip/TripDay 契约一致）。
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.DateUtils = void 0;
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;
class DateUtils {
    /**
     * 合法 ISO 日期 = 格式对 + 真实日历日存在。
     * 只过正则不够：`2026-02-30` 会被 JS Date 规范化成 3 月，
     * 放它过去就会产出 startDate=2026-02-30 / endDate=2026-03-xx 的撕裂行程。
     * 与 PlanTripSkill 的入参回检同一口径（小艺 Skill 清单承诺「2026-02-30 会被拒」）。
     */
    static isValidIsoDate(text) {
        if (!ISO_DATE.test(text)) {
            return false;
        }
        const parts = text.split('-');
        const year = Number(parts[0]);
        const month = Number(parts[1]);
        const day = Number(parts[2]);
        const date = new Date(year, month - 1, day);
        return date.getFullYear() === year && date.getMonth() === month - 1 && date.getDate() === day;
    }
    /** ISO 日期加减天数，越界自动进位；入参非法返回空串 */
    static addDays(iso, days) {
        if (!DateUtils.isValidIsoDate(iso)) {
            return '';
        }
        const parts = iso.split('-');
        const base = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
        base.setDate(base.getDate() + days);
        return DateUtils.toIso(base);
    }
    static toIso(date) {
        const m = `${date.getMonth() + 1}`;
        const d = `${date.getDate()}`;
        return `${date.getFullYear()}-${m.length < 2 ? `0${m}` : m}-${d.length < 2 ? `0${d}` : d}`;
    }
    /** 含首尾的天数差，至少 1 */
    static spanDays(startIso, endIso) {
        if (!DateUtils.isValidIsoDate(startIso) || !DateUtils.isValidIsoDate(endIso)) {
            return 1;
        }
        const s = Date.parse(`${startIso}T00:00:00`);
        const e = Date.parse(`${endIso}T00:00:00`);
        return Math.max(1, Math.round((e - s) / 86400000) + 1);
    }
    /** 今天（本机时区）的 ISO 日期 */
    static todayIso() {
        return DateUtils.toIso(new Date());
    }
    /** HH:mm → 当日分钟数；格式/范围非法返回 -1（调用方决定回退口径） */
    static minutesOf(hhmm) {
        if (!/^\d{2}:\d{2}$/.test(hhmm)) {
            return -1;
        }
        const parts = hhmm.split(':');
        const h = Number(parts[0]);
        const m = Number(parts[1]);
        if (h > 23 || m > 59) {
            return -1;
        }
        return h * 60 + m;
    }
    /** 当日分钟数 → HH:mm；越界夹到 [00:00, 23:59] */
    static hhmmOf(minutes) {
        const clamped = Math.max(0, Math.min(1439, Math.round(minutes)));
        const h = `${Math.floor(clamped / 60)}`.padStart(2, '0');
        const m = `${clamped % 60}`.padStart(2, '0');
        return `${h}:${m}`;
    }
}
exports.DateUtils = DateUtils;
