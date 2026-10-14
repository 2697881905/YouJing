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
}

export const ApiConfig: ApiConfigType = {
  BASE_URL: '',
  LLM_CHAT_ENDPOINT: ''
};
