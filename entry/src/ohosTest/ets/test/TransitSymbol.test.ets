/**
 * 通勤图标映射回归（utils/TransitSymbol）。
 * 这个映射原来写在 ItineraryPage 私有方法里，屏15 抄了一份写死的汽车图标，
 * 下一段是地铁/公交时显示错误车标——提取共用后一直没有用例守着。
 * 断言的是 keyOf（字符串），因为 Resource 没有可比的值。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { TransitSymbol } from '../../../main/ets/utils/TransitSymbol';

const KEYS: string[] = ['subway', 'bus', 'taxi', 'car', 'bicycle', 'airplane', 'walk'];

export default function transitSymbolTest(): void {
  describe('TransitSymbol 映射', () => {
    it('synonyms_land_on_the_same_key', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      for (const m of ['地铁 2 号线', '轨道交通', '轻轨']) {
        expect(TransitSymbol.keyOf(m)).assertEqual('subway');
      }
      for (const m of ['公交 87路', '旅游巴士']) {
        expect(TransitSymbol.keyOf(m)).assertEqual('bus');
      }
      for (const m of ['打车', '出租车', '网约车']) {
        expect(TransitSymbol.keyOf(m)).assertEqual('taxi');
      }
      for (const m of ['共享单车', '骑行']) {
        expect(TransitSymbol.keyOf(m)).assertEqual('bicycle');
      }
      for (const m of ['机场快线', '航班', '飞机']) {
        expect(TransitSymbol.keyOf(m)).assertEqual('airplane');
      }
    });

    it('unknown_mode_falls_back_to_walk', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      // 兜底必须是步行（行程里最常见的一段），不能是汽车：屏15 原来就写死汽车
      expect(TransitSymbol.keyOf('')).assertEqual('walk');
      expect(TransitSymbol.keyOf('缆车')).assertEqual('walk');
      expect(TransitSymbol.keyOf('轮渡')).assertEqual('walk');
    });

    it('every_key_resolves_to_a_resource', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      // of() 不能对任何已知键返回空：$r 拼错名字编译期不报，运行时才画不出来
      for (const k of KEYS) {
        const r: Resource = TransitSymbol.of(k);
        expect(r === null || r === undefined).assertFalse();
      }
    });

    it('mode_order_prefers_the_more_specific_match', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      // 「机场巴士」同时含「机场」和「巴士」：识别顺序里 bus 在前，
      // 落地面接驳而不是飞机——顺序改了这条就红，是有意锁住的
      expect(TransitSymbol.keyOf('机场巴士')).assertEqual('bus');
      expect(TransitSymbol.keyOf('机场大巴')).assertEqual('airplane');
    });
  });
}
