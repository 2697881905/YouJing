/**
 * 切片 4 离线断言：一句话意图解析 + 自动选点/住宿区。
 * 被 tools/verify_trip_intent.sh 拷进临时目录后用 bundled tsc --strict 编译、
 * bundled node 运行，不依赖 @kit / 设备。
 */

import { Area, AreaGroup, AreaPriceTier } from '../model/Area';
import { Spot, SpotTag } from '../model/Spot';
import { SelectedSpot, SpotPriority } from '../model/PlanParams';
import { TripIntent, TripIntentParser } from '../utils/TripIntentParser';
import { PlanAutoPick } from '../utils/PlanAutoPick';
import { Geo, GeoPoint } from '../utils/Geo';

let cases = 0;

function ok(cond: boolean, msg: string): void {
  cases += 1;
  if (!cond) {
    throw new Error(`FAIL: ${msg}`);
  }
}

function eq(actual: string | number | boolean, expected: string | number | boolean, msg: string): void {
  cases += 1;
  if (actual !== expected) {
    throw new Error(`FAIL: ${msg}（actual=${actual} expected=${expected}）`);
  }
}

function spot(id: string, popularity: number, tags: SpotTag[], lat: number, lng: number): Spot {
  const s: Spot = {
    id: id, name: id, city: '测试', tags: tags, brief: '',
    suggestedDuration: 120, popularity: popularity, nearbySpotIds: [],
    longitude: lng, latitude: lat, district: '', nearestMetro: '',
    booking: { requiresBooking: false },
    provenance: { source: 'test', updatedAt: '2026-10-30' }
  };
  return s;
}

function area(id: string, tier: AreaPriceTier, lat: number, lng: number): Area {
  const a: Area = {
    id: id, name: id, city: '测试', longitude: lng, latitude: lat, description: '',
    anchorStations: [], metroLines: [], airportMinutes: 0, trainStationMinutes: 0,
    commerceTags: [], diningDensity: '中', suitableCrowds: [], priceTier: tier,
    group: AreaGroup.CORE, source: 'test', updatedAt: '2026-10-30'
  };
  return a;
}

function mapArea(name: string, lat: number, lng: number): Area {
  const a: Area = area(name, AreaPriceTier.COMFORT, lat, lng);
  a.source = 'MapKit';
  return a;
}

function sel(id: string): SelectedSpot {
  const s: SelectedSpot = { spotId: id, priority: SpotPriority.MUST };
  return s;
}

const TODAY: string = '2026-10-30'; // 周五

// ---------- 一句话解析 ----------

const full: TripIntent =
  TripIntentParser.parse('下周五去上海玩三天，两个人，喜欢历史和美食', TODAY);
eq(full.city, '上海', '目的地 上海');
eq(full.startDate, '2026-11-06', '下周五 = 2026-11-06');
eq(full.dayCount, 3, '玩三天');
eq(full.people, 2, '两个人');
eq(full.style, 'foodie', '美食优先判 foodie');
eq(full.tags.indexOf(SpotTag.CLASSIC) >= 0, true, '历史 → classic 标签');
eq(full.notes.length, 0, '完整句无歧义说明');

const budget: TripIntent =
  TripIntentParser.parse('明天去北京，一家三口，预算1.5万，想住得舒服点，坐地铁', TODAY);
eq(budget.city, '北京', '目的地 北京');
eq(budget.startDate, '2026-10-31', '明天');
eq(budget.people, 3, '一家三口 = 3');
eq(budget.budgetAmount, 15000, '预算1.5万 = 15000');
eq(budget.budgetIsPerPerson, false, '未写人均按总预算');
eq(budget.stayTier, 'comfort', '舒服 → comfort');
eq(budget.transit, 'public', '地铁 → public');
eq(TripIntentParser.budgetPerPerson(budget.budgetAmount, budget.budgetIsPerPerson, budget.people),
  5000, '15000/3 人均 5000');

const perPerson: TripIntent =
  TripIntentParser.parse('后天去深圳，5天4晚，人均6000，小众打卡', TODAY);
eq(perPerson.city, '深圳', '目的地 深圳');
eq(perPerson.startDate, '2026-11-01', '后天');
eq(perPerson.dayCount, 5, '5天4晚取 5 天');
eq(perPerson.people, 0, '没提人数');
eq(perPerson.budgetAmount, 6000, '人均6000');
eq(perPerson.budgetIsPerPerson, true, '人均标记');
eq(perPerson.tags.indexOf(SpotTag.NICHE) >= 0, true, '小众 → niche');
eq(perPerson.tags.indexOf(SpotTag.MUST_SEE) >= 0, true, '打卡 → must_see');

const unsupported: TripIntent = TripIntentParser.parse('11月15日去西安玩4天', TODAY);
eq(unsupported.city, '', '未内置城市不冒充支持城市');
eq(unsupported.unsupportedCity, '西安', '西安判成未支持');
eq(unsupported.startDate, '2026-11-15', '未内置城市仍解析日期');
eq(unsupported.dayCount, 4, '未内置城市仍解析天数');

const unsupportedFull: TripIntent =
  TripIntentParser.parse('下周五去西安玩三天，两个人，预算一万', TODAY);
eq(unsupportedFull.unsupportedCity, '西安', '西安整句');
eq(unsupportedFull.startDate, '2026-11-06', '西安整句解析日期');
eq(unsupportedFull.dayCount, 3, '西安整句解析天数');
eq(unsupportedFull.people, 2, '西安整句解析人数');
eq(unsupportedFull.budgetAmount, 10000, '西安整句解析预算');

const fromTo: TripIntent = TripIntentParser.parse('从北京去西安玩三天', TODAY);
eq(fromTo.unsupportedCity, '西安', '「从北京去西安」目的地取西安');

const aliasMap: TripIntent = TripIntentParser.parse('去蓉城玩三天，两个人', TODAY);
eq(aliasMap.unsupportedCity, '成都', '蓉城 → 成都');
eq(aliasMap.dayCount, 3, '蓉城句仍解析天数');
eq(aliasMap.people, 2, '蓉城句仍解析人数');
const aliasFrom: TripIntent = TripIntentParser.parse('从北京去山城吃火锅', TODAY);
eq(aliasFrom.unsupportedCity, '重庆', '山城 → 重庆');

const alias: TripIntent = TripIntentParser.parse('下周去魔都玩三天', TODAY);
eq(alias.city, '上海', '魔都 → 上海');

const nights: TripIntent = TripIntentParser.parse('去广州住4晚', TODAY);
eq(nights.dayCount, 5, '住4晚 = 5 天');

const ordinal: TripIntent = TripIntentParser.parse('第3天去故宫，去北京玩五天', TODAY);
eq(ordinal.dayCount, 5, '「第3天」不是天数，取「五天」');

const rollover: TripIntent = TripIntentParser.parse('1月5日去北京', '2026-12-30');
eq(rollover.startDate, '2027-01-05', '过去月日滚到明年');
eq(rollover.notes.length, 1, '跨年推断有说明');

const badDate: TripIntent = TripIntentParser.parse('2月30日去北京', TODAY);
eq(badDate.startDate, '', '非法日期不产出');
ok(badDate.notes.length === 1 && badDate.notes[0].indexOf('不是有效日期') >= 0, '非法日期有说明');

const thisWeek: TripIntent = TripIntentParser.parse('本周六去北京', TODAY);
eq(thisWeek.startDate, '2026-10-31', '本周六 = 2026-10-31');

const empty: TripIntent = TripIntentParser.parse('   ', TODAY);
eq(empty.city, '', '空句无目的地');
eq(empty.dayCount, 0, '空句无天数');
eq(empty.tags.length, 0, '空句无标签');

// 中文数字预算与人数
const chineseBudget: TripIntent = TripIntentParser.parse('去上海玩两天，预算八千', TODAY);
eq(chineseBudget.budgetAmount, 8000, '预算八千 = 8000');
eq(chineseBudget.people, 0, '「两天」不会被当成两人');

const clampBudget: number =
  TripIntentParser.budgetPerPerson(8000, false, 4);
eq(clampBudget, 3000, '总预算 8000/4=2000 夹到下限 3000');
eq(TripIntentParser.budgetPerPerson(100000, false, 1), 12000, '超上限夹到 12000');
eq(TripIntentParser.budgetPerPerson(8100, false, 2), 4000, '4050 取整到 500 档');
eq(TripIntentParser.budgetPerPerson(0, false, 2), 0, '没预算返回 0');

// ---------- 自动选点 ----------

const spots: Spot[] = [
  spot('s1', 90, [SpotTag.CLASSIC], 34.27, 108.07),
  spot('s2', 80, [SpotTag.NICHE], 34.28, 108.08),
  spot('s3', 70, [SpotTag.FAMILY], 34.29, 108.09),
  spot('s4', 60, [SpotTag.CLASSIC], 34.30, 108.10),
  spot('s5', 50, [], 34.31, 108.11),
  spot('s6', 40, [], 34.32, 108.12)
];

eq(PlanAutoPick.dailyCap('relaxed'), 3, '轻松 3');
eq(PlanAutoPick.dailyCap('standard'), 4, '标准 4');
eq(PlanAutoPick.dailyCap('packed'), 6, '紧凑 6');
eq(PlanAutoPick.dailyCap(''), 4, '未选节奏按标准 4');

const oneDay: SelectedSpot[] = PlanAutoPick.pickSpots(spots, 1, 'standard', ['classic']);
eq(oneDay.length, 4, '1 天标准预选 4 个');
eq(oneDay[0].spotId, 's1', '标签命中且热度最高排第一');
eq(oneDay[1].spotId, 's4', '标签命中排第二');
eq(oneDay[2].spotId, 's2', '其余按热度补齐');
eq(oneDay[0].priority, SpotPriority.MUST, '首站必去');
eq(oneDay[1].priority, SpotPriority.WANT, '其余想去');

const twoDays: SelectedSpot[] = PlanAutoPick.pickSpots(spots, 2, 'relaxed', []);
eq(twoDays.length, 6, '2 天轻松 6 个刚好全取');
eq(twoDays[0].priority, SpotPriority.MUST, '第 1 个必去');
eq(twoDays[1].priority, SpotPriority.MUST, '第 2 个必去（每天至少一站）');
eq(twoDays[2].priority, SpotPriority.WANT, '第 3 个想去');

const packed: SelectedSpot[] = PlanAutoPick.pickSpots(spots, 2, 'packed', []);
eq(packed.length, 6, '紧凑 2 天也只有 6 个候选，不重复');
eq(PlanAutoPick.pickSpots([], 3, 'standard', []).length, 0, '无景点返回空');

// ---------- 单日按 10h 窗口收口 ----------
const home: Area = area('home', AreaPriceTier.COMFORT, 34.27, 108.07);
const nearSpots: Spot[] = [
  spot('n1', 100, [SpotTag.CLASSIC], 34.27, 108.07),
  spot('n2', 90, [], 34.28, 108.08),
  spot('n3', 80, [], 34.29, 108.09),
  spot('n4', 70, [], 34.30, 108.10)
];
const nearSingle: SelectedSpot[] = PlanAutoPick.pickSpotsForSingleDay(
  nearSpots, 'standard', [], home);
eq(nearSingle.length, 3, '同城 4 站按 10h 窗口收到 3 站');
eq(nearSingle[0].priority, SpotPriority.MUST, '单日首站仍是必去');
const farSpots: Spot[] = [
  spot('f1', 100, [SpotTag.CLASSIC], 34.34, 108.35),
  spot('f2', 90, [], 34.28, 108.08),
  spot('f3', 80, [], 34.29, 108.09),
  spot('f4', 70, [], 34.30, 108.10)
];
const farSingle: SelectedSpot[] = PlanAutoPick.pickSpotsForSingleDay(
  farSpots, 'standard', [], home);
eq(farSingle.length, 2, '远郊首站把单日名额压到 2');
eq(farSingle[0].spotId, 'f1', '高优先级远郊首站保留');
// 重庆 1 天真机形态：首候选是 120km 外的大足石刻，单站就吃掉整天预算
// ——从尾部砍会把同城的洪崖洞/磁器口全砍光，正确做法是跳过这一站
const cqHome: Area = area('渝中区', AreaPriceTier.COMFORT, 29.56, 106.55);
const cqSpots: Spot[] = [
  spot('cq1', 100, [SpotTag.CLASSIC], 29.70, 105.72),
  spot('cq2', 95, [], 29.562, 106.578),
  spot('cq3', 90, [], 29.58, 106.45),
  spot('cq4', 80, [], 30.30, 105.90)
];
const cqSingle: SelectedSpot[] = PlanAutoPick.pickSpotsForSingleDay(
  cqSpots, 'standard', [], cqHome);
eq(cqSingle.length, 2, '重庆 1 天：跳过远郊首站后留下 2 个同城站');
eq(cqSingle[0].spotId, 'cq2', '远郊首站被跳过，同城最高优先级排第一');
ok(cqSingle.find((s: SelectedSpot): boolean => s.spotId === 'cq1') === undefined,
  '装不下的大足石刻不占单日名额');
eq(PlanAutoPick.pickSpotsForSingleDay([], 'standard', [], home).length, 0, '单日无景点返回空');
ok(PlanAutoPick.describe(nearSingle, home, 1, 'standard')
  .indexOf('按单日 10 小时窗口预选 3 个景点') >= 0, '单日预览说明窗口与站数');

// ---------- 住宿区：地图区县按酒店供给，种子片区按平均距离（列表与预选同源） ----------

// 丽江真机形态：候选顺序即酒店供给降序（古城区 467 店、玉龙县 139 店），
// 但玉龙雪山那颗卫星点会把平均距离拉向县城——列表与预选都必须按供给说话
const ljAreas: Area[] = [
  mapArea('古城区', 26.87, 100.23),
  mapArea('玉龙纳西族自治县', 27.12, 100.24)
];
const ljTargets: GeoPoint[] = [
  { latitude: 26.98, longitude: 100.23 },
  { latitude: 26.76, longitude: 100.23 },
  { latitude: 27.122, longitude: 100.245 },
  { latitude: 27.135, longitude: 100.26 }
];
ok(Geo.meanDistanceKm({ latitude: 27.12, longitude: 100.24 }, ljTargets) <
  Geo.meanDistanceKm({ latitude: 26.87, longitude: 100.23 }, ljTargets),
  '丽江这组点位的平均距离确实偏向玉龙县（按距离重排必错）');
const tie: Area | null = PlanAutoPick.nearestArea(ljAreas, ljTargets);
ok(tie !== null && tie.name === '古城区', '地图区县按供给顺序取古城区，不被距离重排');
ok(PlanAutoPick.rankAreas(ljAreas, ljTargets)[1].name === '玉龙纳西族自治县',
  '列表第二名仍是玉龙县（供给顺序原样保留）');

// ---------- 自动住宿区 ----------

const areas: Area[] = [
  area('a1', AreaPriceTier.ECONOMY, 34.00, 108.00),
  area('a2', AreaPriceTier.COMFORT, 34.10, 108.10),
  area('a3', AreaPriceTier.COMFORT, 34.20, 108.20)
];
const nearA3: GeoPoint[] = [{ latitude: 34.19, longitude: 108.19 }];
const nearest: Area | null = PlanAutoPick.nearestArea(areas, nearA3);
ok(nearest !== null && nearest.id === 'a3', '最近区取 a3');
ok(PlanAutoPick.nearestArea(areas, []) === null, '无景点坐标返回 null');
ok(PlanAutoPick.nearestArea([], nearA3) === null, '无片区返回 null');

const comfortPick: Area | null = PlanAutoPick.pickArea(areas, spots, [sel('s6')], 'comfort');
ok(comfortPick !== null && comfortPick.id === 'a3', '舒适档内取离 s6 最近的 a3');
const economyPick: Area | null = PlanAutoPick.pickArea(areas, spots, [sel('s6')], 'economy');
ok(economyPick !== null && economyPick.id === 'a1', '经济档只剩 a1');
const fallbackTier: Area | null = PlanAutoPick.pickArea(areas, spots, [sel('s6')], 'luxury');
ok(fallbackTier !== null && fallbackTier.id === 'a3', '档位无候选退回全量');
const noSpotsPick: Area | null = PlanAutoPick.pickArea(areas, spots, [], 'comfort');
ok(noSpotsPick !== null && noSpotsPick.id === 'a2', '没选景点时退回候选首位');
ok(PlanAutoPick.pickArea([], spots, [sel('s1')], 'comfort') === null, '无片区返回 null');
// 种子片区没有住宿库存，只能按到所选景点的平均直线距离升序
const seededRanked: Area[] = PlanAutoPick.rankAreas(areas, nearA3);
ok(seededRanked[0].id === 'a3', '种子片区按平均距离升序');
ok(PlanAutoPick.rankAreas(areas, []).length === areas.length, '没有景点坐标时不重排');

ok(PlanAutoPick.describe(oneDay, comfortPick, 1, 'standard').indexOf('预选 4 个景点') >= 0,
  '预览理由含预选数量');
ok(PlanAutoPick.describe([], null, 1, 'standard').indexOf('没有可预选') >= 0,
  '空结果也有说明');

console.log(`PASS ${cases}/${cases}`);
