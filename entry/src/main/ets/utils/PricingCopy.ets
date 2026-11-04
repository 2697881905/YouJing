/**
 * 付费页标题/副标题的口径（纯函数，可进 hypium）。
 *
 * 为什么需要：订阅用户用满每月 20 次后，`GeneratingPage` 统一跳付费页
 * （`CLOUD_QUOTA_EXHAUSTED` 的唯一出口），而页面仍写「解锁完整行程 / 生成免费」——
 * 一个已经付费、只是本月用完的人被劝去"解锁"，属误导。这里按权益缓存给出诚实口径：
 * 订阅且本月用尽 ⇒ 说明额度与恢复时间，并指出通行证是立即可用的另一条路。
 */

export function pricingHeadline(hasSubscription: boolean, usedToday: number, dailyCap: number,
  giftSpent: boolean = false): string {
  if (hasSubscription && dailyCap > 0 && usedToday >= dailyCap) {
    return '本月次数已用完';
  }
  if (giftSpent) {
    return '免费次数已用完';
  }
  return '解锁完整行程';
}

export function pricingSubtitle(hasSubscription: boolean, usedToday: number, dailyCap: number,
  giftSpent: boolean = false): string {
  if (hasSubscription && dailyCap > 0 && usedToday >= dailyCap) {
    return `订阅每月 ${dailyCap} 次，下月 1 日恢复；单个行程通行证可立即继续`;
  }
  if (giftSpent) {
    return `赠送的免费次数已用完；通行证解锁这一个行程，订阅解锁每月 ${dailyCap} 次`;
  }
  return '生成免费，导出与无限重排需解锁';
}
