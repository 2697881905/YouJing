/**
 * 行程长度文案（N 天 M 晚）。
 *
 * 为什么要有它：全仓七处各自写 `${days}天${days - 1}晚`，
 * 单日行程就被端成「1天0晚」——那是减法的结果，不是用户说的话（2026-11-04 真机实拍）。
 * 单天一趟过完，没有"晚"可报，只写「1天」。
 */
export class TripSpan {
  static text(days: number): string {
    const d: number = Math.max(1, Math.round(days));
    return d > 1 ? `${d}天${d - 1}晚` : '1天';
  }
}
