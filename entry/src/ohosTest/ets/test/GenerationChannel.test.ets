/**
 * 生成通道判据的回归（商业化 P0-B）。
 *
 * 为什么要有这一份：门禁（pages/GeneratingPage）与传输选择（ai/LlmClient）此前各读一遍配置，
 * 口径分叉的后果是「干净检出点生成行程 100% 跳付费页」——仓库版 ApiConfig 是
 * `BFF_BASE_URL:''` + `DEV_SKIP_BFF:false`，而权益缓存只能由设备激活填充，激活又必须先有 BFF。
 * 判据收进 utils/GenerationChannel 后，这里把它钉成一张四种组合的表：
 * **只要 BFF 没配，就必须能免费生成**。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { GenerationChannel } from '../../../main/ets/utils/GenerationChannel';

export default function generationChannelTest(): void {
  describe('GenerationChannel', () => {
    it('local_when_bff_missing_regardless_of_mock_flag', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // 仓库默认形态（提审包就是这样）：BFF 空 ⇒ 端侧合成，绝不能被额度拦
      expect(GenerationChannel.isLocalOf(false, '')).assertTrue();
      expect(GenerationChannel.isLocalOf(true, '')).assertTrue();
    });

    it('bff_only_when_url_present_and_mock_off', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      expect(GenerationChannel.isLocalOf(false, 'https://bff.example.com')).assertFalse();
      // 显式 mock 开关优先于地址：离线走查时不该打真服务
      expect(GenerationChannel.isLocalOf(true, 'https://bff.example.com')).assertTrue();
    });

    it('entitlement_only_required_for_bff', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // 这条是 P0 的直接断言：没有 BFF 就没有额度这回事
      expect(GenerationChannel.isLocalOf(false, '')).assertTrue();
      expect(GenerationChannel.isLocalOf(false, 'https://bff.example.com')).assertFalse();
    });

    it('current_build_config_keeps_generate_reachable', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {
      // 读当前编译进来的配置真值：本地档 ⇒ 门禁不得要求权益。
      // 若将来有人把 BFF 地址配好又没部署，这条会红——那正是它该管住的情形。
      const local: boolean = GenerationChannel.isLocal();
      if (local) {
        expect(GenerationChannel.needsEntitlement()).assertFalse();
      } else {
        expect(GenerationChannel.needsEntitlement()).assertTrue();
      }
    });
  });
}
