/**
 * 付费页标题/副标题的口径（纯函数，可进 hypium）。
 *
 * 为什么需要：订阅用户用满每月 20 次后，`GeneratingPage` 统一跳付费页
 * （`CLOUD_QUOTA_EXHAUSTED` 的唯一出口），而页面仍写「解锁完整行程 / 生成免费」——
 * 一个已经付费、只是本月用完的人被劝去"解锁"，属误导。这里按权益缓存给出诚实口径：
 * 订阅且本月用尽 ⇒ 说明额度与恢复时间，并指出通行证是立即可用的另一条路。
 */

export function pricingHeadline(hasSubscription: boolean, usedToday: number, dailyCap: number,
  giftSpent: boolean = false, exportGate: boolean = false): string {
  if (exportGate) {
    return '导出需要解锁';
  }
  if (hasSubscription && dailyCap > 0 && usedToday >= dailyCap) {
    return '本月次数已用完';
  }
  if (giftSpent) {
    return '免费次数已用完';
  }
  return '解锁完整行程';
}

export function pricingSubtitle(hasSubscription: boolean, usedToday: number, dailyCap: number,
  giftSpent: boolean = false, exportGate: boolean = false): string {
  if (exportGate) {
    return '通行证解锁这一个行程的导出、海报与分享；订阅解锁全部高级能力';
  }
  if (hasSubscription && dailyCap > 0 && usedToday >= dailyCap) {
    return `订阅每月 ${dailyCap} 次，下月 1 日恢复；单个行程通行证可立即继续`;
  }
  if (giftSpent) {
    // 这句原来 27 字，真机在「每 / 月 20 次」中间断行——中文逐字断行会把词劈开，
    // 付费页的说明行读起来像坏了。收成一句能落在单行内的长度（§5ci 续 192）
    return `赠送的免费次数已用完；通行证解锁这一趟，订阅每月 ${subMonthlyCap(dailyCap)} 次`;
  }
  return '生成免费，导出与无限重排需解锁';
}

/**
 * 订阅每月次数上限的唯一展示口径。
 *
 * 为什么需要：`EntitlementStore` 明确写了「上限口径改了不该等端侧发版」，
 * 付费页的标题/副标题也确实按服务端值插值；但同一屏的订阅计划卡把
 * 「每月 20 次生成上限」写死在特性数组里（2026-11-05 对表）。服务端改成 30 次那天，
 * 这一屏会同时说「订阅解锁每月 30 次」和「每月 20 次生成上限」。
 * 另外未激活/离线时缓存里的 dailyCap 是 0，直接插值会端出「每月 0 次」。
 */
export const SUB_MONTHLY_CAP_DEFAULT: number = 20;

export function subMonthlyCap(dailyCap: number): number {
  return dailyCap > 0 ? dailyCap : SUB_MONTHLY_CAP_DEFAULT;
}

export function subCapLine(dailyCap: number): string {
  return `每月 ${subMonthlyCap(dailyCap)} 次生成上限`;
}

/**
 * 三档展示价格的唯一来源。
 *
 * 为什么需要：同一屏把 `¥19.9` 写了两种间距（计划卡「¥19.9 / 月」、按钮「¥19.9/月」），
 * 且五个位置各写字面量——改价时必然漏一处，而付费页漏一处就是当场自相矛盾。
 * 注意端侧现在拿不到 AGC 的实时商品价格（`IapStore` 只按 productId 发起购买），
 * 所以这里仍是**声明价**：AGC 改了价格必须同步这九个字符，别指望界面自动跟上。
 */
export const PRICE_PASS: string = '¥9.9';
export const PRICE_SUB_MONTH: string = '¥19.9';
export const PRICE_SUB_YEAR: string = '¥98';

export function passPriceLine(): string {
  return `${PRICE_PASS}/单个行程`;
}

export function subPriceLine(): string {
  return `${PRICE_SUB_MONTH}/月 · ${PRICE_SUB_YEAR}/年`;
}

export function buyPassLabel(): string {
  return `购买行程通行证 ${PRICE_PASS}`;
}

export function subMonthLabel(): string {
  return `订阅会员 ${PRICE_SUB_MONTH}/月`;
}

export function subYearLabel(): string {
  return `订阅会员 ${PRICE_SUB_YEAR}/年`;
}
