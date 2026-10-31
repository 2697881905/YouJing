/**
 * 一句话成行程 · 本地意图解析（纯函数，不碰 @kit，可离线断言）。
 *
 * 只识别 App 真能消费的字段：目的地 / 日期 / 天数 / 人数 / 预算 / 四类偏好 / 兴趣标签。
 * 没有 LLM、不联网；原句不落盘，调用方只把派生字段写进 PlanDraft 与表单。
 * 歧义一律走「可解释的默认」：解析结果会连同 notes 在确认面板里逐条说明。
 */

import { BudgetConfig } from '../common/constants/BudgetConfig';
import { CITY_ALIASES, MAP_CITY_ALIASES, SUPPORTED_CITIES, UNSUPPORTED_CITIES } from '../common/constants/Cities';
import { SpotTag } from '../model/Spot';
import { DateUtils } from './DateUtils';

export interface TripIntent {
  /** 命中的支持城市；'' = 没识别出目的地 */
  city: string;
  /** 命中可走 Map Kit 的未内置城市；'' = 没有 */
  unsupportedCity: string;
  /** ISO 出发日；'' = 没提到 */
  startDate: string;
  /** 天数；0 = 没提到 */
  dayCount: number;
  /** 人数；0 = 没提到 */
  people: number;
  /** 原句里的预算数额（元）；0 = 没提到 */
  budgetAmount: number;
  /** true = 原句写了「人均/每人」；false = 按总预算理解 */
  budgetIsPerPerson: boolean;
  /** TravelStyle 码值；'' = 没提到 */
  style: string;
  /** AreaPriceTier 码值；'' = 没提到 */
  stayTier: string;
  /** TransitPreference 码值；'' = 没提到 */
  transit: string;
  /** PaceOption 码值；'' = 没提到 */
  pace: string;
  /** SpotTag 码值，给自动选点做兴趣加权 */
  tags: string[];
  /** 口径说明（日期非法、跨年推断等），按顺序展示 */
  notes: string[];
}

interface BudgetParse {
  amount: number;
  perPerson: boolean;
}

export class TripIntentParser {
  static parse(text: string, todayIso: string): TripIntent {
    const intent: TripIntent = {
      city: '', unsupportedCity: '', startDate: '', dayCount: 0, people: 0,
      budgetAmount: 0, budgetIsPerPerson: false, style: '', stayTier: '',
      transit: '', pace: '', tags: [], notes: []
    };
    const raw: string = text.trim();
    if (raw.length === 0) {
      return intent;
    }
    const dest: string = TripIntentParser.findDestination(raw);
    if (dest.startsWith('!')) {
      // 未内置城市不再提前返回：日期/人数/预算/偏好照样解析，
      // 由页面决定走 Map Kit 还是明确拒绝（Stage 2）
      intent.unsupportedCity = dest.substring(1);
    } else {
      intent.city = dest;
    }
    intent.startDate = TripIntentParser.parseStartDate(raw, todayIso, intent.notes);
    intent.dayCount = TripIntentParser.parseDuration(raw);
    intent.people = TripIntentParser.parsePeople(raw);
    const budget: BudgetParse = TripIntentParser.parseBudget(raw);
    intent.budgetAmount = budget.amount;
    intent.budgetIsPerPerson = budget.perPerson;
    intent.style = TripIntentParser.parseStyle(raw);
    intent.stayTier = TripIntentParser.parseStay(raw);
    intent.transit = TripIntentParser.parseTransit(raw);
    intent.pace = TripIntentParser.parsePace(raw);
    if (intent.pace.length === 0) {
      // 「暴走/休闲」本身就是节奏信号，不再要求用户补一个「每天几个」
      if (intent.style === 'fast_pace') {
        intent.pace = 'packed';
      } else if (intent.style === 'leisure') {
        intent.pace = 'relaxed';
      }
    }
    intent.tags = TripIntentParser.parseTags(raw, intent.style);
    return intent;
  }

  /**
   * 预算折算成人均并夹到屏2 滑杆档位。
   * 总预算 ÷ 人数；没说人均时按总预算理解，结果由确认面板写明。
   */
  static budgetPerPerson(amount: number, isPerPerson: boolean, people: number): number {
    if (!Number.isFinite(amount) || amount <= 0) {
      return 0;
    }
    const n: number = people > 0 ? people : 1;
    const per: number = isPerPerson ? amount : amount / n;
    const clamped: number = Math.max(BudgetConfig.MIN, Math.min(BudgetConfig.MAX, per));
    const stepped: number = Math.round(clamped / BudgetConfig.STEP) * BudgetConfig.STEP;
    return Math.max(BudgetConfig.MIN, Math.min(BudgetConfig.MAX, stepped));
  }

  private static findDestination(text: string): string {
    // 目的地动词优先：「从北京去西安」要判成西安，不能被全句扫描先抓到北京
    const verbs: string[] = ['前往', '飞往', '抵达', '去', '到'];
    for (const v of verbs) {
      let from: number = 0;
      while (from < text.length) {
        const at: number = text.indexOf(v, from);
        if (at < 0) {
          break;
        }
        const start: number = at + v.length;
        const tail: string = text.substring(start, Math.min(text.length, start + 8));
        const hit: string = TripIntentParser.matchSupported(tail);
        if (hit.length > 0) {
          return hit;
        }
        const miss: string = TripIntentParser.matchUnsupported(tail);
        if (miss.length > 0) {
          return `!${miss}`;
        }
        from = start;
      }
    }
    const anywhere: string = TripIntentParser.matchSupported(text);
    if (anywhere.length > 0) {
      return anywhere;
    }
    return TripIntentParser.matchUnsupported(text);
  }

  private static matchSupported(text: string): string {
    for (const city of SUPPORTED_CITIES) {
      if (text.indexOf(city) >= 0) {
        return city;
      }
    }
    for (const a of CITY_ALIASES) {
      if (text.indexOf(a.alias) >= 0) {
        return a.city;
      }
    }
    return '';
  }

  private static matchUnsupported(text: string): string {
    // 先认别称（蓉城/山城…），再扫常见城市名；两者都交给 Map Kit
    for (const a of MAP_CITY_ALIASES) {
      if (text.indexOf(a.alias) >= 0) {
        return a.city;
      }
    }
    for (const city of UNSUPPORTED_CITIES) {
      if (text.indexOf(city) >= 0) {
        return city;
      }
    }
    return '';
  }

  private static parseStartDate(text: string, todayIso: string, notes: string[]): string {
    // 显式月日优先于「明天」这类相对词
    const dated: RegExpMatchArray | null =
      text.match(/(\d{1,2}|[一二三四五六七八九十]{1,3})\s*月\s*(\d{1,2}|[一二三四五六七八九十]{1,3})\s*[日号]/);
    if (dated !== null) {
      const month: number = TripIntentParser.parseIntLoose(dated[1]);
      const day: number = TripIntentParser.parseIntLoose(dated[2]);
      if (month < 1 || month > 12 || day < 1 || day > 31) {
        notes.push(`「${dated[0]}」不是有效日期，已忽略`);
        return '';
      }
      const year: number = Number(todayIso.substring(0, 4));
      let iso: string = TripIntentParser.isoOf(year, month, day);
      if (!DateUtils.isValidIsoDate(iso)) {
        notes.push(`「${dated[0]}」不是有效日期，已忽略`);
        return '';
      }
      if (iso < todayIso) {
        iso = TripIntentParser.isoOf(year + 1, month, day);
        if (!DateUtils.isValidIsoDate(iso)) {
          notes.push(`「${dated[0]}」不是有效日期，已忽略`);
          return '';
        }
        notes.push(`日期没写年份，按 ${year + 1} 年`);
      }
      return iso;
    }
    // 大后天必须先于后天判断（前者包含后者的字面）
    if (text.indexOf('大后天') >= 0) {
      return DateUtils.addDays(todayIso, 3);
    }
    if (text.indexOf('后天') >= 0) {
      return DateUtils.addDays(todayIso, 2);
    }
    if (text.indexOf('明天') >= 0) {
      return DateUtils.addDays(todayIso, 1);
    }
    if (text.indexOf('今天') >= 0) {
      return todayIso;
    }
    const nextWeek: RegExpMatchArray | null = text.match(/(下周|下星期)([一二三四五六日天])/);
    if (nextWeek !== null) {
      return TripIntentParser.weekdayDate(todayIso, TripIntentParser.weekdayOf(nextWeek[2]), true);
    }
    const thisWeek: RegExpMatchArray | null = text.match(/(本周|这周|这星期)([一二三四五六日天])/);
    if (thisWeek !== null) {
      return TripIntentParser.weekdayDate(todayIso, TripIntentParser.weekdayOf(thisWeek[2]), false);
    }
    return '';
  }

  private static parseDuration(text: string): number {
    const withNights: RegExpMatchArray | null =
      TripIntentParser.durationMatch(text, /(\d+|[一二两三四五六七八九十]+)\s*天\s*(?:\d+|[一二两三四五六七八九十]+)\s*晚/);
    if (withNights !== null) {
      return TripIntentParser.clampDays(TripIntentParser.parseIntLoose(withNights[1]));
    }
    const days: RegExpMatchArray | null =
      TripIntentParser.durationMatch(text, /(\d+|[一二两三四五六七八九十]+)\s*天/);
    if (days !== null) {
      return TripIntentParser.clampDays(TripIntentParser.parseIntLoose(days[1]));
    }
    const nights: RegExpMatchArray | null =
      TripIntentParser.durationMatch(text, /(\d+|[一二两三四五六七八九十]+)\s*晚/);
    if (nights !== null) {
      return TripIntentParser.clampDays(TripIntentParser.parseIntLoose(nights[1]) + 1);
    }
    const tour: RegExpMatchArray | null =
      TripIntentParser.durationMatch(text, /(\d+|[一二两三四五六七八九十]+)\s*日\s*游/);
    if (tour !== null) {
      return TripIntentParser.clampDays(TripIntentParser.parseIntLoose(tour[1]));
    }
    return 0;
  }

  /** 「第 3 天」是行程内的序号，不是玩 3 天；跳过它继续找下一个「X天」 */
  private static durationMatch(text: string, re: RegExp): RegExpMatchArray | null {
    let from: number = 0;
    while (from < text.length) {
      const rest: string = text.substring(from);
      const m: RegExpMatchArray | null = rest.match(re);
      if (m === null) {
        return null;
      }
      const local: number = m.index === undefined ? 0 : m.index;
      if (from + local > 0 && text.charAt(from + local - 1) === '第') {
        from = from + local + 1;
        continue;
      }
      return m;
    }
    return null;
  }

  private static clampDays(n: number): number {
    if (n < 1) {
      return 0;
    }
    return Math.min(30, n);
  }

  private static parsePeople(text: string): number {
    const family: RegExpMatchArray | null = text.match(/一家\s*([一二两三四五六七八九十]+)\s*口/);
    if (family !== null) {
      return TripIntentParser.clampPeople(TripIntentParser.parseIntLoose(family[1]));
    }
    if (text.indexOf('两口子') >= 0) {
      return 2;
    }
    const m: RegExpMatchArray | null =
      text.match(/(\d+|[一二两三四五六七八九十]+)\s*(个|位|名)?\s*(?:成人|人)/);
    if (m !== null) {
      return TripIntentParser.clampPeople(TripIntentParser.parseIntLoose(m[1]));
    }
    return 0;
  }

  private static clampPeople(n: number): number {
    if (n < 1) {
      return 0;
    }
    return Math.min(20, n);
  }

  private static parseBudget(text: string): BudgetParse {
    const perPerson: boolean = text.indexOf('人均') >= 0 ||
      text.indexOf('每人') >= 0 || text.indexOf('/人') >= 0;
    let at: number = text.indexOf('预算');
    if (at < 0) {
      at = text.indexOf('人均');
    }
    if (at < 0) {
      at = text.indexOf('每人');
    }
    if (at < 0) {
      at = text.indexOf('花费');
    }
    if (at < 0) {
      at = text.indexOf('费用');
    }
    if (at < 0) {
      return { amount: 0, perPerson: false };
    }
    // 五个标记都是两字词
    const tail: string = text.substring(at + 2, Math.min(text.length, at + 14));
    return { amount: TripIntentParser.amountOf(tail), perPerson: perPerson };
  }

  private static amountOf(tail: string): number {
    const m: RegExpMatchArray | null =
      tail.match(/(\d+(?:\.\d+)?)\s*(万|w|W|千|k|K)?|([零一二两三四五六七八九十百千万]+)/);
    if (m === null) {
      return 0;
    }
    if (m[1] !== undefined) {
      let value: number = Number(m[1]);
      const unit: string = m[2] === undefined ? '' : m[2];
      if (unit === '万' || unit === 'w' || unit === 'W') {
        value *= 10000;
      } else if (unit === '千' || unit === 'k' || unit === 'K') {
        value *= 1000;
      }
      return Math.round(value);
    }
    const chinese: number = TripIntentParser.parseIntLoose(m[3]);
    return chinese > 0 ? chinese : 0;
  }

  private static parseStyle(text: string): string {
    if (TripIntentParser.hasAny(text, ['美食', '小吃', '吃货', '餐厅', '探店'])) {
      return 'foodie';
    }
    if (TripIntentParser.hasAny(text, ['亲子', '带娃', '带孩子', '小孩', '宝宝', '一家老小'])) {
      return 'family';
    }
    if (TripIntentParser.hasAny(text, ['暴走', '特种兵', '打卡狂', '赶景点'])) {
      return 'fast_pace';
    }
    if (TripIntentParser.hasAny(text, ['文化', '历史', '古迹', '博物馆', '人文', '看展'])) {
      return 'culture';
    }
    if (TripIntentParser.hasAny(text, ['休闲', '放松', '悠闲', '慢游', '躺平'])) {
      return 'leisure';
    }
    return '';
  }

  private static parseStay(text: string): string {
    if (TripIntentParser.hasAny(text, ['经济', '省钱', '便宜', '穷游'])) {
      return 'economy';
    }
    if (TripIntentParser.hasAny(text, ['豪华', '五星', '高端', '奢华'])) {
      return 'luxury';
    }
    if (TripIntentParser.hasAny(text, ['舒适', '舒服'])) {
      return 'comfort';
    }
    return '';
  }

  private static parseTransit(text: string): string {
    if (TripIntentParser.hasAny(text, ['包车', '自驾', '租车'])) {
      return 'charter';
    }
    if (TripIntentParser.hasAny(text, ['打车', '网约车', '出租车', '滴滴'])) {
      return 'taxi_main';
    }
    if (TripIntentParser.hasAny(text, ['地铁', '公交', '公共交通'])) {
      return 'public';
    }
    return '';
  }

  private static parsePace(text: string): string {
    if (TripIntentParser.hasAny(text, ['轻松', '悠闲', '慢节奏', '每天两三', '每天2-3', '每天3个'])) {
      return 'relaxed';
    }
    if (TripIntentParser.hasAny(text, ['紧凑', '暴走', '特种兵', '每天六七', '每天6个', '赶一点'])) {
      return 'packed';
    }
    if (TripIntentParser.hasAny(text, ['标准', '正常节奏'])) {
      return 'standard';
    }
    return '';
  }

  private static parseTags(text: string, style: string): string[] {
    const tags: string[] = [];
    const add = (tag: string): void => {
      if (tags.indexOf(tag) < 0) {
        tags.push(tag);
      }
    };
    if (TripIntentParser.hasAny(text, ['亲子', '带娃', '带孩子', '小孩', '宝宝', '一家老小'])) {
      add(SpotTag.FAMILY as string);
    }
    if (TripIntentParser.hasAny(text, ['小众', '冷门', '人少', '避开人群'])) {
      add(SpotTag.NICHE as string);
    }
    if (TripIntentParser.hasAny(text, ['历史', '文化', '古迹', '博物馆', '人文'])) {
      add(SpotTag.CLASSIC as string);
    }
    if (TripIntentParser.hasAny(text, ['必去', '地标', '经典', '打卡'])) {
      add(SpotTag.MUST_SEE as string);
    }
    if (style === 'family') {
      add(SpotTag.FAMILY as string);
    } else if (style === 'culture') {
      add(SpotTag.CLASSIC as string);
      add(SpotTag.MUST_SEE as string);
    } else if (style === 'fast_pace') {
      add(SpotTag.MUST_SEE as string);
    }
    return tags;
  }

  private static hasAny(text: string, words: string[]): boolean {
    for (const w of words) {
      if (text.indexOf(w) >= 0) {
        return true;
      }
    }
    return false;
  }

  private static isoOf(year: number, month: number, day: number): string {
    const m: string = `${month}`.padStart(2, '0');
    const d: string = `${day}`.padStart(2, '0');
    return `${year}-${m}-${d}`;
  }

  private static weekdayOf(ch: string): number {
    if (ch === '一') {
      return 1;
    }
    if (ch === '二') {
      return 2;
    }
    if (ch === '三') {
      return 3;
    }
    if (ch === '四') {
      return 4;
    }
    if (ch === '五') {
      return 5;
    }
    if (ch === '六') {
      return 6;
    }
    return 7;
  }

  private static weekdayDate(todayIso: string, weekday: number, nextWeek: boolean): string {
    const parts: string[] = todayIso.split('-');
    const base: Date = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
    const jsDay: number = base.getDay();
    const todayWeekday: number = jsDay === 0 ? 7 : jsDay;
    if (nextWeek) {
      let toMonday: number = (8 - todayWeekday) % 7;
      if (toMonday === 0) {
        toMonday = 7;
      }
      const monday: string = DateUtils.addDays(todayIso, toMonday);
      return DateUtils.addDays(monday, weekday - 1);
    }
    let delta: number = weekday - todayWeekday;
    if (delta < 0) {
      delta += 7;
    }
    return DateUtils.addDays(todayIso, delta);
  }

  private static parseIntLoose(raw: string): number {
    if (/^\d+$/.test(raw)) {
      return Number(raw);
    }
    return TripIntentParser.parseChineseInt(raw);
  }

  /** 支持到万级；「一万二」「一千二」「一百零五」按口语读法 */
  private static parseChineseInt(raw: string): number {
    if (raw.length === 0) {
      return -1;
    }
    const text: string = raw.replace(/两/g, '二');
    const wanAt: number = text.indexOf('万');
    if (wanAt >= 0) {
      if (text.indexOf('万', wanAt + 1) >= 0) {
        return -1;
      }
      const leftRaw: string = text.substring(0, wanAt);
      const rightRaw: string = text.substring(wanAt + 1);
      const left: number = leftRaw.length === 0 ? 1 : TripIntentParser.parseUnder10000(leftRaw);
      if (left < 0) {
        return -1;
      }
      let right: number = 0;
      if (rightRaw.length > 0) {
        const single: number = TripIntentParser.digitOf(rightRaw.charAt(0));
        if (rightRaw.length === 1 && single >= 0) {
          right = single * 1000;
        } else {
          right = TripIntentParser.parseUnder10000(rightRaw);
          if (right < 0) {
            return -1;
          }
        }
      }
      return left * 10000 + right;
    }
    const value: number = TripIntentParser.parseUnder10000(text);
    return value > 0 ? value : -1;
  }

  private static parseUnder10000(text: string): number {
    let total: number = 0;
    let num: number = 0;
    let lastUnit: number = 0;
    let sawZero: boolean = false;
    let hasChar: boolean = false;
    for (let i = 0; i < text.length; i++) {
      const ch: string = text.charAt(i);
      const digit: number = TripIntentParser.digitOf(ch);
      if (digit >= 0) {
        if (ch === '零') {
          sawZero = true;
          num = 0;
        } else {
          num = digit;
        }
        hasChar = true;
        continue;
      }
      let unit: number = 0;
      if (ch === '十') {
        unit = 10;
      } else if (ch === '百') {
        unit = 100;
      } else if (ch === '千') {
        unit = 1000;
      }
      if (unit === 0) {
        return -1;
      }
      if (num === 0 && unit === 10) {
        num = 1;
      }
      total += num * unit;
      num = 0;
      lastUnit = unit;
      sawZero = false;
      hasChar = true;
    }
    if (!hasChar) {
      return -1;
    }
    if (num > 0) {
      if (!sawZero && lastUnit >= 100) {
        total += num * (lastUnit / 10);
      } else {
        total += num;
      }
    }
    return total;
  }

  private static digitOf(ch: string): number {
    if (ch === '零') {
      return 0;
    }
    if (ch === '一') {
      return 1;
    }
    if (ch === '二') {
      return 2;
    }
    if (ch === '三') {
      return 3;
    }
    if (ch === '四') {
      return 4;
    }
    if (ch === '五') {
      return 5;
    }
    if (ch === '六') {
      return 6;
    }
    if (ch === '七') {
      return 7;
    }
    if (ch === '八') {
      return 8;
    }
    if (ch === '九') {
      return 9;
    }
    return -1;
  }
}
