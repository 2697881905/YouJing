/**
 * BFF HTTP 错误 → 端侧 ErrorCode（纯映射，可进 hypium）。
 *
 * 为什么单独成文件：服务端 5xx 里混着两类完全不同的失败——
 * - 上游/网络问题（LLM_UPSTREAM_ERROR）：用户该等一会儿；
 * - 模型内容问题（LLM_INVALID_TRIP / LLM_INVALID_JSON）：已经重试/修正过仍不合格，
 *   屏7 应该说「两次都没排通」，而不是「连不上行程服务」（用户会去查网络）。
 * 以前端侧对所有 >=500 一律报 LLM_UNAVAILABLE，把后者也说成网络问题。
 */

import { ErrorCode } from '../common/error/ErrorCode';

export function bffErrorCode(status: number, bodyText: string): number {
  if (status === 401) {
    return ErrorCode.CLOUD_TOKEN_INVALID;
  }
  if (status === 402) {
    return ErrorCode.CLOUD_QUOTA_EXHAUSTED;
  }
  if (status === 429) {
    return ErrorCode.CLOUD_RATE_LIMITED;
  }
  if (status === 409) {
    return ErrorCode.CLOUD_IDEMPOTENCY_CONFLICT;
  }
  if (status >= 500) {
    let error: string = '';
    try {
      const parsed: Record<string, Object> = JSON.parse(bodyText) as Record<string, Object>;
      const raw: Object | undefined = parsed['error'];
      error = typeof raw === 'string' ? raw : '';
    } catch (err) {
      error = '';
    }
    if (error === 'LLM_INVALID_TRIP' || error === 'LLM_INVALID_JSON') {
      return ErrorCode.TRIP_GENERATE_RETRY_EXHAUSTED;
    }
    return ErrorCode.LLM_UNAVAILABLE;
  }
  return ErrorCode.NETWORK_REQUEST_FAILED;
}
