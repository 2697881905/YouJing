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
  if (code === ErrorCode.MAP_CITY_DATA_FAILED) {
    return '地图数据没取到';
  }
  if (code === ErrorCode.TRIP_NO_SPOT_SELECTED) {
    return '还没选景点';
  }
  if (code === ErrorCode.TRIP_NO_AREA_SELECTED) {
    return '还没选住宿区域';
  }
  // 云端三兄弟此前没有文案、全落进「生成没能完成」：用户看不出该做什么。
  if (code === ErrorCode.CLOUD_TOKEN_INVALID) {
    return '登录状态过期了';
  }
  if (code === ErrorCode.CLOUD_RATE_LIMITED) {
    return '请求太频繁';
  }
  if (code === ErrorCode.CLOUD_IDEMPOTENCY_CONFLICT) {
    return '这次请求和上一次重复';
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
  if (code === ErrorCode.MAP_CITY_DATA_FAILED) {
    return '地图服务没有返回这座城市的景点或住宿区，检查网络后再试';
  }
  if (code === ErrorCode.TRIP_NO_SPOT_SELECTED) {
    return '至少要选 1 个景点才排得出行程';
  }
  if (code === ErrorCode.TRIP_NO_AREA_SELECTED) {
    return '要先定下住哪一片，通勤起点才算得出来';
  }
  if (code === ErrorCode.CLOUD_TOKEN_INVALID) {
    return '重新打开应用会自动恢复登录；还不行就到「我的」里重新登录';
  }
  if (code === ErrorCode.CLOUD_RATE_LIMITED) {
    return '等一分钟再试；重试不会再扣一次额度';
  }
  if (code === ErrorCode.CLOUD_IDEMPOTENCY_CONFLICT) {
    return '再点一次生成就好，不会重复扣额度';
  }
  return '原因已记进本机日志，可以先按下面的方法调整再试';
}
