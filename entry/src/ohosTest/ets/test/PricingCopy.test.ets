/**
 * 付费页文案口径的回归：订阅用户用满每月额度后，不能再说「解锁」「生成免费」。
 *
 * 触发路径：GeneratingPage 把所有 `CLOUD_QUOTA_EXHAUSTED` 都跳 PricingPage，
 * 其中包含「已订阅但本月 20 次用完」的人。文案错在这里直接误导已付费用户。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { pricingHeadline, pricingSubtitle } from '../../../main/ets/utils/PricingCopy';

export default function pricingCopyTest(): void {
  describe('PricingCopy', () => {
    it('subscriber_at_cap_explains_quota_not_unlock', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      expect(pricingHeadline(true, 20, 20)).assertEqual('本月次数已用完');
      expect(pricingSubtitle(true, 20, 20))
        .assertEqual('订阅每月 20 次，下月 1 日恢复；单个行程通行证可立即继续');
    });

    it('subscriber_below_cap_keeps_default', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      expect(pricingHeadline(true, 3, 20)).assertEqual('解锁完整行程');
      expect(pricingSubtitle(true, 3, 20)).assertEqual('生成免费，导出与无限重排需解锁');
    });

    it('gift_user_at_cap_keeps_default', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // 没订阅的人用尽赠送：付费页的默认口径本来就成立
      expect(pricingHeadline(false, 20, 20)).assertEqual('解锁完整行程');
      expect(pricingSubtitle(false, 20, 20)).assertEqual('生成免费，导出与无限重排需解锁');
    });

    it('unknown_cap_falls_back_to_default', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // 缓存里还没有 dailyCap（旧数据/未刷新）时不能算出「已用完」
      expect(pricingHeadline(true, 0, 0)).assertEqual('解锁完整行程');
    });
  });
}
