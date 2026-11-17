/**
 * 手机侧手表桥接（常驻，不绑页面生命周期）——规格 §7。
 *
 * 出站：CompanionStore.show/dismiss 钩子 + 到站打卡时机 → WatchCard → Wear Engine。
 * 入站：WatchDecision → 按 cardId 对账 → 打卡落库 / 请示执行 / 离页入队 / 幂等丢弃。
 *
 * 关键纪律：
 * - 手表打卡 evidence=null → CheckinDao 记 source='manual'，绝不伪造到站坐标。
 * - 高风险（stake=high）离页不静默执行，回页只重新请示。
 * - 同 cardId 只执行一次；对不上的 cardId 一律丢弃。
 */

import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  WATCH_KIND_CHECKIN, WATCH_KIND_COMPANION, WATCH_PROTOCOL_VERSION, WATCH_TYPE_CARD,
  WATCH_TYPE_DECISION, WATCH_TYPE_SYNC, WatchCard, WatchCardId, WatchCheckinRef, WatchCodec, WatchDecision,
  WatchEnvelope, WatchProjection, WatchSourceOption, WatchSourcePrompt
} from 'watchcontract';
import { CompanionOption, CompanionPrompt, companionDecisionKey } from '../companion/CompanionTypes';
import { CompanionStore } from '../companion/CompanionStore';
import { AccountStore } from '../data/AccountStore';
import { CheckinDao } from '../data/CheckinDao';
import { TripDao } from '../data/TripDao';
import { WidgetSync } from '../widget/TodayCard';
import { Logger } from '../common/logger/Logger';
import { WatchRoute, WatchRoutePlan, WatchPrecheck } from './WatchRoute';
import { WearEngineTransport } from './WearEngineTransport';

const TAG: string = 'Watch.Bridge';
const PROBE_TAG: string = 'Probe.WatchEcho';
const PREFS_NAME: string = 'youjing_watch_bridge';
const KEY_CURRENT: string = 'currentCard';
const KEY_PENDING: string = 'pendingDecisions';
const KEY_PROCESSED: string = 'processedCards';
/** 已处理 cardId 记忆长度：够覆盖一次断连重发即可 */
const PROCESSED_CAP: number = 20;
/** 离页待执行队列上限：超出丢最旧（手表卡本身也有 ts 过期） */
const PENDING_CAP: number = 10;

/** 打卡落库后通知行程页刷新（页面用 @StorageLink 订阅） */
export const WATCH_CHECKIN_TICK_KEY: string = 'watchCheckinTick';

interface WatchCardRecord {
  cardId: string;
  kind: string;
  /** 发卡时的账号分区：切换账号后旧卡决策必须丢弃（US-10） */
  uid: string;
  tripId: string;
  stopKey: string;
  stopTitle: string;
  /** 请示卡原始 CompanionPrompt（执行语义只在手机侧，手表拿不到） */
  promptJson: string;
  stake: string;
  ts: number;
}

interface WatchPendingRecord {
  cardId: string;
  optionKey: string;
  uid: string;
  promptJson: string;
  stake: string;
  ts: number;
}

export class WatchBridge {
  private static context: common.Context | null = null;
  private static transport: WearEngineTransport = new WearEngineTransport();
  private static current: WatchCardRecord | null = null;
  private static pending: WatchPendingRecord[] = [];
  private static processed: string[] = [];
  private static ready: boolean = false;
  private static echoMode: boolean = false;

  static isReady(): boolean {
    return WatchBridge.ready;
  }

  /** 离页待执行队列长度（探针/日志用） */
  static pendingCount(): number {
    return WatchBridge.pending.length;
  }

  /**
   * 初始化（幂等）。echo=true 时额外跑 G0 回声探针：发 hello，等手表回 pong。
   * 必须在 AccountStore.init 之后调用——打卡路由要靠账号分区。
   */
  static async init(context: common.Context, echo: boolean): Promise<void> {
    WatchBridge.context = context;
    if (WatchBridge.ready) {
      if (echo) {
        Logger.warn(PROBE_TAG, 'wearecho 探针已随 Wear Engine 停用（改跑 --ps watchnetprobe 1）');
      }
      return;
    }
    WatchBridge.ready = true;
    WatchBridge.echoMode = echo;
    WatchBridge.load(context);
    CompanionStore.setShowHook((prompt: CompanionPrompt): void => {
      WatchBridge.publishPrompt(prompt);
    });
    CompanionStore.setDismissHook((cardId: string): void => {
      WatchBridge.onPromptDismissed(cardId);
    });
    Logger.info(TAG, `桥接就绪 current=${WatchBridge.current === null ? '无' : WatchBridge.current.cardId} ` +
      `pending=${WatchBridge.pending.length} echo=${echo}`);
    // 2026-11-16 全网络客户端规格：Wear Engine P2P 路径已废弃（AGC 驳回 + 手机未活跃不可达），
    // 不再初始化任何 P2P 通道；卡片/决策改走 BFF（切片1/2 接 HttpWatchTransport）。
    Logger.info(TAG, 'Wear Engine 已停用；等待 HttpWatchTransport（切片1/2）');
    if (echo) {
      Logger.warn(PROBE_TAG, 'wearecho 探针已随 Wear Engine 停用（改跑 --ps watchnetprobe 1）');
    }
  }

  /** 手机浮出请示卡 → 投影成 WatchCard 并出站 */
  static publishPrompt(prompt: CompanionPrompt): void {
    const source: WatchSourcePrompt = {
      id: prompt.id,
      kind: prompt.kind,
      title: prompt.title,
      detail: prompt.detail,
      options: prompt.options.map((option: CompanionOption): WatchSourceOption => {
        const flat: WatchSourceOption = {
          key: option.key, label: option.label, subline: option.subline
        };
        return flat;
      }),
      recommendedIndex: prompt.recommendedIndex,
      stake: prompt.stake
    };
    const card: WatchCard = WatchProjection.fromPrompt(source, Date.now());
    const record: WatchCardRecord = {
      cardId: card.cardId,
      kind: card.kind,
      uid: AccountStore.uid(),
      tripId: '',
      stopKey: '',
      stopTitle: '',
      promptJson: JSON.stringify(prompt),
      stake: prompt.stake,
      ts: card.ts
    };
    WatchBridge.current = record;
    WatchBridge.saveCurrent();
    WatchBridge.sendCard(card);
    Logger.info(TAG, `出站请示卡 cardId=${card.cardId} options=${card.options.length} ` +
      `recommended=${card.recommendedKey}`);
  }

  /** 手机收起卡（点选/划掉）→ 通知手表清屏 */
  static onPromptDismissed(cardId: string): void {
    if (cardId.length === 0) {
      return;
    }
    const record: WatchCardRecord | null = WatchBridge.current;
    if (record === null || record.cardId !== cardId) {
      return;
    }
    WatchBridge.current = null;
    WatchBridge.saveCurrent();
    WatchBridge.sendWithdraw(cardId);
  }

  /**
   * 到站打卡卡（ArrivalNotice 时机）。
   * 与手机请示卡同生同灭：桥接层只保留「最新一张」在手表屏幕上（一屏一卡）。
   */
  static publishCheckin(tripId: string, stopKey: string, stopTitle: string): void {
    if (tripId.length === 0 || stopKey.length === 0) {
      return;
    }
    if (WatchBridge.current !== null && WatchBridge.current.kind === WATCH_KIND_COMPANION) {
      Logger.info(TAG, `到站卡覆盖未决请示卡 ${WatchBridge.current.cardId}（一屏一卡）`);
    }
    const card: WatchCard = WatchProjection.checkinCard(tripId, stopKey, stopTitle, Date.now());
    const record: WatchCardRecord = {
      cardId: card.cardId,
      kind: card.kind,
      uid: AccountStore.uid(),
      tripId: tripId,
      stopKey: stopKey,
      stopTitle: stopTitle,
      promptJson: '',
      stake: 'low',
      ts: card.ts
    };
    WatchBridge.current = record;
    WatchBridge.saveCurrent();
    WatchBridge.sendCard(card);
    Logger.info(TAG, `出站打卡卡 cardId=${card.cardId} stop=${stopTitle}`);
  }

  /**
   * 手机侧完成打卡 → 撤掉对应的手表打卡卡。
   * 不撤的话手表会留一个「打卡」按钮，点下去只会被幂等丢弃（看起来像失灵）。
   */
  static withdrawCheckin(tripId: string, stopKey: string): void {
    const record: WatchCardRecord | null = WatchBridge.current;
    if (record === null || record.kind !== WATCH_KIND_CHECKIN) {
      return;
    }
    const ref: WatchCheckinRef | null = WatchCardId.parseCheckin(record.cardId);
    if (ref === null || ref.tripId !== tripId || ref.stopKey !== stopKey) {
      return;
    }
    WatchBridge.clearCurrentAndWithdraw(record.cardId);
  }

  /**
   * 行程页回页消费离页决策。返回真正执行（或重新请示）的条数。
   * 必须在 reload 之后调用：执行器改行程要读页面已加载的 trip/day。
   */
  static async consumePending(context: common.Context): Promise<number> {
    if (WatchBridge.pending.length === 0) {
      return 0;
    }
    const queue: WatchPendingRecord[] = WatchBridge.pending;
    WatchBridge.pending = [];
    WatchBridge.savePending();
    const executedIds: string[] = [];
    const reshowIds: string[] = [];
    for (const item of queue) {
      if (WatchRoute.isStale(item.ts, Date.now())) {
        Logger.warn(TAG, `队列项已过期，丢弃 cardId=${item.cardId}`);
        continue;
      }
      if (WatchRoute.isForeignAccount(item.uid, AccountStore.uid())) {
        Logger.warn(TAG, `队列项属于其他账号分区，丢弃 cardId=${item.cardId}`);
        continue;
      }
      const prompt: CompanionPrompt | null = WatchBridge.parsePrompt(item.promptJson);
      if (prompt === null) {
        Logger.warn(TAG, `队列项缺少原请示卡，丢弃 cardId=${item.cardId}`);
        continue;
      }
      if (item.stake === 'high') {
        // 高风险不在后台静默执行：回页只把卡重新亮出来，等用户再拍板。
        // 若手机横幅已被别的卡顶替，则不再把旧卡塞回去（避免盖掉更新的请示）。
        const livePrompt: CompanionPrompt | null = CompanionStore.current();
        if (livePrompt !== null && livePrompt.id !== item.cardId) {
          Logger.warn(TAG, `高风险卡已被新卡顶替，丢弃旧决策 cardId=${item.cardId}`);
          continue;
        }
        CompanionStore.show(prompt);
        reshowIds.push(item.cardId);
        Logger.info(TAG, `高风险决策回页重新请示 cardId=${item.cardId} option=${item.optionKey}`);
        continue;
      }
      let idx: number = -1;
      for (let i = 0; i < prompt.options.length; i++) {
        if (prompt.options[i].key === item.optionKey) {
          idx = i;
          break;
        }
      }
      if (idx < 0) {
        Logger.warn(TAG, `队列项选项对不上 cardId=${item.cardId} option=${item.optionKey}`);
        continue;
      }
      WatchBridge.markProcessed(item.cardId);
      CompanionStore.prefs.recordChoice(companionDecisionKey(prompt), item.optionKey,
        prompt.options[prompt.recommendedIndex].key);
      CompanionStore.execute(prompt.options[idx].action);
      executedIds.push(item.cardId);
      Logger.info(TAG, `离页决策已执行 cardId=${item.cardId} option=${item.optionKey}`);
    }
    const live: CompanionPrompt | null = CompanionStore.current();
    if (live !== null && executedIds.indexOf(live.id) >= 0) {
      CompanionStore.dismiss();
    }
    return executedIds.length + reshowIds.length;
  }

  /** 入站统一入口（传输层解码出字符串后调进来） */
  static onInbound(text: string): void {
    if (WatchBridge.echoMode) {
      Logger.info(PROBE_TAG, `收到对端消息: ${text}`);
    }
    const env: WatchEnvelope | null = WatchCodec.decode(text);
    if (env === null) {
      Logger.warn(TAG, `丢弃畸形/未知版本消息 chars=${text.length}（协议 v=${WATCH_PROTOCOL_VERSION}）`);
      return;
    }
    if (env.type === WATCH_TYPE_SYNC) {
      Logger.info(TAG, '对端请求补发当前卡（打开即见/重连对齐）');
      WatchBridge.resendCurrent();
      return;
    }
    if (env.type === WATCH_TYPE_DECISION && env.decision !== null) {
      WatchBridge.handleDecision(env.decision).catch((err: Error): void => {
        Logger.error(TAG, `决策处理失败: ${err.message}`);
      });
      return;
    }
    if (env.type === WATCH_TYPE_CARD) {
      Logger.warn(TAG, '收到对端发来的 card（只允许手机→手表），忽略');
      return;
    }
    Logger.info(TAG, `忽略消息 type=${env.type}`);
  }

  // ---- 内部 ----

  private static async handleDecision(decision: WatchDecision): Promise<void> {
    const record: WatchCardRecord | null = WatchBridge.current;
    const pre: WatchPrecheck = WatchRoute.precheck(
      record !== null && record.cardId === decision.cardId,
      record === null ? '' : record.uid,
      record === null ? 0 : record.ts,
      Date.now(), AccountStore.uid());
    if (!pre.pass) {
      // 卡已撤/已决/过时/跨账号：静默丢弃，保证幂等（US-5 / US-6 / US-10）
      Logger.warn(TAG, `丢弃决策 cardId=${decision.cardId} 原因=${pre.reason}`);
      if (pre.reason !== 'card-not-live') {
        WatchBridge.clearCurrentAndWithdraw(decision.cardId);
      }
      return;
    }
    if (record === null) {
      return;
    }
    if (record.kind === WATCH_KIND_CHECKIN) {
      await WatchBridge.handleCheckin(record, decision);
      return;
    }
    await WatchBridge.handleCompanion(record, decision);
  }

  private static async handleCheckin(record: WatchCardRecord, decision: WatchDecision): Promise<void> {
    const intent: string = WatchRoute.checkinIntent(decision.optionKey);
    if (intent === 'invalid') {
      Logger.warn(TAG, `打卡卡收到未知选项 ${decision.optionKey}`);
      return;
    }
    if (WatchBridge.processed.indexOf(decision.cardId) >= 0) {
      Logger.info(TAG, `重复决策已忽略 cardId=${decision.cardId}`);
      return;
    }
    WatchBridge.markProcessed(decision.cardId);
    // 无论打卡/跳过/划掉，手表上这张卡都应立即清掉（手机撤卡；划掉时对端本来已清，幂等无害）
    WatchBridge.clearCurrentAndWithdraw(decision.cardId);
    if (intent === 'dismiss') {
      Logger.info(TAG, `手表划掉打卡卡 cardId=${decision.cardId}`);
      return;
    }
    if (intent === 'skip') {
      Logger.info(TAG, `手表选择跳过打卡 cardId=${decision.cardId}`);
      return;
    }
    const ref: WatchCheckinRef | null = WatchCardId.parseCheckin(record.cardId);
    const context: common.Context | null = WatchBridge.context;
    if (ref === null || context === null) {
      Logger.warn(TAG, `打卡卡 cardId 无法解析 ${record.cardId}`);
      return;
    }
    try {
      // 账号分区：TripDao 按当前 uid 取，切换账号后旧卡必然取不到 → 丢弃
      const trip = await TripDao.loadTrip(context, ref.tripId);
      if (trip === null) {
        Logger.warn(TAG, `行程不属于当前账号或已删除，丢弃手表打卡 trip=${ref.tripId}`);
        return;
      }
      // evidence=null → CheckinDao 记 source='manual'（手表没有定位凭证，不伪造 arrival）
      await CheckinDao.set(context, ref.tripId, ref.stopKey, true, null);
      WatchBridge.bumpCheckinTick();
      WidgetSync.refreshAll(context).catch((err: Error): void => {
        Logger.warn(TAG, `卡片刷新失败: ${err.message}`);
      });
      Logger.info(TAG, `手表打卡落库 trip=${ref.tripId} stop=${ref.stopKey} source=manual`);
    } catch (err) {
      Logger.error(TAG, `手表打卡失败: ${(err as Error).message}`);
    }
  }

  private static async handleCompanion(record: WatchCardRecord, decision: WatchDecision): Promise<void> {
    const prompt: CompanionPrompt | null = WatchBridge.parsePrompt(record.promptJson);
    if (prompt === null) {
      Logger.warn(TAG, `原请示卡缺失，丢弃决策 cardId=${record.cardId}`);
      return;
    }
    const plan: WatchRoutePlan = WatchRoute.planCompanion(decision, {
      cardLive: true,
      pagePresent: CompanionStore.hasExecutor(),
      stake: prompt.stake,
      duplicate: WatchBridge.processed.indexOf(decision.cardId) >= 0
    });
    Logger.info(TAG, `决策 cardId=${decision.cardId} option=${decision.optionKey} → ` +
      `${plan.action}(${plan.reason})`);
    if (plan.action === 'drop') {
      return;
    }
    if (plan.action === 'dismiss') {
      WatchBridge.markProcessed(decision.cardId);
      WatchBridge.clearCurrentAndWithdraw(decision.cardId);
      CompanionStore.dismiss();
      return;
    }
    if (plan.action === 'queue') {
      WatchBridge.enqueue(record, decision, prompt);
      return;
    }
    let idx: number = -1;
    for (let i = 0; i < prompt.options.length; i++) {
      if (prompt.options[i].key === decision.optionKey) {
        idx = i;
        break;
      }
    }
    if (idx < 0) {
      Logger.warn(TAG, `选项不属于该卡 cardId=${decision.cardId} option=${decision.optionKey}`);
      return;
    }
    WatchBridge.markProcessed(decision.cardId);
    CompanionStore.prefs.recordChoice(companionDecisionKey(prompt), decision.optionKey,
      prompt.options[prompt.recommendedIndex].key);
    WatchBridge.clearCurrentAndWithdraw(decision.cardId);
    CompanionStore.execute(prompt.options[idx].action);
    // 有执行器时 dismiss 会顺带清空手机横幅；dismiss 钩子已无卡可撤，不会重复发
    CompanionStore.dismiss();
    Logger.info(TAG, `手表决策已当场执行 cardId=${decision.cardId} option=${decision.optionKey}`);
  }

  private static enqueue(record: WatchCardRecord, decision: WatchDecision, prompt: CompanionPrompt): void {
    for (const item of WatchBridge.pending) {
      if (item.cardId === decision.cardId) {
        Logger.info(TAG, `同卡已在队列，忽略重复决策 cardId=${decision.cardId}`);
        return;
      }
    }
    if (WatchBridge.pending.length >= PENDING_CAP) {
      const dropped: WatchPendingRecord | undefined = WatchBridge.pending.shift();
      if (dropped !== undefined) {
        Logger.warn(TAG, `待执行队列满，丢弃最旧 cardId=${dropped.cardId}`);
      }
    }
    const item: WatchPendingRecord = {
      cardId: decision.cardId,
      optionKey: decision.optionKey,
      uid: record.uid,
      promptJson: record.promptJson,
      stake: prompt.stake,
      ts: decision.ts
    };
    WatchBridge.pending.push(item);
    WatchBridge.savePending();
    // 手表上这张卡已经拍板，先撤掉；手机横幅保留，等回页消费
    WatchBridge.clearCurrentAndWithdraw(decision.cardId);
    Logger.info(TAG, `离页决策入队 cardId=${decision.cardId} option=${decision.optionKey} ` +
      `stake=${prompt.stake}`);
  }

  private static clearCurrentAndWithdraw(cardId: string): void {
    WatchBridge.current = null;
    WatchBridge.saveCurrent();
    WatchBridge.sendWithdraw(cardId);
  }

  private static resendCurrent(): void {
    const record: WatchCardRecord | null = WatchBridge.current;
    if (record === null) {
      return;
    }
    if (WatchRoute.isStale(record.ts, Date.now())) {
      Logger.info(TAG, `当前卡已过期，补发改为撤卡 cardId=${record.cardId}`);
      WatchBridge.clearCurrentAndWithdraw(record.cardId);
      return;
    }
    if (WatchRoute.isForeignAccount(record.uid, AccountStore.uid())) {
      Logger.info(TAG, `当前卡属于其他账号，补发改为撤卡 cardId=${record.cardId}`);
      WatchBridge.clearCurrentAndWithdraw(record.cardId);
      return;
    }
    if (record.kind === WATCH_KIND_CHECKIN) {
      WatchBridge.sendCard(
        WatchProjection.checkinCard(record.tripId, record.stopKey, record.stopTitle, Date.now()));
      return;
    }
    const prompt: CompanionPrompt | null = WatchBridge.parsePrompt(record.promptJson);
    if (prompt === null) {
      return;
    }
    WatchBridge.publishPrompt(prompt);
  }

  private static sendCard(card: WatchCard): void {
    if (!WatchBridge.transport.isConnected()) {
      // 通道不可用（G0 未过 / 手表不在附近）：卡只留在手机侧，不刷失败日志
      return;
    }
    WatchBridge.transport.send(WatchCodec.encodeCard(card)).then((ok: boolean): void => {
      Logger.info(TAG, `卡片出站 ${card.kind} cardId=${card.cardId} ok=${ok}`);
    }).catch((err: Error): void => {
      Logger.warn(TAG, `卡片出站异常: ${err.message}`);
    });
  }

  private static sendWithdraw(cardId: string): void {
    if (!WatchBridge.transport.isConnected()) {
      return;
    }
    WatchBridge.transport.send(WatchCodec.encodeWithdraw(cardId, Date.now())).then((ok: boolean): void => {
      Logger.info(TAG, `撤卡出站 cardId=${cardId} ok=${ok}`);
    }).catch((err: Error): void => {
      Logger.warn(TAG, `撤卡出站异常: ${err.message}`);
    });
  }

  /** G0 回声探针随 Wear Engine 停用；保留空实现避免旧调试入口报错 */
  private static async echoHello(): Promise<void> {
    Logger.warn(PROBE_TAG, 'wearecho 已停用，请使用 watchnetprobe');
  }

  private static bumpCheckinTick(): void {
    const tick: number = AppStorage.get<number>(WATCH_CHECKIN_TICK_KEY) ?? 0;
    AppStorage.setOrCreate(WATCH_CHECKIN_TICK_KEY, tick + 1);
  }

  private static parsePrompt(json: string): CompanionPrompt | null {
    if (json.length === 0) {
      return null;
    }
    try {
      return JSON.parse(json) as CompanionPrompt;
    } catch (err) {
      return null;
    }
  }

  private static markProcessed(cardId: string): void {
    if (WatchBridge.processed.indexOf(cardId) >= 0) {
      return;
    }
    WatchBridge.processed.push(cardId);
    while (WatchBridge.processed.length > PROCESSED_CAP) {
      WatchBridge.processed.shift();
    }
    WatchBridge.saveProcessed();
  }

  private static load(context: common.Context): void {
    try {
      const store: preferences.Preferences =
        preferences.getPreferencesSync(context, { name: PREFS_NAME });
      const rawCurrent: preferences.ValueType = store.getSync(KEY_CURRENT, '');
      if (typeof rawCurrent === 'string' && (rawCurrent as string).length > 0) {
        WatchBridge.current = JSON.parse(rawCurrent as string) as WatchCardRecord;
      }
      const rawPending: preferences.ValueType = store.getSync(KEY_PENDING, '');
      if (typeof rawPending === 'string' && (rawPending as string).length > 0) {
        const parsed: Object = JSON.parse(rawPending as string) as Object;
        if (Array.isArray(parsed)) {
          WatchBridge.pending = parsed as WatchPendingRecord[];
        }
      }
      const rawProcessed: preferences.ValueType = store.getSync(KEY_PROCESSED, '');
      if (typeof rawProcessed === 'string' && (rawProcessed as string).length > 0) {
        const parsed: Object = JSON.parse(rawProcessed as string) as Object;
        if (Array.isArray(parsed)) {
          WatchBridge.processed = parsed as string[];
        }
      }
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      Logger.warn(TAG, `桥接状态读取失败，按空态继续: ${be.message}`);
      WatchBridge.current = null;
      WatchBridge.pending = [];
      WatchBridge.processed = [];
    }
  }

  private static saveCurrent(): void {
    const text: string = WatchBridge.current === null ? '' : JSON.stringify(WatchBridge.current);
    WatchBridge.put(KEY_CURRENT, text);
  }

  private static savePending(): void {
    WatchBridge.put(KEY_PENDING, JSON.stringify(WatchBridge.pending));
  }

  private static saveProcessed(): void {
    WatchBridge.put(KEY_PROCESSED, JSON.stringify(WatchBridge.processed));
  }

  private static put(key: string, text: string): void {
    const context: common.Context | null = WatchBridge.context;
    if (context === null) {
      return;
    }
    try {
      const store: preferences.Preferences =
        preferences.getPreferencesSync(context, { name: PREFS_NAME });
      store.putSync(key, text);
      store.flushSync();
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      Logger.warn(TAG, `桥接状态写入失败 ${key}: ${be.message}`);
    }
  }
}
