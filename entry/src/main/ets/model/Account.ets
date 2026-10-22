/**
 * 账号登录态模型（开发文档 §6 阶段 8：UnionID 登录态 + 数据按用户分区）。
 *
 * 只存 UnionID，不落手机号/邮箱等敏感字段（UnionID 登录响应本身也不含昵称）；uid 即 RDB 分区键。
 */

export enum AccountKind {
  /** 已取到华为 UnionID */
  HUAWEI = 'huawei',
  /** 未登录：数据留在本机游客分区 */
  GUEST = 'guest'
}

export interface AccountState {
  /** 分区键：UnionID，未登录时为 AccountConfig.GUEST_UID */
  uid: string;
  kind: AccountKind;
  /** 登录态写入时刻（ms），游客态为 0 */
  loginAt: number;
}
