/**
 * 生成门禁的回归（`EntitlementStore.canGenerate` 的纯判定部分）。
 *
 * 旧实现里订阅分支直接 `return used < cap`：订阅用户用满每月额度后，
 * 即使手里有**该行程的通行证**也会被端上先拦下，服务端 `determineQuotaSource`
 * 根本没机会按 pass 放行。通行证按方案是「该行程无限生成」的付费权益。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { generateAllowed } from '../../../main/ets/data/EntitlementStore';

export default function entitlementGateTest(): void {
  describe('EntitlementGenerate', () => {
    it('subscriber_below_cap_allows', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      expect(generateAllowed(true, 3, 20, false, false)).assertTrue();
    });

    it('subscriber_at_cap_with_pass_allows', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // 回归：订阅满额 + 通行证 ⇒ 必须放行（服务端会选 pass）
      expect(generateAllowed(true, 20, 20, true, false)).assertTrue();
    });

    it('subscriber_at_cap_without_pass_denies', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      expect(generateAllowed(true, 20, 20, false, false)).assertFalse();
    });

    it('gift_quota_allows_when_no_paid_entitlement', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      expect(generateAllowed(false, 0, 20, false, true)).assertTrue();
      expect(generateAllowed(false, 0, 20, false, false)).assertFalse();
    });
  });
}
