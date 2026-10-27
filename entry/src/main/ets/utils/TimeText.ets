/**
 * 时段文案（分钟差 → 「4小时」「30分钟」「4小时30分钟」）。
 *
 * 原来这段算法长在 `ItineraryPage.durationText` 里，屏9 补「移走后空多少」时
 * 要第二次用同一算法——复制一份必然漂，故提到 utils 层。
 * 只依赖 model，不碰 design/（§分层：utils 不许 import design）。
 */

import { Activity } from '../model/Trip';

export class TimeText {
  /** 停留时长；时间缺失或倒挂返回空串，由调用方决定怎么兜底 */
  static stayMinutes(act: Activity): number {
    const t: string[] = act.time.split(':');
    const e: string[] = act.endTime.split(':');
    if (t.length < 2 || e.length < 2) {
      return 0;
    }
    return Number(e[0]) * 60 + Number(e[1]) - Number(t[0]) * 60 - Number(t[1]);
  }

  static stayOf(act: Activity): string {
    const mins: number = TimeText.stayMinutes(act);
    if (mins <= 0) {
      return '';
    }
    const h: number = Math.floor(mins / 60);
    const m: number = mins % 60;
    if (h > 0 && m > 0) {
      return `${h}小时${m}分钟`;
    }
    return h > 0 ? `${h}小时` : `${m}分钟`;
  }
}
