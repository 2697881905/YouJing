/**
 * 时长中文文案（纯函数，可进 hypium）。
 *
 * 为什么收成一处：屏8/屏15 此前直接把分钟数原样打出来，真机实拍到
 * 「打车 149分钟」「已过开始时间 431 分钟」——用户要的是"2小时29分钟"，不是自己做除法。
 * 小于 1 小时的量保留分钟（45分钟比0.8小时好读），过 1 天才拆到天。
 * **写法跟 utils/TimeText.stayOf 的既有口径一致（不带空格：4小时30分钟）**，
 * 免得同一个 App 里出现「5小时」与「5 小时」两套间距。
 */
export class DurationCn {
  /** 分钟 → 人读的时长：45→'45分钟'、60→'1小时'、162→'2小时42分钟'、1500→'1天1小时' */
  static text(minutes: number): string {
    const m: number = Math.max(0, Math.round(minutes));
    if (m < 60) {
      return `${m}分钟`;
    }
    const days: number = Math.floor(m / 1440);
    const hours: number = Math.floor((m % 1440) / 60);
    const mins: number = m % 60;
    if (days > 0) {
      return hours === 0 ? `${days}天` : `${days}天${hours}小时`;
    }
    return mins === 0 ? `${hours}小时` : `${hours}小时${mins}分钟`;
  }
}
