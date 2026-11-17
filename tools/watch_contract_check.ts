/**
 * 手表线协议 + 路由决策表 · 离线断言（参照 arkts-pure-logic-offline-verify 手法）。
 *
 * 覆盖规格 §10：
 * - CompanionPrompt → WatchCard 投影正确（含推荐键、截断、至多 3 项）
 * - WatchDecision / Withdraw / Sync 解析；畸形与未知版本静默忽略
 * - 打卡 cardId 可逆（tripId / stopKey 含 '-' 也不串段）
 * - 路由决策表：在场执行 / 离页入队 / 高风险不静默 / 幂等 / 卡已撤丢弃
 */

import {
  WATCH_DISMISS_KEY, WATCH_KIND_CHECKIN, WATCH_KIND_COMPANION, WATCH_MAX_DETAIL, WATCH_MAX_LABEL,
  WATCH_MAX_OPTIONS, WATCH_MAX_TITLE, WATCH_OPTION_CHECKIN, WATCH_OPTION_SKIP, WATCH_PROTOCOL_VERSION,
  WATCH_TYPE_CARD, WATCH_TYPE_DECISION, WATCH_TYPE_SYNC, WATCH_TYPE_WITHDRAW, WatchCard, WatchCardId,
  WatchCheckinRef, WatchCodec, WatchDecision, WatchEnvelope, WatchOption, WatchProjection, WatchSourceOption,
  WatchSourcePrompt
} from 'watchcontract';
import { WatchRoute, WatchRoutePlan, WATCH_CARD_TTL_MS } from '../entry/src/main/ets/watch/WatchRoute';

declare const process: { exit(code: number): void };

let passed: number = 0;
const failures: string[] = [];

function ok(condition: boolean, name: string): void {
  if (condition) {
    passed++;
  } else {
    failures.push(name);
  }
}

function eq(actual: string, expected: string, name: string): void {
  if (actual === expected) {
    passed++;
  } else {
    failures.push(`${name}（期望「${expected}」实际「${actual}」）`);
  }
}

function eqNum(actual: number, expected: number, name: string): void {
  if (actual === expected) {
    passed++;
  } else {
    failures.push(`${name}（期望 ${expected} 实际 ${actual}）`);
  }
}

function sourcePrompt(): WatchSourcePrompt {
  const options: WatchSourceOption[] = [
    { key: 'move_tomorrow', label: '留着博览园，下一站挪明天', subline: '今天从容逛，明天我提醒你' },
    { key: 'quick_visit', label: '快逛一下，赶得上下一站', subline: '压缩游览，刚好不挤占' },
    { key: 'keep_plan', label: '按原计划走', subline: '博览园记下来下次去' }
  ];
  const prompt: WatchSourcePrompt = {
    id: 'unplanned-博览园-act123',
    kind: 'unplanned_arrival',
    title: '你到了博览园——不在今天计划里',
    detail: '它大概要 90 分钟，会挤占下一站。怎么安排？',
    options: options,
    recommendedIndex: 0,
    stake: 'low'
  };
  return prompt;
}

function findOption(options: WatchOption[], key: string): WatchOption | null {
  for (const option of options) {
    if (option.key === key) {
      return option;
    }
  }
  return null;
}

// ---- 1. 投影 ----

const now: number = 1794576962289;
const card: WatchCard = WatchProjection.fromPrompt(sourcePrompt(), now);
eq(card.cardId, 'unplanned-博览园-act123', '投影 cardId 复用 prompt.id');
eq(card.kind, WATCH_KIND_COMPANION, '投影 kind=companion');
eqNum(card.v, WATCH_PROTOCOL_VERSION, '投影协议版本');
eq(card.type, WATCH_TYPE_CARD, '投影 type=card');
eqNum(card.options.length, 3, '投影保留 3 个选项');
eq(card.recommendedKey, 'move_tomorrow', '投影 recommendedKey 取推荐项 key');
eqNum(card.ts, now, '投影透传时间戳');
ok(card.title.length <= WATCH_MAX_TITLE, '标题截断到手表可读长度');
ok(card.detail.length <= WATCH_MAX_DETAIL, '后果文案截断到手表可读长度');
const moveOption: WatchOption | null = findOption(card.options, 'move_tomorrow');
ok(moveOption !== null, '投影保留选项 key');
ok(moveOption !== null && moveOption.label.length <= WATCH_MAX_LABEL, '选项主文案截断');

// 推荐下标越界 → 落第一项，不产生空推荐键
const badIndex: WatchSourcePrompt = sourcePrompt();
badIndex.recommendedIndex = 9;
const fallbackCard: WatchCard = WatchProjection.fromPrompt(badIndex, now);
eq(fallbackCard.recommendedKey, fallbackCard.options[0].key, '推荐下标越界回落首项');

// 超过 3 个选项 → 截到 3
const many: WatchSourcePrompt = sourcePrompt();
many.options.push({ key: 'extra', label: '多余项', subline: '' });
eqNum(WatchProjection.fromPrompt(many, now).options.length, WATCH_MAX_OPTIONS, '选项数截到 3');

// 超长文案确实被裁剪且带省略号
const long: WatchSourcePrompt = sourcePrompt();
long.title = '很长很长'.repeat(30);
long.detail = '后果'.repeat(80);
const longCard: WatchCard = WatchProjection.fromPrompt(long, now);
ok(longCard.title.length === WATCH_MAX_TITLE && longCard.title.endsWith('…'), '超长标题补省略号');
ok(longCard.detail.length === WATCH_MAX_DETAIL && longCard.detail.endsWith('…'), '超长后果补省略号');

// ---- 2. 打卡卡与 cardId ----

const tripId: string = 'trip-2026-11-13-0a1b';
const stopKey: string = 'yl-001';
const checkinCard: WatchCard =
  WatchProjection.checkinCard(tripId, stopKey, '西北农林科技大学博览园', now);
eq(checkinCard.kind, WATCH_KIND_CHECKIN, '打卡卡 kind=checkin');
eqNum(checkinCard.options.length, 2, '打卡卡固定 2 个选项');
eq(checkinCard.options[0].key, WATCH_OPTION_CHECKIN, '打卡卡首项=打卡');
eq(checkinCard.options[1].key, WATCH_OPTION_SKIP, '打卡卡次项=跳过');
eq(checkinCard.recommendedKey, WATCH_OPTION_CHECKIN, '打卡卡推荐打卡');
const ref: WatchCheckinRef | null = WatchCardId.parseCheckin(checkinCard.cardId);
ok(ref !== null, '打卡 cardId 可解析');
eq(ref === null ? '' : ref.tripId, tripId, '打卡 cardId 解析回 tripId（含 - 不串段）');
eq(ref === null ? '' : ref.stopKey, stopKey, '打卡 cardId 解析回 stopKey');
ok(WatchCardId.isCheckin(checkinCard.cardId), '打卡 cardId 前缀识别');
ok(!WatchCardId.isCheckin('unplanned-x'), '请示卡 cardId 不误判为打卡');

const trickyTrip: string = 'trip-100%-a-b';
const trickyStop: string = 'meal-1-LUNCH';
const trickyCardId: string = WatchCardId.checkin(trickyTrip, trickyStop);
const trickyRef: WatchCheckinRef | null = WatchCardId.parseCheckin(trickyCardId);
eq(trickyRef === null ? '' : trickyRef.tripId, trickyTrip, 'cardId 转义：% 与 - 可逆');
eq(trickyRef === null ? '' : trickyRef.stopKey, trickyStop, 'cardId 转义：stopKey 可逆');
ok(WatchCardId.parseCheckin('checkin-onlyone') === null, '畸形 cardId 返回 null');
ok(WatchCardId.parseCheckin('unplanned-x') === null, '非打卡卡不按打卡解析');

// ---- 3. 编解码与容错 ----

const encodedCard: string = WatchCodec.encodeCard(card);
const decodedCard: WatchCard | null = WatchCodec.decodeCard(encodedCard);
ok(decodedCard !== null, '卡片 JSON 往返可解');
eq(decodedCard === null ? '' : decodedCard.cardId, card.cardId, '往返 cardId 一致');
eq(decodedCard === null ? '' : decodedCard.recommendedKey, card.recommendedKey, '往返推荐键一致');

const decision: WatchDecision = {
  v: WATCH_PROTOCOL_VERSION, type: WATCH_TYPE_DECISION, cardId: card.cardId,
  optionKey: 'move_tomorrow', ts: now + 1000
};
const decodedDecision: WatchDecision | null = WatchCodec.decodeDecision(WatchCodec.encodeDecision(decision));
ok(decodedDecision !== null, '决策 JSON 往返可解');
eq(decodedDecision === null ? '' : decodedDecision.optionKey, 'move_tomorrow', '决策往返 optionKey 一致');

const withdrawEnv: WatchEnvelope | null = WatchCodec.decode(WatchCodec.encodeWithdraw(card.cardId, now));
ok(withdrawEnv !== null && withdrawEnv.type === WATCH_TYPE_WITHDRAW, '撤卡消息可解');
eq(withdrawEnv === null || withdrawEnv.withdraw === null ? '' : withdrawEnv.withdraw.cardId,
  card.cardId, '撤卡 cardId 一致');

const syncEnv: WatchEnvelope | null = WatchCodec.decode(WatchCodec.encodeSync(now));
ok(syncEnv !== null && syncEnv.type === WATCH_TYPE_SYNC, 'sync 消息可解');

const unknownVersion: string = `{"v":2,"type":"decision","cardId":"x","optionKey":"y","ts":1}`;
ok(WatchCodec.decode(unknownVersion) === null, '未知版本静默忽略');
ok(WatchCodec.decode('') === null, '空串忽略');
ok(WatchCodec.decode('{') === null, '畸形 JSON 忽略');
ok(WatchCodec.decode('[]') === null, '数组载荷忽略');
ok(WatchCodec.decode('{"v":1,"type":"decision","cardId":"","optionKey":"y","ts":1}') === null,
  '缺 cardId 的决策忽略');
ok(WatchCodec.decode('{"v":1,"type":"decision","cardId":"x","optionKey":"","ts":1}') === null,
  '缺 optionKey 的决策忽略');
ok(WatchCodec.decode('{"v":1,"type":"decision","cardId":"x","optionKey":"y","ts":0}') === null,
  '时间戳非法的决策忽略');
ok(WatchCodec.decode('{"v":1,"type":"nope"}') === null, '未知 type 忽略');
ok(WatchCodec.decode('{"v":1,"type":"card","cardId":"x","kind":"companion","title":"t",' +
  '"detail":"","options":[],"recommendedKey":"","ts":1}') === null, '空选项卡片忽略');
ok(WatchCodec.decode('{"v":1,"type":"card","cardId":"x","kind":"other","title":"t",' +
  '"detail":"","options":[{"key":"a","label":"A","subline":""}],"recommendedKey":"a","ts":1}') === null,
  '未知 kind 卡片忽略');

// 推荐键对不上任何选项 → 回落首项，而不是丢卡
const brokenRecommended: string = '{"v":1,"type":"card","cardId":"x","kind":"companion","title":"t",' +
  '"detail":"","options":[{"key":"a","label":"A","subline":""}],"recommendedKey":"zzz","ts":1}';
const fixedCard: WatchCard | null = WatchCodec.decodeCard(brokenRecommended);
eq(fixedCard === null ? '' : fixedCard.recommendedKey, 'a', '推荐键对不上回落首项');

// ---- 4. 路由决策表 ----

function plan(optionKey: string, cardLive: boolean, pagePresent: boolean,
  stake: string, duplicate: boolean): WatchRoutePlan {
  const d: WatchDecision = {
    v: WATCH_PROTOCOL_VERSION, type: WATCH_TYPE_DECISION, cardId: 'c1', optionKey: optionKey, ts: now
  };
  return WatchRoute.planCompanion(d, {
    cardLive: cardLive, pagePresent: pagePresent,
    stake: stake === 'high' ? 'high' : 'low', duplicate: duplicate
  });
}

eq(plan('move_tomorrow', true, true, 'low', false).action, 'execute', '在场 → 当场执行');
eq(plan('move_tomorrow', true, false, 'low', false).action, 'queue', '离页低风险 → 入队');
eq(plan('move_tomorrow', true, false, 'high', false).action, 'queue', '离页高风险 → 入队不执行');
eq(plan('move_tomorrow', true, false, 'high', false).reason, 'high-stake-offpage',
  '高风险离页带明确原因');
eq(plan('move_tomorrow', true, true, 'low', true).action, 'drop', '重复决策丢弃');
eq(plan('move_tomorrow', false, true, 'low', false).action, 'drop', '卡已撤丢弃');
eq(plan(WATCH_DISMISS_KEY, true, true, 'low', false).action, 'dismiss', '划掉 → 收卡不执行');
eq(plan(WATCH_DISMISS_KEY, false, true, 'low', false).action, 'drop', '卡已撤时划掉也丢弃');

eq(WatchRoute.checkinIntent(WATCH_OPTION_CHECKIN), 'checkin', '打卡键识别');
eq(WatchRoute.checkinIntent(WATCH_OPTION_SKIP), 'skip', '跳过键识别');
eq(WatchRoute.checkinIntent(WATCH_DISMISS_KEY), 'dismiss', '打卡卡划掉识别');
eq(WatchRoute.checkinIntent('move_tomorrow'), 'invalid', '打卡卡不接受请示键');

// ---- 5. 入站前置校验（US-5 / US-6 / US-10）----

ok(!WatchRoute.isStale(now - WATCH_CARD_TTL_MS + 1000, now), 'TTL 内不算过时');
ok(WatchRoute.isStale(now - WATCH_CARD_TTL_MS - 1000, now), '超过 TTL 算过时');
ok(WatchRoute.isStale(0, now), '非法时间戳算过时');
ok(WatchRoute.isForeignAccount('uid-a', 'uid-b'), '跨账号判定');
ok(!WatchRoute.isForeignAccount('', 'uid-b'), '历史记录空 uid 按当前账号');
ok(!WatchRoute.isForeignAccount('uid-a', 'uid-a'), '同账号放行');

eq(WatchRoute.precheck(false, 'uid-a', now, now, 'uid-a').reason, 'card-not-live', '卡已撤优先丢弃');
eq(WatchRoute.precheck(true, 'uid-a', now - WATCH_CARD_TTL_MS - 1, now, 'uid-a').reason, 'stale',
  '过时卡丢弃');
eq(WatchRoute.precheck(true, 'uid-a', now, now, 'uid-b').reason, 'foreign-account', '跨账号丢弃');
ok(WatchRoute.precheck(true, 'uid-a', now, now, 'uid-a').pass, '正常卡放行');
ok(WatchRoute.precheck(true, '', now, now, 'uid-b').pass, '历史空 uid 正常卡放行');

// ---- 6. 消息体积（G0-e：SDK 单条 [1, 4096) 字节）----

const packed: WatchSourcePrompt = sourcePrompt();
packed.title = '标题'.repeat(40);
packed.detail = '后果说明'.repeat(60);
packed.options = [
  { key: 'move_tomorrow', label: '选项一'.repeat(10), subline: '后果一'.repeat(20) },
  { key: 'quick_visit', label: '选项二'.repeat(10), subline: '后果二'.repeat(20) },
  { key: 'keep_plan', label: '选项三'.repeat(10), subline: '后果三'.repeat(20) }
];
const packedJson: string = WatchCodec.encodeCard(WatchProjection.fromPrompt(packed, now));
const packedBytes: number = new TextEncoder().encode(packedJson).length;
ok(packedBytes > 0 && packedBytes < 4096, `最大卡字节数落在 SDK 上限内（bytes=${packedBytes}）`);
const checkinJson: string = WatchCodec.encodeCard(checkinCard);
const checkinBytes: number = new TextEncoder().encode(checkinJson).length;
ok(checkinBytes > 0 && checkinBytes < 4096, `打卡卡字节数落在 SDK 上限内（bytes=${checkinBytes}）`);

// ---- 汇总 ----

if (failures.length > 0) {
  console.error(`WATCH_CONTRACT_FAIL cases=${passed} failures=${failures.length}`);
  for (const failure of failures) {
    console.error(`  ✗ ${failure}`);
  }
  process.exit(1);
}
console.log(`WATCH_CONTRACT_OK cases=${passed}`);
