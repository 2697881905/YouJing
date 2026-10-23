/**
 * 华为账号登录配置 · 单点定义（开发文档 §6 阶段 8）。
 *
 * AGC 侧已就绪（2026-10-23）：APP ID / Client ID 均为 6917619826312400726，
 * 调试签名 SHA256 指纹已登记，Client ID 与 APP ID 相同故无需在 module.json5 配 client_id。
 * 调试签名必须用 AGC 手动创建的 Profile（appIdentifier = APP ID）：DevEco 本地自动签名
 * 生成的 Profile 带随机 appIdentifier，Account Kit 会报 1001502003。
 * 置为 false 时 AccountStore 跳过真实请求、直接落本机游客分区；
 * 账号侧配置有变动时只改本文件一处（同 ApiConfig 占位纪律，改动须全量重编）。
 */

export interface AccountConfigType {
  /** 是否发起真实 UnionID 静默登录 */
  ACCOUNT_KIT_ENABLED: boolean;
  /** 登录态持久化分片名 */
  PREFERENCES_NAME: string;
  KEY_UNION_ID: string;
  KEY_LOGIN_AT: string;
  /** 未登录时的本机分区标识：游客数据即「保留于本地」的数据 */
  GUEST_UID: string;
}

export const AccountConfig: AccountConfigType = {
  ACCOUNT_KIT_ENABLED: true,
  PREFERENCES_NAME: 'youjing_account',
  KEY_UNION_ID: 'union_id',
  KEY_LOGIN_AT: 'login_at',
  GUEST_UID: 'local-guest'
};
