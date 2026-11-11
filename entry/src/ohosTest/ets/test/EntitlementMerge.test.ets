/**
 * 配额快照合并的回归（D9）。
 *
 * 为什么要有这一份：端侧此前把 `subscription` 从本地缓存**原样结转**，服务端回的 quota 里
 * 根本没有这个字段。于是订阅到期或退款之后，只要生成间隔小于缓存 TTL，
 * 付费页/门禁会一直认为"订阅有效"。现在服务端回传 subscription 快照，
 * 正确语义是「服务端说 null 就清掉」，而「旧版服务端没这个字段」才沿用旧值。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import {
  Entitlement, QuotaSnapshot, mergeQuotaSnapshot, SubscriptionInfo, EntitlementStore
} from '../../../main/ets/data/EntitlementStore';

function baseEntitlement(): Entitlement {
  const sub: SubscriptionInfo = { status: 'active', periodEnd: '2026-12-03 12:00:00' };
  const ent: Entitlement = {
    subscription: sub,
    passes: [],
    giftRemaining: 2,
    usedToday: 3,
    dailyCap: 20
  };
  return ent;
}

export default function entitlementMergeTest(): void {
  describe('EntitlementMerge', () => {
    it('server_null_subscription_clears_local', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const quota: QuotaSnapshot = { subscription: null };
      const merged: Entitlement = mergeQuotaSnapshot(baseEntitlement(), quota);
      // 到期/退款后服务端回 null，本地必须跟着清——这是端上唯一的失效通路
      expect(merged.subscription === null).assertTrue();
    });

    it('missing_subscription_keeps_local_old_server_compat', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const quota: QuotaSnapshot = { giftRemaining: 1 };
      const merged: Entitlement = mergeQuotaSnapshot(baseEntitlement(), quota);
      const sub: SubscriptionInfo | null = merged.subscription;
      expect(sub !== null).assertTrue();
      expect(sub === null ? '' : sub.status).assertEqual('active');
      // 未回传的字段不能被 undefined 抹掉
      expect(merged.passes.length).assertEqual(0);
      expect(merged.usedToday).assertEqual(3);
      expect(merged.giftRemaining).assertEqual(1);
    });

    it('server_subscription_overrides_local', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const sub: SubscriptionInfo = { status: 'expired', periodEnd: '2026-11-01 00:00:00' };
      const quota: QuotaSnapshot = { subscription: sub };
      const merged: Entitlement = mergeQuotaSnapshot(baseEntitlement(), quota);
      const got: SubscriptionInfo | null = merged.subscription;
      expect(got !== null).assertTrue();
      expect(got === null ? '' : got.status).assertEqual('expired');
      expect(got === null ? '' : got.periodEnd).assertEqual('2026-11-01 00:00:00');
    });

    it('has_pass_matches_trip_only', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, async () => {
      const passEnt: Entitlement = {
        subscription: null,
        passes: [{ localTripId: 'trip-owned', status: 'active', expiresAt: null }],
        giftRemaining: 0, usedToday: 0, dailyCap: 20
      };
      await EntitlementStore.update(passEnt);
      expect(EntitlementStore.hasPass('trip-owned')).assertTrue();
      expect(EntitlementStore.hasPass('trip-other')).assertFalse();
    });

    it('update_bumps_tick_for_open_pages', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, async () => {
      // 「我的」会员卡靠这个 tick 在买完返回时即时刷新（pop 回来不触发 onShow）
      await EntitlementStore.update(baseEntitlement());
      const tick: number = AppStorage.get<number>(EntitlementStore.TICK_KEY) ?? 0;
      expect(tick > 0).assertTrue();
    });

    it('admin_unlimited_bypasses_generate_gate', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, async () => {
      // 管理员由 BFF 白名单下发 unlimited：额度用满也不该被端侧拦下
      const admin: Entitlement = {
        subscription: null, passes: [], giftRemaining: 0, usedToday: 25, dailyCap: 20, unlimited: true
      };
      await EntitlementStore.update(admin);
      expect(EntitlementStore.canGenerate()).assertTrue();

      const normal: Entitlement = {
        subscription: null, passes: [], giftRemaining: 0, usedToday: 25, dailyCap: 20
      };
      await EntitlementStore.update(normal);
      expect(EntitlementStore.canGenerate()).assertFalse();
    });

    it('daily_cap_follows_server', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const quota: QuotaSnapshot = { dailyCap: 20, remainingToday: 7 };
      const merged: Entitlement = mergeQuotaSnapshot(baseEntitlement(), quota);
      expect(merged.dailyCap).assertEqual(20);
      expect(merged.usedToday).assertEqual(7);
    });
  });
}
