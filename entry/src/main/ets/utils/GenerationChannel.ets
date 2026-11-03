import { ApiConfig } from '../common/config/ApiConfig';
import { MockConfig } from '../common/config/MockConfig';

/**
 * 「这次生成走端侧规则引擎还是走 BFF」的唯一判据。
 *
 * 为什么收成一处：门禁（pages/GeneratingPage）与传输选择（ai/LlmClient）此前各读一遍配置。
 * 两边口径一分叉就会出现「放开门禁但传输仍打不通」的半成品付费墙——干净检出点「生成行程」
 * 100% 跳付费页那条 P0 正是这么来的（见 Docs/analysis/商业化链路真实验收-2026-11-03.md §5/§7）。
 */
export class GenerationChannel {
  /** 纯函数形态：把两个配置当入参，hypium 与离线脚本才能按四种组合断言，不必依赖构建期常量 */
  static isLocalOf(useMockData: boolean, bffBaseUrl: string): boolean {
    return useMockData || bffBaseUrl.length === 0;
  }

  /** 端侧合成 = 免费档，零 token 成本，不依赖任何 BFF 权益 */
  static isLocal(): boolean {
    return GenerationChannel.isLocalOf(MockConfig.USE_MOCK_DATA, ApiConfig.BFF_BASE_URL);
  }

  /** 只有真要打 BFF 时，才该问 BFF 侧额度；本地档被额度拦死是错的 */
  static needsEntitlement(): boolean {
    return !GenerationChannel.isLocal();
  }
}
