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

/**
 * 错误码 → 用户可读的一句原因（屏7 标题下面那行）。
 *
 * 为什么另起一个函数而不是直接把 `err.message` 铺上去：真机截图里出现过
 * 「两次生成均失败: days 不能为空数组」——那是 `TripParser` 的校验术语，
 * 用户既读不懂也不知道该做什么。原始诊断只该进日志和**明确标注的调试行**，
 * 主副标题两版（debug/release）必须一致。
 */
export function failureDetail(code: number): string {
  if (code === ErrorCode.TRIP_GENERATE_RETRY_EXHAUSTED) {
    return '连着两次拿到的排期都没能拆成可用的一天';
  }
  if (code === ErrorCode.SCHEMA_VALIDATION_FAILED || code === ErrorCode.TYPE_GUARD_FAILED ||
    code === ErrorCode.JSON_PARSE_FAILED) {
    return '返回的行程里缺了日期或站点，落不成行程';
  }
  if (code === ErrorCode.LLM_UNAVAILABLE) {
    return '行程服务没有响应';
  }
  if (code === ErrorCode.NETWORK_REQUEST_FAILED || code === ErrorCode.NETWORK_TIMEOUT) {
    return '请求超时或网络不通';
  }
  if (code === ErrorCode.TRIP_NO_SPOT_SELECTED) {
    return '至少要选 1 个景点才排得出行程';
  }
  if (code === ErrorCode.TRIP_NO_AREA_SELECTED) {
    return '要先定下住哪一片，通勤起点才算得出来';
  }
  return '原因已记进本机日志，可以先按下面的方法调整再试';
}
