/**
 * 阶段 5 种子数据回归：JSONL→模型映射纯函数 + 真机 rawfile 行数验收
 * （验收线：每城景点 30-50、区域 35-50）。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { util } from '@kit.ArkTS';
import { DataSeeder } from '../../../main/ets/data/DataSeeder';
import { SpotTag } from '../../../main/ets/model/Spot';
import { AreaGroup, AreaPriceTier } from '../../../main/ets/model/Area';

const SAMPLE_SPOT: string =
  '{"id":"bj-001","n":"故宫博物院","d":"东城区","t":["must_see","classic"],"dur":240,"pop":99,' +
  '"bk":{"req":true,"m":"官网/小程序预约","adv":7,"rel":"20:00","closed":"周一","diff":"难"}}';

const SAMPLE_AREA: string =
  '{"id":"bja-001","n":"王府井-东城核心","g":"core","tier":"comfort","st":["灯市口","东单"],' +
  '"lines":["1号线","5号线"],"air":45,"train":12,"din":"高","crowds":["首次来京","购物"]}';

async function countLines(path: string): Promise<number> {
  const ctx = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
  const bytes: Uint8Array = await ctx.resourceManager.getRawFileContent(path);
  const text: string = new util.TextDecoder().decodeToString(bytes);
  return text.split('\n').filter((l: string): boolean => l.trim().length > 0).length;
}

export default function dataSeederTest(): void {
  describe('DataSeeder', () => {
    it('toSpot_mapping', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const s = DataSeeder.toSpot(SAMPLE_SPOT, '北京');
      expect(s.id).assertEqual('bj-001');
      expect(s.city).assertEqual('北京');
      expect(s.tags.length).assertEqual(2);
      expect(s.tags[0]).assertEqual(SpotTag.MUST_SEE);
      expect(s.booking.requiresBooking).assertTrue();
      expect(s.booking.advanceDays).assertEqual(7);
      expect(s.booking.closedDay).assertEqual('周一');
      expect(s.latitude > 39.9 && s.longitude > 116.4).assertTrue();
      expect(s.provenance.source).assertEqual('seed-v1');
    });

    it('toArea_mapping', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const a = DataSeeder.toArea(SAMPLE_AREA, '北京');
      expect(a.id).assertEqual('bja-001');
      expect(a.anchorStations.length).assertEqual(2);
      expect(a.priceTier).assertEqual(AreaPriceTier.COMFORT);
      expect(a.group).assertEqual(AreaGroup.CORE);
      expect(a.airportMinutes).assertEqual(45);
    });

    const cities: string[] = ['beijing', 'shanghai', 'guangzhou', 'shenzhen'];
    cities.forEach((c: string) => {
      it(`seed_counts_${c}`, TestType.FUNCTION | Size.MEDIUMTEST | Level.LEVEL1, async () => {
        const spots: number = await countLines(`seed/spots_${c}.jsonl`);
        const areas: number = await countLines(`seed/areas_${c}.jsonl`);
        expect(spots >= 30 && spots <= 50).assertTrue();
        expect(areas >= 35 && areas <= 50).assertTrue();
      });
    });
  });
}
