/**
 * 华为账号登录配置 · 单点定义（开发文档 §6 阶段 8）。
 *
 * ACCOUNT_KIT_ENABLED 置 false 的原因：Account Kit 需在 AGC 侧配置 Client ID 并与
 * 签名证书指纹绑定，当前调试签名尚未挂到 AGC 应用，静默登录必然报错。
 * 置为 false 时 AccountStore 跳过真实请求、直接落本机游客分区；
 * AGC 配置就绪后只改本文件一处（同 ApiConfig 占位纪律，改动须全量重编）。
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
  ACCOUNT_KIT_ENABLED: false,
  PREFERENCES_NAME: 'youjing_account',
  KEY_UNION_ID: 'union_id',
  KEY_LOGIN_AT: 'login_at',
  GUEST_UID: 'local-guest'
};
