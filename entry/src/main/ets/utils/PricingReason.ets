/**
 * 「这一趟进付费页是为了什么」的一次性说明位。
 *
 * 为什么要有它：付费页原来只能按权益缓存猜标题（赠送用完 ⇒「免费次数已用完」）。
 * 但被**导出**门禁拦进来的人，刚做的动作不是生成，而是点「导出日历 / 海报」——
 * 真机实拍到他从导出走到「免费次数已用完」这句上，答非所问。
 * 同屏 toast 也试过：`toast()` 后紧跟 `pushPath` 时提示不会显示出来（截图里根本没有），
 * 所以反馈必须落在**目的页的标题**上，而不是出发页的浮层。
 *
 * 取用即清（`takeExportGate`），避免下一次正常进付费页还挂着这条理由。
 * 出发页只调 `markExportGate()` 后**沿用自己的 pathStack** 跳转——
 * 各标签页的栈不是同一个（屏8 有过用错全局栈导致分享/编辑全推错的先例）。
 */
const KEY: string = 'pricingReasonExportGate';

export class PricingReason {
  /** 出发页调用：这次跳付费页是因为导出被门禁拦住 */
  static markExportGate(): void {
    AppStorage.setOrCreate<boolean>(KEY, true);
  }

  /** 付费页读取并复位：读到 true 就换成导出口径的标题 */
  static takeExportGate(): boolean {
    const on: boolean = AppStorage.get<boolean>(KEY) === true;
    if (on) {
      AppStorage.setOrCreate<boolean>(KEY, false);
    }
    return on;
  }

  /** 离开付费页时兜底复位（用户从别的入口进来时不该残留） */
  static clear(): void {
    AppStorage.setOrCreate<boolean>(KEY, false);
  }
}
