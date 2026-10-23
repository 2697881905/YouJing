/**
 * 错误码 → 用户可读标题（屏7 生成受阻用）。
 *
 * 单独成文件而不是写在页面里：这是纯映射，可以进 hypium 回归；
 * 页面只负责排版。错误码分区见同目录 ErrorCode.ets。
 */

import { ErrorCode } from './ErrorCode';

export function failureHeadline(code: number): string {
  if (code === ErrorCode.TRIP_GENERATE_RETRY_EXHAUSTED) {
    return '试了两次都没排通';
  }
  if (code === ErrorCode.SCHEMA_VALIDATION_FAILED || code === ErrorCode.TYPE_GUARD_FAILED ||
    code === ErrorCode.JSON_PARSE_FAILED) {
    return 'AI 给的行程缺关键信息';
  }
  if (code === ErrorCode.LLM_UNAVAILABLE) {
    return '连不上行程服务';
  }
  if (code === ErrorCode.NETWORK_REQUEST_FAILED || code === ErrorCode.NETWORK_TIMEOUT) {
    return '网络不通或超时';
  }
  if (code === ErrorCode.TRIP_NO_SPOT_SELECTED) {
    return '还没选景点';
  }
  if (code === ErrorCode.TRIP_NO_AREA_SELECTED) {
    return '还没选住宿区域';
  }
  return '生成没能完成';
}
