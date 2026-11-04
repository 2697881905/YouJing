/**
 * 时长中文文案（纯函数，可进 hypium）。
 *
 * 为什么收成一处：屏15 的信号条此前直接把分钟数原样打出来，真机实拍到
 * 「已过开始时间 431 分钟」——用户要的是"7 小时 11 分"，不是自己做除法。
 * 小于 1 小时的量保留分钟（"45 分钟"比"0.8 小时"好读），过 1 天才拆到天。
 */
export class DurationCn {
  /** 分钟 → 人读的时长：45→'45 分钟'、60→'1 小时'、162→'2 小时 42 分'、1500→'1 天 1 小时' */
  static text(minutes: number): string {
    const m: number = Math.max(0, Math.round(minutes));
    if (m < 60) {
      return `${m} 分钟`;
    }
    const days: number = Math.floor(m / 1440);
    const hours: number = Math.floor((m % 1440) / 60);
    const mins: number = m % 60;
    if (days > 0) {
      return hours === 0 ? `${days} 天` : `${days} 天 ${hours} 小时`;
    }
    return mins === 0 ? `${hours} 小时` : `${hours} 小时 ${mins} 分`;
  }
}
