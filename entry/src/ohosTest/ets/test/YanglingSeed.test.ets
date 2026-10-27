/**
 * 杨凌种子数据验收（用户所在城市，2026-10-26 加的第 5 座城）。
 *
 * 为什么不复用 `DataSeeder.test.ets` 里那个城市循环：那条钉的是
 * "每城景点 30-50、区域 35-50"的验收线，而杨凌是**手写的真实 POI**，
 * 只有 10 景点 / 5 区域——塞进那个循环会红，把阈值调低又会把四座大城的质量线一起废掉。
 * 所以这里钉的是杨凌该钉的三件事：
 *   ① 文件在、行数达到下限（有人误删行要能发现）；
 *   ② 每一行都能被 toSpot/toArea 解析（坏行首启会静默跳过，不炸启动，所以必须主动数）；
 *   ③ 坐标落在杨凌的框里——这是最要紧的一条：我给的经纬度是从公开道路/村落位置推算的
 *      近似值，写错一位就会落到西安甚至宝鸡，地图页照样画得出点，肉眼看不出来。
 * 外加区中心兜底：`DistrictCoords` 缺 `杨凌:杨陵区` 时坐标会退成 0，
 * 被 MapStops.usable 直接滤掉——那时"地图上没点"要由这条先报，而不是等用户发现。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { util } from '@kit.ArkTS';
import { DataSeeder, DistrictCoords } from '../../../main/ets/data/DataSeeder';
import { Spot } from '../../../main/ets/model/Spot';
import { Area } from '../../../main/ets/model/Area';

async function readRows(path: string): Promise<string[]> {
  const ctx = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
  const bytes: Uint8Array = await ctx.resourceManager.getRawFileContent(path);
  const text: string = new util.TextDecoder().decodeToString(bytes);
  return text.split('\n').filter((l: string): boolean => l.trim().length > 0);
}

/** 杨凌示范区大致范围：纬度 34.1~34.4，经度 107.9~108.3（东西跨约 20km） */
function inYangling(lat: number, lon: number): boolean {
  return lat >= 34.1 && lat <= 34.4 && lon >= 107.9 && lon <= 108.3;
}

export default function yanglingSeedTest(): void {
  describe('杨凌种子', () => {

    it('spots_parse_and_land_in_yangling', TestType.FUNCTION | Size.MEDIUMTEST | Level.LEVEL1, async () => {
      const rows: string[] = await readRows('seed/spots_yangling.jsonl');
      expect(rows.length >= 8).assertTrue();
      let bad: number = 0;
      let offmap: number = 0;
      let noCoord: number = 0;
      rows.forEach((line: string) => {
        const s: Spot | null = DataSeeder.toSpot(line, '杨凌');
        if (s === null) {
          bad += 1;
          return;
        }
        if (s.latitude === 0 && s.longitude === 0) {
          noCoord += 1;
          return;
        }
        if (!inYangling(s.latitude, s.longitude)) {
          offmap += 1;
        }
      });
      expect(bad).assertEqual(0);
      expect(offmap).assertEqual(0);
      expect(noCoord).assertEqual(0);
    });

    it('areas_parse_and_reference_yangling_district', TestType.FUNCTION | Size.MEDIUMTEST | Level.LEVEL1, async () => {
      const rows: string[] = await readRows('seed/areas_yangling.jsonl');
      expect(rows.length >= 4).assertTrue();
      let bad: number = 0;
      let noStation: number = 0;
      rows.forEach((line: string) => {
        const a: Area | null = DataSeeder.toArea(line, '杨凌');
        if (a === null) {
          bad += 1;
          return;
        }
        if (a.anchorStations.length === 0) {
          noStation += 1;
        }
      });
      expect(bad).assertEqual(0);
      // 屏5/屏5b 靠站名锚点讲清"这一片凭什么好住"，空锚点的片区在屏面上只能说空话
      expect(noStation).assertEqual(0);
    });

    it('district_center_resolves_for_yangling', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      // 种子行没写坐标的景点靠 `DistrictCoords` 兜底。这一条是"地图上有没有点"的前提：
      // 缺 `杨凌:杨陵区` 这一项时 lookup 回 0/0，MapStops.usable 会把它们全滤掉，
      // 屏面表现是"地图页一片空白"，而代码没有任何报错。
      const c: number[] = DistrictCoords.lookup('杨凌', '杨陵区');
      expect(c.length).assertEqual(2);
      expect(inYangling(c[0], c[1])).assertTrue();
    });
  });
}
