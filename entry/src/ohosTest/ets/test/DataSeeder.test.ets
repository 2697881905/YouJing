/**
 * 阶段 5 种子数据回归：JSONL→模型映射纯函数 + 真机 rawfile 行数验收
 * （验收线：每城景点 30-50、区域 35-50）。
 * 2026-10-25 起 toSpot/toArea 返回 `Spot | null`：坏行跳过而不是在首启炸掉启动。
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
      const spot = DataSeeder.toSpot(SAMPLE_SPOT, '北京');
      expect(spot === null).assertFalse();
      if (spot === null) {
        return;
      }
      expect(spot.id).assertEqual('bj-001');
      expect(spot.city).assertEqual('北京');
      expect(spot.tags.length).assertEqual(2);
      expect(spot.tags[0]).assertEqual(SpotTag.MUST_SEE);
      expect(spot.booking.requiresBooking).assertTrue();
      expect(spot.booking.advanceDays).assertEqual(7);
      expect(spot.booking.closedDay).assertEqual('周一');
      expect(spot.latitude > 39.9 && spot.longitude > 116.4).assertTrue();
      expect(spot.provenance.source).assertEqual('seed-v1');
      // 无坐标 → 区中心兜底，可信度记「低」
      expect(spot.provenance.confidence).assertEqual('低');
    });

    it('toSpot_geo_confidence', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const withGeo: string =
        '{"id":"bj-002","n":"颐和园","d":"海淀区","t":["classic"],"dur":180,"pop":90,"la":39.999,"lo":116.275}';
      const spot = DataSeeder.toSpot(withGeo, '北京');
      expect(spot === null).assertFalse();
      if (spot === null) {
        return;
      }
      expect(spot.latitude).assertEqual(39.999);
      expect(spot.provenance.source).assertEqual('seed-v2-geo');
      expect(spot.provenance.confidence).assertEqual('中');
    });

    it('toSpot_bad_rows_return_null', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      // 坏 JSON / 缺 id / 缺 name：跳过该行，不在首启动 bootstrap 里抛
      expect(DataSeeder.toSpot('{bad json', '北京')).assertNull();
      expect(DataSeeder.toSpot('{"n":"没id","d":"东城区"}', '北京')).assertNull();
      expect(DataSeeder.toSpot('{"id":"x"}', '北京')).assertNull();
    });

    it('toSpot_missing_booking_degrades', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      // bk 整组缺失时不再 TypeError：预约字段全 undefined，需预约为 false
      const spot = DataSeeder.toSpot('{"id":"bj-003","n":"某公园","d":"东城区","dur":60,"pop":50}', '北京');
      expect(spot === null).assertFalse();
      if (spot === null) {
        return;
      }
      expect(spot.booking.requiresBooking).assertFalse();
      expect(spot.booking.bookingMethod).assertUndefined();
      // 简介种子没采：留空，不拿「名称（区）」冒充
      expect(spot.brief).assertEqual('');
    });

    it('toSpot_filters_unknown_tags', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const spot = DataSeeder.toSpot(
        '{"id":"bj-004","n":"某地","d":"东城区","t":["must_see","bogus","classic"],"dur":60,"pop":50}', '北京');
      expect(spot === null).assertFalse();
      if (spot === null) {
        return;
      }
      expect(spot.tags.length).assertEqual(2);
      expect(spot.tags[1]).assertEqual(SpotTag.CLASSIC);
    });

    it('toArea_mapping', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const area = DataSeeder.toArea(SAMPLE_AREA, '北京');
      expect(area === null).assertFalse();
      if (area === null) {
        return;
      }
      expect(area.id).assertEqual('bja-001');
      expect(area.anchorStations.length).assertEqual(2);
      expect(area.priceTier).assertEqual(AreaPriceTier.COMFORT);
      expect(area.group).assertEqual(AreaGroup.CORE);
      expect(area.airportMinutes).assertEqual(45);
      // 无坐标不落点（0 会被 MapStops.usable 滤掉）；描述留空
      expect(area.latitude).assertEqual(0);
      expect(area.description).assertEqual('');
    });

    it('toArea_whitelist_fallback', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      const area = DataSeeder.toArea(
        '{"id":"bja-009","n":"某片","g":"bogus","tier":"bogus","st":[],"lines":[],"air":1,"train":1,"din":"中","crowds":[]}',
        '北京');
      expect(area === null).assertFalse();
      if (area === null) {
        return;
      }
      // 陌生枚举落默认档，不把脏值写进库
      expect(area.group).assertEqual(AreaGroup.METRO);
      expect(area.priceTier).assertEqual(AreaPriceTier.COMFORT);
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
