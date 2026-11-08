/**
 * P1 AI 精选云函数配置（AGC 版，无自购服务器）。
 *
 * URL 为空时 PickClient 回退到 ApiConfig.BFF_BASE_URL + /v1/pick/spots（本地联调）。
 * 部署 cloud/pickSpots 后把 HTTP 触发器 URL 填到 URL，TOKEN 与云函数
 * YOUJING_PICK_TOKEN 保持一致；两者都不是密钥级机密，但不要填 LLM Key。
 */
export interface PickConfigType {
  URL: string;
  TOKEN: string;
}

export const PickConfig: PickConfigType = {
  URL: '',
  TOKEN: ''
};
