/**
 * 当日负载（纯逻辑，不引 @kit）：把一天的活动折成「需要用户在场多少分钟」，
 * 与一个建议窗口比出三态，供屏8 吸顶日标题的负载条使用。
 *
 * 口径（别改回「最后结束 − 最早开始」）：
 * 跨度会把「上午两小时 + 晚上两小时」算成 12 小时，用户读到的「今日 12h」就不成立；
 * 这里只累加**真正被占用**的两段——
 *   · 停留 = 非交通节点的 endTime − time；
 *   · 通勤 = 非交通节点到达该站的 transport.duration；
 *     交通节点本身就是一段路，只取「节点时段」或「自带 duration」其中一个，
 *     同一条腿算两次会把 10 小时的一天报成 13.4 小时。
 * 两者相加超过窗口就是排太满。
 */

import { ActivityCategory, TransportInfo, TripDay } from '../model/Trip';
import { DateUtils } from './DateUtils';

export enum LoadLevel {
  OK = 'ok',
  WARN = 'warn',
  OVER = 'over'
}

export interface DayLoad {
  stayMinutes: number;
  transitMinutes: number;
  /** stayMinutes + transitMinutes */
  minutes: number;
  /** 建议窗口，分钟（10 小时） */
  windowMinutes: number;
  /** minutes / windowMinutes，不做四舍五入 */
  ratio: number;
  level: LoadLevel;
}

export class DayLoadCalc {
  /** 建议在场窗口：10 小时。低于 8 小时会误伤正常的一天，高于 12 小时就失去提醒意义 */
  static readonly WINDOW_MINUTES: number = 600;
  /** 达到窗口的 80% 起标黄 */
  static readonly WARN_RATIO: number = 0.8;

  static of(day: TripDay): DayLoad {
    let stay: number = 0;
    let transit: number = 0;
    for (const act of day.activities) {
      const start: number = DateUtils.minutesOf(act.time);
      const end: number = DateUtils.minutesOf(act.endTime);
      const span: number = start >= 0 && end > start ? end - start : 0;
      const t: TransportInfo | undefined = act.transport;
      if (act.category === ActivityCategory.TRANSPORT) {
        // 交通节点本身就是一段路：有时段按时段，没时段才用自带 duration 兜，二者不叠加
        if (span > 0) {
          transit += span;
        } else if (t !== undefined && t.duration > 0) {
          transit += t.duration;
        }
      } else {
        stay += span;
        if (t !== undefined && t.duration > 0) {
          transit += t.duration;
        }
      }
    }
    const minutes: number = stay + transit;
    const ratio: number = minutes / DayLoadCalc.WINDOW_MINUTES;
    const level: LoadLevel = minutes > DayLoadCalc.WINDOW_MINUTES ? LoadLevel.OVER :
      (ratio >= DayLoadCalc.WARN_RATIO ? LoadLevel.WARN : LoadLevel.OK);
    const load: DayLoad = {
      stayMinutes: stay, transitMinutes: transit, minutes: minutes,
      windowMinutes: DayLoadCalc.WINDOW_MINUTES, ratio: ratio, level: level
    };
    return load;
  }

  /** 分钟 → 小时文案，一位小数且去掉「.0」：390→'6.5'、600→'10'、642→'10.7' */
  static hours(minutes: number): string {
    const hours: number = Math.round(Math.max(0, minutes) / 6) / 10;
    const text: string = `${hours}`;
    return text.endsWith('.0') ? text.slice(0, text.length - 2) : text;
  }

  /** 屏8 吸顶日标题那一行（数据为空串时返回 ''，宿主据此整行不出） */
  static label(load: DayLoad): string {
    if (load.minutes <= 0) {
      return '';
    }
    const total: string = DayLoadCalc.hours(load.minutes);
    if (load.level === LoadLevel.OVER) {
      return `今日 ${total}h · 超建议 ${DayLoadCalc.hours(load.minutes - load.windowMinutes)}h`;
    }
    return `今日 ${total}h · 建议 ≤${DayLoadCalc.hours(load.windowMinutes)}h`;
  }
}
