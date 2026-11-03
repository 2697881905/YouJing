/**
 * BFF 状态码/错误体 → 端侧错误码的回归。
 *
 * 关键分歧：502 可能来自上游故障（该等一会儿），也可能来自模型内容不合格
 * （BFF 已修正重问仍失败，屏7 应说「两次都没排通」）。以前端侧一律报 LLM_UNAVAILABLE。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { bffErrorCode } from '../../../main/ets/utils/BffErrorMap';
import { ErrorCode } from '../../../main/ets/common/error/ErrorCode';

export default function bffErrorMapTest(): void {
  describe('BffErrorMap', () => {
    it('content_errors_map_to_retry_exhausted', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const trip = JSON.stringify({ error: 'LLM_INVALID_TRIP', message: 'days: 缺字段' });
      const json = JSON.stringify({ error: 'LLM_INVALID_JSON', message: 'bad json' });
      expect(bffErrorCode(502, trip)).assertEqual(ErrorCode.TRIP_GENERATE_RETRY_EXHAUSTED);
      expect(bffErrorCode(502, json)).assertEqual(ErrorCode.TRIP_GENERATE_RETRY_EXHAUSTED);
    });

    it('upstream_errors_map_to_unavailable', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      const upstream = JSON.stringify({ error: 'LLM_UPSTREAM_ERROR' });
      expect(bffErrorCode(502, upstream)).assertEqual(ErrorCode.LLM_UNAVAILABLE);
      expect(bffErrorCode(503, 'not json at all')).assertEqual(ErrorCode.LLM_UNAVAILABLE);
    });

    it('known_statuses_map_to_their_codes', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      expect(bffErrorCode(401, '')).assertEqual(ErrorCode.CLOUD_TOKEN_INVALID);
      expect(bffErrorCode(402, '')).assertEqual(ErrorCode.CLOUD_QUOTA_EXHAUSTED);
      expect(bffErrorCode(429, '')).assertEqual(ErrorCode.CLOUD_RATE_LIMITED);
      expect(bffErrorCode(409, '')).assertEqual(ErrorCode.CLOUD_IDEMPOTENCY_CONFLICT);
      expect(bffErrorCode(400, '')).assertEqual(ErrorCode.NETWORK_REQUEST_FAILED);
    });
  });
}
