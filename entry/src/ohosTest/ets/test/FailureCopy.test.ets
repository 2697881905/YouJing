/**
 * 错误码 → 文案映射回归（屏7）。纯函数，可在 hypium 内跑。
 * 目的：保证屏7 说人话且每个已定义的错误码都有归属，不出现空标题。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { failureHeadline } from '../../../main/ets/common/error/FailureCopy';
import { ErrorCode } from '../../../main/ets/common/error/ErrorCode';

export default function failureCopyTest(): void {
  describe('FailureCopy', () => {
    it('known_codes_have_headlines', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(failureHeadline(ErrorCode.TRIP_GENERATE_RETRY_EXHAUSTED)).assertEqual('试了两次都没排通');
      expect(failureHeadline(ErrorCode.TYPE_GUARD_FAILED)).assertEqual('AI 给的行程缺关键信息');
      expect(failureHeadline(ErrorCode.SCHEMA_VALIDATION_FAILED)).assertEqual('AI 给的行程缺关键信息');
      expect(failureHeadline(ErrorCode.LLM_UNAVAILABLE)).assertEqual('连不上行程服务');
      expect(failureHeadline(ErrorCode.NETWORK_TIMEOUT)).assertEqual('网络不通或超时');
      expect(failureHeadline(ErrorCode.TRIP_NO_SPOT_SELECTED)).assertEqual('还没选景点');
      expect(failureHeadline(ErrorCode.TRIP_NO_AREA_SELECTED)).assertEqual('还没选住宿区域');
    });

    it('unknown_code_falls_back_not_empty', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(failureHeadline(0)).assertEqual('生成没能完成');
      expect(failureHeadline(9999)).assertEqual('生成没能完成');
      // 存储区段（3xxx）不该被当成生成问题文案，走兜底
      expect(failureHeadline(ErrorCode.RDB_TRANSACTION_FAILED)).assertEqual('生成没能完成');
    });
  });
}
