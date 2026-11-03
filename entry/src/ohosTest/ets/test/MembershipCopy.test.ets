/**
 * 「我的」页会员卡状态的回归。
 *
 * 关键语义：订阅是否有效以 periodEnd 为准（缓存里的 status 可能是旧的）；
 * 通行证按"已解锁条数"展示；两者都没有时说未开通，不假装有权益。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { membershipStatus, subscriptionActive, membershipUsage, MembershipStatus } from '../../../main/ets/utils/MembershipCopy';

export default function membershipCopyTest(): void {
  describe('MembershipCopy', () => {
    it('active_subscription_shows_period_end', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const s: MembershipStatus = membershipStatus(true, '2026-12-03 12:00:00', 0, '2026-11-03');
      expect(s.active).assertTrue();
      expect(s.title).assertEqual('订阅会员');
      expect(s.detail).assertEqual('有效期至 2026-12-03');
    });

    it('expired_subscription_is_not_active_even_if_status_true', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const s: MembershipStatus = membershipStatus(true, '2026-11-01 12:00:00', 0, '2026-11-03');
      expect(s.active).assertFalse();
      expect(s.title).assertEqual('未开通会员');
    });

    it('pass_holder_shows_unlocked_count', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const s: MembershipStatus = membershipStatus(false, '', 2, '2026-11-03');
      expect(s.active).assertTrue();
      expect(s.title).assertEqual('已解锁 2 条行程');
    });

    it('subscription_active_requires_future_end_and_active_status',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
        expect(subscriptionActive('active', '2026-12-03 12:00:00', '2026-11-03')).assertTrue();
        expect(subscriptionActive('active', '2026-11-01 12:00:00', '2026-11-03')).assertFalse();
        expect(subscriptionActive('expired', '2026-12-03 12:00:00', '2026-11-03')).assertFalse();
      });

    it('usage_only_for_subscriber_with_cap',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
        expect(membershipUsage(true, 17, 20)).assertEqual('本月已用 17 / 20 次');
        expect(membershipUsage(false, 17, 20)).assertEqual('');
        expect(membershipUsage(true, 0, 0)).assertEqual('');
      });

    it('expired_subscription_with_pass_falls_back_to_pass', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const s: MembershipStatus = membershipStatus(true, '2026-10-01 00:00:00', 1, '2026-11-03');
      expect(s.active).assertTrue();
      expect(s.title).assertEqual('已解锁 1 条行程');
    });
  });
}
