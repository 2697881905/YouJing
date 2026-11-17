/**
 * 手表 BFF 连接配置（切片0 探针 / 后续切片共用）。
 *
 * 部署后把 WATCH_BFF_BASE_URL 改成实际公网地址（必须是 HTTPS，证书有效）。
 * 当前 bff.youju.chat 尚未部署（G0-N-a 未通过），探针会明确显示「未连接」。
 */

export const WATCH_BFF_BASE_URL: string = 'https://bff.youju.chat';
export const WATCH_CONNECT_TIMEOUT_MS: number = 8000;
export const WATCH_READ_TIMEOUT_MS: number = 15000;
