/**
 * @kit.BasicServicesKit 的离线替身（只给 skill_check 用）。
 * 脚本只用 BusinessError 的 code/message 两个字段。
 */
export interface BusinessError {
  code: number;
  message: string;
}
