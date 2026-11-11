/**
 * 代理提醒失败分类（纯逻辑，不引 @kit，可进离线断言）。
 *
 * 为什么需要它：部分手机/平板对代理提醒有管控。系统在
 * VerifyCloudCapability 失败时，App 侧拿到的不是「能力未开通」，
 * 而是 1700002「The number of reminders exceeds the limit」。
 * 真机实测：本 App 有效提醒为 0 条时仍报 1700002，所以
 * 「1700002 + 0 条」必须判为能力未开通，而不是数量超限。
 */

export enum ReminderFailureKind {
  NONE = 'none',
  /** 代理提醒能力被管控/未开通 */
  CAPABILITY = 'capability',
  /** 本 App 提醒数量确实达到系统上限 */
  LIMIT = 'limit',
  /** 其他失败，页面按通用失败处理 */
  OTHER = 'other'
}

export class ReminderFailure {
  static classify(code: number, message: string, existingCount: number): ReminderFailureKind {
    if (code === 201 || message.indexOf('agentreminder') >= 0 ||
      message.indexOf('ungranted capability') >= 0) {
      return ReminderFailureKind.CAPABILITY;
    }
    if (code === 1700002) {
      return existingCount === 0 ? ReminderFailureKind.CAPABILITY : ReminderFailureKind.LIMIT;
    }
    return ReminderFailureKind.OTHER;
  }
}
