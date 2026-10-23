/**
 * 屏4/5/8 Mock 数据（开发文档 §6 阶段 2：UI 占位 + Mock 渲染）。
 * USE_MOCK_DATA 开启时 data/ 层路由到此；字段全部走 model/ 契约类型。
 * 城市选京都与底稿帧同源，正式内置库为北上广深（阶段 5 替换）。
 */

import { Spot, SpotTag } from '../model/Spot';
import { Area, AreaGroup, AreaPriceTier } from '../model/Area';

function spot(id: string, name: string, tags: SpotTag[], district: string,
  durationMin: number, popularity: number, needsBooking: boolean): Spot {
  const s: Spot = {
    id: id,
    name: name,
    city: '京都',
    tags: tags,
    brief: name + ' 一句话简介（mock）',
    suggestedDuration: durationMin,
    popularity: popularity,
    nearbySpotIds: [],
    longitude: 135.7,
    latitude: 35.0,
    district: district,
    nearestMetro: '京都市营',
    booking: { requiresBooking: needsBooking },
    provenance: { source: 'mock', updatedAt: '2026-10-22' }
  };
  return s;
}

export class MockSpots {
  static readonly CULTURE: Spot[] = [
    spot('s-kiyomizu', '清水寺', [SpotTag.MUST_SEE, SpotTag.CLASSIC], '东山区', 90, 98, false),
    spot('s-ninenzaka', '二年坂', [SpotTag.CLASSIC], '东山区', 60, 88, true),
    spot('s-fushimi', '伏见稻荷大社', [SpotTag.MUST_SEE], '伏见区', 120, 96, false),
    spot('s-kinkaku', '金阁寺', [SpotTag.CLASSIC], '北区', 60, 92, false)
  ];
  static readonly FOOD: Spot[] = [
    spot('s-nishiki', '锦市场', [SpotTag.CLASSIC], '中京区', 90, 90, false),
    spot('s-kamogawa', '鸭川纳凉床', [SpotTag.NICHE], '下京区', 60, 82, true),
    spot('s-uji', '宇治抹茶街', [SpotTag.NICHE], '宇治市', 120, 78, false)
  ];
  static readonly NATURE: Spot[] = [
    spot('s-arashiyama', '岚山竹林小径', [SpotTag.MUST_SEE], '右京区', 90, 94, false),
    spot('s-philosopher', '哲学之道', [SpotTag.NICHE], '左京区', 60, 80, false)
  ];
}

function area(id: string, name: string, group: AreaGroup, tier: AreaPriceTier,
  airportMin: number, stationMin: number): Area {
  const a: Area = {
    id: id,
    name: name,
    city: '京都',
    longitude: 135.77,
    latitude: 35.0,
    description: name + '（mock）',
    anchorStations: ['京都站'],
    metroLines: ['市营巴士'],
    airportMinutes: airportMin,
    trainStationMinutes: stationMin,
    commerceTags: [],
    diningDensity: '高',
    suitableCrowds: [],
    priceTier: tier,
    group: group,
    source: 'mock',
    updatedAt: '2026-10-22'
  };
  return a;
}

/** 屏5 区域卡的展示包装：AI 理由与角标为生成结果，不属内置库契约 */
export interface AreaPick {
  area: Area;
  badgeLabel: string;
  aiRank: number;
  reason: string;
}

export class MockAreas {
  static readonly PICKS: AreaPick[] = [
    {
      area: area('a-gion', '祇园 · 东山', AreaGroup.CORE, AreaPriceTier.COMFORT, 75, 12),
      badgeLabel: 'AI 精选 1',
      aiRank: 1,
      reason: '早上 7 点前能空着走进清水寺，避开旅行团'
    },
    {
      area: area('a-kawaramachi', '河原町 · 三条', AreaGroup.COMMERCIAL, AreaPriceTier.COMFORT, 70, 10),
      badgeLabel: '商圈便利',
      aiRank: 2,
      reason: '夜间餐饮选择极多，步行即达锦市场与鸭川沿岸'
    },
    {
      area: area('a-station', '京都站前', AreaGroup.METRO, AreaPriceTier.ECONOMY, 55, 1),
      badgeLabel: '交通枢纽',
      aiRank: 3,
      reason: '行李寄存与往返机场最省事，适合早班车出发日'
    }
  ];
}
