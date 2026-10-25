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
  /** 连接建立超时（毫秒）。 */
  CONNECT_TIMEOUT_MS: number;
  /**
   * 响应读取超时（毫秒）。整程 Trip JSON 的生成可能需要 1–2 分钟，给足余量；
   * 超时按 NETWORK_TIMEOUT 报（屏7 文案「网络不通或超时」），不再谎报成普通请求失败。
   */
  READ_TIMEOUT_MS: number;
}

export const ApiConfig: ApiConfigType = {
  BASE_URL: '',
  LLM_CHAT_ENDPOINT: '',
  API_KEY: '',
  CONNECT_TIMEOUT_MS: 10000,
  READ_TIMEOUT_MS: 120000
};
