/**
 * 「我的」页会员卡文案（纯函数，可进 hypium）。
 *
 * 为什么需要：付费链路做完后，App 里**没有任何地方**能看到订阅/通行证状态——
 * 用户付过钱却只能从"还能不能导出"反推。这里按权益缓存给一句话状态：
 * 订阅以 periodEnd 是否到期为准（不信 status 一个字段），通行证按条数。
 */

export interface MembershipStatus {
  title: string;
  detail: string;
  active: boolean;
}

/** 订阅是否在有效期内：status=active 且 periodEnd（按天）不早于今天 */
export function subscriptionActive(status: string, periodEnd: string, todayIso: string): boolean {
  const endDate: string = periodEnd.length >= 10 ? periodEnd.slice(0, 10) : '';
  return status === 'active' && endDate.length === 10 && endDate >= todayIso;
}

export function membershipStatus(hasSubscription: boolean, periodEnd: string,
  passCount: number, todayIso: string): MembershipStatus {
  const endDate: string = periodEnd.length >= 10 ? periodEnd.slice(0, 10) : '';
  const active: boolean = hasSubscription && endDate.length === 10 && endDate >= todayIso;
  if (active) {
    const status: MembershipStatus = {
      title: '订阅会员',
      detail: `有效期至 ${endDate}`,
      active: true
    };
    return status;
  }
  if (passCount > 0) {
    const status: MembershipStatus = {
      title: `已解锁 ${passCount} 条行程`,
      detail: '行程通行证（买断）· 该行程不限次生成',
      active: true
    };
    return status;
  }
  const status: MembershipStatus = {
    title: '未开通会员',
    detail: '生成免费；导出与无限重排需解锁',
    active: false
  };
  return status;
}
