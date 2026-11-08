/**
 * P5 实况窗开关。
 *
 * 当前 AGC 实况窗权益未开通（startLiveViewByTrigger → 1003500005），
 * 保持 false，避免每次到站都发一次必败请求。
 * 权益/Profile 通过后改为 true 即可启用 OnTripPage 的到站实况窗。
 */
export class LiveViewConfig {
  static readonly ENABLED: boolean = false;
}
