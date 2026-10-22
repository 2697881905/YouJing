/**
 * 错误码常量表 · 全工程唯一定义点。
 *
 * 区段划分规则：
 *   1xxx 网络（http 请求、LLM 服务调用）
 *   2xxx JSON / 解析（response_format、类型守卫，服务开发文档 §4.3 三层防线）
 *   3xxx 存储（RDB 建库、迁移、事务、查询）
 *   4xxx 业务规则（行程生成前置校验与流程约束）
 *   5xxx 账号（UnionID 静默登录、登录态持久化）
 * 码值全局唯一不得重复；新增错误码只能在所属区段内顺延追加。
 */

export class ErrorCode {
  // ---- 1xxx 网络 ----
  static readonly NETWORK_REQUEST_FAILED: number = 1001; // 网络请求失败（连接错误或非 2xx 响应）
  static readonly NETWORK_TIMEOUT: number = 1002; // 网络请求超时
  static readonly LLM_UNAVAILABLE: number = 1003; // LLM 服务不可用（小艺 Skill 或直连 API 无响应）

  // ---- 2xxx JSON / 解析 ----
  static readonly JSON_PARSE_FAILED: number = 2001; // LLM 返回内容不是合法 JSON
  static readonly SCHEMA_VALIDATION_FAILED: number = 2002; // JSON 未通过 Schema 校验（字段缺失或枚举越界）
  static readonly TYPE_GUARD_FAILED: number = 2003; // ArkTS 类型守卫逐字段校验失败，无法构造 Trip 对象

  // ---- 3xxx 存储（RDB）----
  static readonly RDB_INIT_FAILED: number = 3001; // RdbStore 初始化或建库失败
  static readonly RDB_MIGRATION_FAILED: number = 3002; // 数据库版本迁移（onUpgrade）失败
  static readonly RDB_TRANSACTION_FAILED: number = 3003; // 写事务执行失败（含 busy 冲突）
  static readonly RDB_QUERY_FAILED: number = 3004; // 查询失败或 ResultSet 逐列收口异常

  // ---- 4xxx 业务规则 ----
  static readonly TRIP_DATE_RANGE_INVALID: number = 4001; // 出发/返程日期区间不合法
  static readonly TRIP_NO_SPOT_SELECTED: number = 4002; // 未选择任何景点即请求生成行程
  static readonly TRIP_NO_AREA_SELECTED: number = 4003; // 未选择住宿区域即请求生成行程
  static readonly TRIP_GENERATE_RETRY_EXHAUSTED: number = 4004; // 行程生成重试一次后仍失败，进入降级/提示

  // ---- 5xxx 账号 ----
  static readonly ACCOUNT_LOGIN_FAILED: number = 5001; // UnionID 静默登录失败（未登录华为账号 / AGC 未配置）
  static readonly ACCOUNT_PREFERENCES_FAILED: number = 5002; // 登录态持久化读写失败
}
