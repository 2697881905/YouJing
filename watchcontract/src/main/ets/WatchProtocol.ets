/**
 * 有径手表 B 路径 · 线协议（单一真源）。
 *
 * 纪律（见 Docs/superpowers/specs/2026-11-13-watch-interaction-b-path.md §6）：
 * - 本文件只放纯数据与纯函数，**禁止 import 任何 @kit / 页面 / DAO**，两端共用同一份。
 * - 手机是唯一裁决者：手表只回 optionKey，不回 action；action 由手机按 cardId 找回原请示卡。
 * - 未知 v / 畸形 JSON 一律返回 null，由调用方静默忽略并打日志，绝不崩。
 *
 * 传输：Wear Engine P2P 消息（Uint8Array，单条 [1, 4096) 字节，见本机 SDK
 * @hms.health.wearEngine.d.ts sendMessage 注释），这里只负责 JSON 字符串。
 */

/** 协议版本：手机与手表必须同版本，未知版本静默丢弃 */
export const WATCH_PROTOCOL_VERSION: number = 1;

export const WATCH_TYPE_CARD: string = 'card';
export const WATCH_TYPE_DECISION: string = 'decision';
/** 手机撤卡（用户在手机点选/划掉），手表据此清屏 */
export const WATCH_TYPE_WITHDRAW: string = 'withdraw';
/** 手表请求补发当前卡（打开即见 / 重连后对齐，G0-d 拉取式也靠它） */
export const WATCH_TYPE_SYNC: string = 'sync';

/** 请示卡：与 CompanionPrompt 同源 */
export const WATCH_KIND_COMPANION: string = 'companion';
/** 到站打卡卡：独立建模（F8），不进 CompanionPrompt */
export const WATCH_KIND_CHECKIN: string = 'checkin';

/** 划掉/超时的统一选项键 */
export const WATCH_DISMISS_KEY: string = '__dismiss__';
export const WATCH_OPTION_CHECKIN: string = 'checkin';
export const WATCH_OPTION_SKIP: string = 'skip';

/** 对端应用：手机与手表同属一个应用（同 bundleName） */
export const WATCH_REMOTE_BUNDLE: string = 'com.youjing.app';
/**
 * 对端应用指纹。Wear Engine 的 AppInfo 要求 bundleName + fingerprint 成对；
 * 指纹的真实取值与申请路径正是 G0-c 要取证的问题——真机探针前保持空串，
 * 由真机日志确认是否需要从 AGC「Wear Engine 服务」处获取后回填。
 */
export const WATCH_REMOTE_FINGERPRINT: string = '';

/** 单条消息上限（SDK 注释：[1, 4096) 字节） */
export const WATCH_MAX_MESSAGE_BYTES: number = 4096;
/** 我们自己留的发送预算：贴近上限就截断，别让对端整条丢 */
export const WATCH_SEND_BUDGET_BYTES: number = 4000;

/** 手表可读长度上限：圆屏一屏一卡，宁短勿挤 */
export const WATCH_MAX_TITLE: number = 40;
export const WATCH_MAX_DETAIL: number = 60;
export const WATCH_MAX_LABEL: number = 12;
export const WATCH_MAX_SUBLINE: number = 16;
export const WATCH_MAX_OPTIONS: number = 3;

/** 一个选项的扁平投影（只给手表看的文案，不带 action） */
export interface WatchOption {
  key: string;
  label: string;
  subline: string;
}

/** 手机 → 手表：一屏一卡 */
export interface WatchCard {
  v: number;
  type: string;
  /** 去重/对账键：请示卡复用 CompanionPrompt.id；打卡卡见 WatchCardId */
  cardId: string;
  kind: string;
  title: string;
  detail: string;
  /** 至多 3 个；打卡固定 2 个 */
  options: WatchOption[];
  /** 推荐项 key（手表高亮） */
  recommendedKey: string;
  /** 手机发出时刻（毫秒），手表用于过期判断 */
  ts: number;
}

/** 手表 → 手机：只回 key */
export interface WatchDecision {
  v: number;
  type: string;
  cardId: string;
  optionKey: string;
  ts: number;
}

/** 手机 → 手表：撤卡 */
export interface WatchWithdraw {
  v: number;
  type: string;
  cardId: string;
  ts: number;
}

/** 手表 → 手机：请求补发当前卡 */
export interface WatchSync {
  v: number;
  type: string;
  ts: number;
}

/** 解包结果：type 决定哪个字段非空（ArkTS 不做联合类型窄化，故用可空字段收口） */
export interface WatchEnvelope {
  type: string;
  card: WatchCard | null;
  decision: WatchDecision | null;
  withdraw: WatchWithdraw | null;
}

/** 投影输入：CompanionPrompt 的结构子集（避免 HAR 反向依赖 entry） */
export interface WatchSourceOption {
  key: string;
  label: string;
  subline: string;
}

export interface WatchSourcePrompt {
  id: string;
  kind: string;
  title: string;
  detail: string;
  options: WatchSourceOption[];
  recommendedIndex: number;
  /** 'low' | 'high'；手机路由用，手表不感知 */
  stake: string;
}

export class WatchCodec {
  static encodeCard(card: WatchCard): string {
    return JSON.stringify(card);
  }

  static encodeDecision(decision: WatchDecision): string {
    return JSON.stringify(decision);
  }

  static encodeWithdraw(cardId: string, ts: number): string {
    const msg: WatchWithdraw = {
      v: WATCH_PROTOCOL_VERSION, type: WATCH_TYPE_WITHDRAW, cardId: cardId, ts: ts
    };
    return JSON.stringify(msg);
  }

  static encodeSync(ts: number): string {
    const msg: WatchSync = { v: WATCH_PROTOCOL_VERSION, type: WATCH_TYPE_SYNC, ts: ts };
    return JSON.stringify(msg);
  }

  /** 解包；任何不合法都返回 null（调用方负责打日志） */
  static decode(raw: string): WatchEnvelope | null {
    const obj: Record<string, Object> | null = WatchCodec.asRecord(raw);
    if (obj === null) {
      return null;
    }
    if (WatchCodec.numOf(obj, 'v') !== WATCH_PROTOCOL_VERSION) {
      return null;
    }
    const type: string = WatchCodec.strOf(obj, 'type');
    if (type === WATCH_TYPE_CARD) {
      const card: WatchCard | null = WatchCodec.readCard(obj);
      if (card === null) {
        return null;
      }
      const env: WatchEnvelope = { type: type, card: card, decision: null, withdraw: null };
      return env;
    }
    if (type === WATCH_TYPE_DECISION) {
      const decision: WatchDecision | null = WatchCodec.readDecision(obj);
      if (decision === null) {
        return null;
      }
      const env: WatchEnvelope = { type: type, card: null, decision: decision, withdraw: null };
      return env;
    }
    if (type === WATCH_TYPE_WITHDRAW) {
      const withdraw: WatchWithdraw | null = WatchCodec.readWithdraw(obj);
      if (withdraw === null) {
        return null;
      }
      const env: WatchEnvelope = { type: type, card: null, decision: null, withdraw: withdraw };
      return env;
    }
    if (type === WATCH_TYPE_SYNC) {
      const env: WatchEnvelope = { type: type, card: null, decision: null, withdraw: null };
      return env;
    }
    return null;
  }

  static decodeDecision(raw: string): WatchDecision | null {
    const env: WatchEnvelope | null = WatchCodec.decode(raw);
    return env === null ? null : env.decision;
  }

  static decodeCard(raw: string): WatchCard | null {
    const env: WatchEnvelope | null = WatchCodec.decode(raw);
    return env === null ? null : env.card;
  }

  private static readCard(obj: Record<string, Object>): WatchCard | null {
    const cardId: string = WatchCodec.strOf(obj, 'cardId');
    const kind: string = WatchCodec.strOf(obj, 'kind');
    const title: string = WatchCodec.strOf(obj, 'title');
    const ts: number = WatchCodec.numOf(obj, 'ts');
    if (cardId.length === 0 || title.length === 0 || ts <= 0) {
      return null;
    }
    if (kind !== WATCH_KIND_COMPANION && kind !== WATCH_KIND_CHECKIN) {
      return null;
    }
    const rawOptions: Object | undefined = obj['options'];
    if (!Array.isArray(rawOptions)) {
      return null;
    }
    const list: Object[] = rawOptions as Object[];
    if (list.length === 0) {
      return null;
    }
    const options: WatchOption[] = [];
    for (let i = 0; i < list.length && i < WATCH_MAX_OPTIONS; i++) {
      const item: Object = list[i];
      if (typeof item !== 'object' || item === null || Array.isArray(item)) {
        return null;
      }
      const o: Record<string, Object> = item as Record<string, Object>;
      const key: string = WatchCodec.strOf(o, 'key');
      const label: string = WatchCodec.strOf(o, 'label');
      if (key.length === 0 || label.length === 0) {
        return null;
      }
      const option: WatchOption = { key: key, label: label, subline: WatchCodec.strOf(o, 'subline') };
      options.push(option);
    }
    let recommended: string = WatchCodec.strOf(obj, 'recommendedKey');
    let matched: boolean = false;
    for (const option of options) {
      if (option.key === recommended) {
        matched = true;
        break;
      }
    }
    if (!matched) {
      recommended = options[0].key;
    }
    const card: WatchCard = {
      v: WATCH_PROTOCOL_VERSION, type: WATCH_TYPE_CARD, cardId: cardId, kind: kind,
      title: title, detail: WatchCodec.strOf(obj, 'detail'), options: options,
      recommendedKey: recommended, ts: ts
    };
    return card;
  }

  private static readDecision(obj: Record<string, Object>): WatchDecision | null {
    const cardId: string = WatchCodec.strOf(obj, 'cardId');
    const optionKey: string = WatchCodec.strOf(obj, 'optionKey');
    const ts: number = WatchCodec.numOf(obj, 'ts');
    if (cardId.length === 0 || optionKey.length === 0 || ts <= 0) {
      return null;
    }
    const decision: WatchDecision = {
      v: WATCH_PROTOCOL_VERSION, type: WATCH_TYPE_DECISION, cardId: cardId,
      optionKey: optionKey, ts: ts
    };
    return decision;
  }

  private static readWithdraw(obj: Record<string, Object>): WatchWithdraw | null {
    const cardId: string = WatchCodec.strOf(obj, 'cardId');
    const ts: number = WatchCodec.numOf(obj, 'ts');
    if (cardId.length === 0 || ts <= 0) {
      return null;
    }
    const withdraw: WatchWithdraw = {
      v: WATCH_PROTOCOL_VERSION, type: WATCH_TYPE_WITHDRAW, cardId: cardId, ts: ts
    };
    return withdraw;
  }

  private static asRecord(raw: string): Record<string, Object> | null {
    if (raw.length === 0) {
      return null;
    }
    try {
      const parsed: Object = JSON.parse(raw) as Object;
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
        return null;
      }
      return parsed as Record<string, Object>;
    } catch (err) {
      return null;
    }
  }

  private static strOf(obj: Record<string, Object>, key: string): string {
    const value: Object | undefined = obj[key];
    return typeof value === 'string' ? value as string : '';
  }

  private static numOf(obj: Record<string, Object>, key: string): number {
    const value: Object | undefined = obj[key];
    return typeof value === 'number' ? value as number : Number.NaN;
  }
}

/** 打卡卡的 cardId 编解码：`checkin-<tripId>-<stopKey>` */
export interface WatchCheckinRef {
  tripId: string;
  stopKey: string;
}

export class WatchCardId {
  private static readonly CHECKIN_PREFIX: string = 'checkin-';

  /**
   * 段内 '-' 会破坏「前缀后按第一个 '-' 切分」的可逆性，故先把 '%' 与 '-' 转义。
   * tripId / stopKey 由本工程生成（uuid / 活动 id / meal-key），不含 '%2D' 字面量。
   */
  static checkin(tripId: string, stopKey: string): string {
    return `${WatchCardId.CHECKIN_PREFIX}${WatchCardId.escape(tripId)}-${WatchCardId.escape(stopKey)}`;
  }

  static isCheckin(cardId: string): boolean {
    return cardId.startsWith(WatchCardId.CHECKIN_PREFIX);
  }

  /** 解析失败返回 null（畸形 cardId 一律丢弃，不猜） */
  static parseCheckin(cardId: string): WatchCheckinRef | null {
    if (!WatchCardId.isCheckin(cardId)) {
      return null;
    }
    const rest: string = cardId.substring(WatchCardId.CHECKIN_PREFIX.length);
    const cut: number = rest.indexOf('-');
    if (cut <= 0 || cut >= rest.length - 1) {
      return null;
    }
    const ref: WatchCheckinRef = {
      tripId: WatchCardId.unescape(rest.substring(0, cut)),
      stopKey: WatchCardId.unescape(rest.substring(cut + 1))
    };
    if (ref.tripId.length === 0 || ref.stopKey.length === 0) {
      return null;
    }
    return ref;
  }

  private static escape(part: string): string {
    return part.split('%').join('%25').split('-').join('%2D');
  }

  private static unescape(part: string): string {
    return part.split('%2D').join('-').split('%25').join('%');
  }
}
