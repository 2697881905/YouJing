/**
 * 导出放行判定的回归（商业化 §4.2）。
 *
 * 旧实现要求「缓存必须 5 分钟内」，过期即拒：付费用户在最后一次生成 5 分钟后、
 * 或离线时永远导不出（而导出的是本机文件，服务端根本感知不到）。
 * 现在判据只有身份 + 权益，不看缓存新鲜度；无权益/游客仍拒绝。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { exportAllowed } from '../../../main/ets/data/EntitlementStore';

export default function entitlementExportTest(): void {
  describe('EntitlementExport', () => {
    it('dev_bypass_always_allows', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      expect(exportAllowed(true, true, false, false)).assertTrue();
    });

    it('guest_always_denied_even_with_entitlement', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      expect(exportAllowed(false, true, true, true)).assertFalse();
    });

    it('subscriber_allows_without_fresh_cache', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // 判据里没有「缓存新鲜度」这个入参，就是这条语义本身
      expect(exportAllowed(false, false, true, false)).assertTrue();
    });

    it('pass_holder_allows_and_nobody_holds_denies', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      expect(exportAllowed(false, false, false, true)).assertTrue();
      expect(exportAllowed(false, false, false, false)).assertFalse();
    });
  });
}
