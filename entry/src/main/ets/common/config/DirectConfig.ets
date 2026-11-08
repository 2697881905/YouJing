/**
 * 开发期端侧直连 LLM 配置（P0 兜底，不上架）。
 *
 * 为什么单独一个文件：ApiConfig 是 skip-worktree，仓库 HEAD 里没有新增字段，
 * 直接往里加 KEY 会让干净检出编译失败（P1 的 PickConfig 同因）。
 *
 * 用法：
 * 1. URL 填完整的 OpenAI 兼容 chat/completions 地址；
 * 2. KEY 填真实 Key；
 * 3. 填好后执行
 *    git update-index --skip-worktree entry/src/main/ets/common/config/DirectConfig.ets
 *    防误提交；
 * 4. 同时把 ApiConfig.BFF_BASE_URL 置空，GenerationChannel 判 isLocal=true：
 *    跳过设备票据/权益门禁，LlmClient 优先走本直连（不是 Mock）；
 *    PickClient 在无 AGC/BFF 时也走本直连。
 *
 * 两项任一为空 = 不启用直连，回退 BFF（配了）或本地合成（没配）。
 * 上架前必须迁云（AGC 云函数或 BFF），发布包不能带 Key。
 */

export interface DirectConfigType {
  URL: string;
  KEY: string;
  MODEL: string;
  MAX_TOKENS: number;
}

export const DirectConfig: DirectConfigType = {
  URL: 'https://api.deepseek.com/v1/chat/completions',
  KEY: 'sk-5743b6ca85d344239d64a01909a16669',
  MODEL: 'deepseek-chat',
  MAX_TOKENS: 8192
};
