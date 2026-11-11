/**
 * 海报 / AI 生图门禁的回归（2026-11-11 决策：只认有效订阅）。
 *
 * 与 EntitlementExport.test.ets 的差别要固定住：ICS 等通用导出仍允许通行证，
 * 海报分享与生图不再允许。否则一次「顺手复用 canExport」就把收紧的口径退回去了。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { posterAllowed, exportAllowed } from '../../../main/ets/data/EntitlementStore';

export default function posterEntitlementTest(): void {
  describe('PosterEntitlement', () => {
    it('dev_bypass_always_allows', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      expect(posterAllowed(true, true, false)).assertTrue();
    });

    it('guest_denied_even_with_subscription', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      expect(posterAllowed(false, true, true)).assertFalse();
    });

    it('subscriber_allows_and_nonsubscriber_denied', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      expect(posterAllowed(false, false, true)).assertTrue();
      expect(posterAllowed(false, false, false)).assertFalse();
    });

    it('pass_still_allows_ics_but_not_poster', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      expect(exportAllowed(false, false, false, true)).assertTrue();
      expect(posterAllowed(false, false, false)).assertFalse();
    });
  });
}
