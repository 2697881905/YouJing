/**
 * 网络配置单点 · 全工程所有 URL / 端点常量只能定义在此文件。
 *
 * 注意：修改任何网络配置后必须全量重编并重装 HAP 才生效
 *（hvigor 增量构建可能不重编本文件的引用方）。
 */

export interface ApiConfigType {
  /**
   * 服务端基础地址。当前为占位空串：有径无自建后端（开发文档 §1.3），
   * 本项仅在启用「直连 LLM API」备选方案时取值（§2.4），具体值待该阶段决策后填入。
   */
  BASE_URL: string;
  /**
   * LLM 对话端点路径。占位空串，取值来源：小艺开放平台 Skill 接入协议（待调研，
   * 见 INIT_REPORT 待办）或备选直连 LLM 服务的接口文档。
   */
  LLM_CHAT_ENDPOINT: string;
  /**
   * LLM 直连鉴权 Key（Bearer）。占位空串：为空时请求不带 Authorization 头（只告警不阻断，
   * 兼容免鉴权的本地网关）。开发期把真值写进本文件，并执行
   * `git update-index --skip-worktree entry/src/main/ets/common/config/ApiConfig.ets`
   * 防误提交（与 build-profile.json5 签名配置同一套口径）；
   * 上架前必须迁进系统凭据存储并撤掉本明文位（Docs/LLM接入方案-2026-10-26.md §三-2）。
   */
  API_KEY: string;
  /**
   * 对话模型名。**必配**：OpenAI 兼容端点（DeepSeek 等）缺 model 字段直接 400，
   * 这一项此前没有落点（2026-10-27 直连实测抓到）。免鉴权本地网关可留空不发。
   *
   * 必须写**在售的真模型 id**（deepseek-flash / deepseek-v4-pro），不写退役别名：
   * 旧值 `deepseek-chat` 2026-07 起已退役，当前只是被服务端映射到 deepseek-flash，
   * 映射口径随时可变（改成 Pro 就是 13.5 元/百万 token 的输出价，端上毫无感知）。
   */
  LLM_MODEL: string;
  /**
   * 关闭思考模式（`thinking: {type:'disabled'}`）。deepseek-flash **默认开思考**，
   * 思维链 token 混在 completion_tokens 里按输出计费（2026-10-27 实测：直接请求带
   * reasoning_tokens，模型列表里默认 effort=high）。本 App 只要一段结构化 JSON，
   * 思考是纯成本，故关掉；若某天规划质量不够要换回思考，置 false 并接受账单上涨。
   */
  LLM_THINKING_DISABLED: boolean;
  /**
   * 单次输出上限（max_tokens）。非思考模式服务端默认只给 8K，长行程 JSON 可能被
   * 截断（finish_reason=length）→ TripParser 判失败 → 重试一次，等于双倍账单。
   * 16384 覆盖现有最长行程，0 = 不发送、用服务端默认。
   */
  LLM_MAX_TOKENS: number;
  /**
   * 端点是否支持 `response_format: json_schema`（§4.3 第二层防线 strict 模式）。
   * DeepSeek 实测回 "This response_format type is unavailable now" → 置 false 时
   * 退回 `json_object`，Schema 仍由第一层（Prompt 内嵌）+ 第三层（TripParser 守卫）兜。
   */
  SUPPORTS_JSON_SCHEMA: boolean;
  /** 连接建立超时（毫秒）。 */
  CONNECT_TIMEOUT_MS: number;
  /**
   * 响应读取超时（毫秒）。整程 Trip JSON 的生成可能需要 1–2 分钟，给足余量；
   * 超时按 NETWORK_TIMEOUT 报（屏7 文案「网络不通或超时」），不再谎报成普通请求失败。
   */
  READ_TIMEOUT_MS: number;
  /** 重排云函数地址。空串 = 不请求，直接走本地兜底（仓库默认值）。 */
  REPLAN_URL: string;
  /**
   * 云函数鉴权头 x-youjing-token 的值，必须等于云函数环境变量 YOUJING_REPLAN_TOKEN。
   * 开发期真值只写本机（skip-worktree 防误提交）；为空时不带该头，云函数回 401 → 本地兜底。
   */
  REPLAN_TOKEN: string;
  /** 重排客户端超时预算：连接 2 秒（方案 §3.5）。 */
  REPLAN_CONNECT_TIMEOUT_MS: number;
  /** 重排客户端超时预算：读取 6 秒（方案 §3.5）。 */
  REPLAN_READ_TIMEOUT_MS: number;
  /**
   * 天气端点（Open-Meteo，免 Key 免登录，公开地址可直接进仓库）。
   * 空串 = 不出天气行。只发当日首站坐标四舍五入到 0.1°，不发实时定位。
   */
  WEATHER_URL: string;
}

export const ApiConfig: ApiConfigType = {
  BASE_URL: '',
  LLM_CHAT_ENDPOINT: '',
  API_KEY: '',
  LLM_MODEL: 'deepseek-flash',
  LLM_THINKING_DISABLED: true,
  LLM_MAX_TOKENS: 16384,
  SUPPORTS_JSON_SCHEMA: false,
  CONNECT_TIMEOUT_MS: 10000,
  READ_TIMEOUT_MS: 120000,
  REPLAN_URL: '',
  REPLAN_TOKEN: '',
  REPLAN_CONNECT_TIMEOUT_MS: 2000,
  REPLAN_READ_TIMEOUT_MS: 6000,
  WEATHER_URL: 'https://api.open-meteo.com/v1/forecast'
};
