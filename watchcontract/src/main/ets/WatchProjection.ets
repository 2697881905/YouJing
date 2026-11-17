/**
 * CompanionPrompt / 到站打卡 → WatchCard 的扁平投影（纯函数，可离线断言）。
 *
 * 手表只吃扁平 DTO：不搬 UnplannedInput.day（TripDay）这类重对象，
 * 也不搬 CompanionAction——执行语义永远留在手机侧。
 */

import {
  WATCH_KIND_CHECKIN, WATCH_KIND_COMPANION, WATCH_MAX_DETAIL, WATCH_MAX_LABEL, WATCH_MAX_OPTIONS,
  WATCH_MAX_SUBLINE, WATCH_MAX_TITLE, WATCH_OPTION_CHECKIN, WATCH_OPTION_SKIP, WATCH_PROTOCOL_VERSION,
  WATCH_TYPE_CARD, WatchCard, WatchCardId, WatchOption, WatchSourcePrompt
} from './WatchProtocol';

export class WatchProjection {
  /** 请示卡投影：title/detail/options 直取，recommendedKey = options[recommendedIndex].key */
  static fromPrompt(src: WatchSourcePrompt, nowTs: number): WatchCard {
    const options: WatchOption[] = [];
    for (let i = 0; i < src.options.length && options.length < WATCH_MAX_OPTIONS; i++) {
      const option: WatchOption = {
        key: src.options[i].key,
        label: WatchProjection.clamp(src.options[i].label, WATCH_MAX_LABEL),
        subline: WatchProjection.clamp(src.options[i].subline, WATCH_MAX_SUBLINE)
      };
      if (option.key.length > 0 && option.label.length > 0) {
        options.push(option);
      }
    }
    if (options.length === 0) {
      // 畸形源（正常不会发生）：给一个可收起的兜底，保证卡在手表上不是死屏
      options.push({ key: '__dismiss__', label: '知道了', subline: '' });
    }
    let recommendedIndex: number = src.recommendedIndex;
    if (recommendedIndex < 0 || recommendedIndex >= src.options.length) {
      recommendedIndex = 0;
    }
    let recommendedKey: string = options[0].key;
    if (recommendedIndex < src.options.length) {
      const wanted: string = src.options[recommendedIndex].key;
      for (const option of options) {
        if (option.key === wanted) {
          recommendedKey = wanted;
          break;
        }
      }
    }
    const card: WatchCard = {
      v: WATCH_PROTOCOL_VERSION,
      type: WATCH_TYPE_CARD,
      cardId: src.id,
      kind: WATCH_KIND_COMPANION,
      title: WatchProjection.clamp(src.title, WATCH_MAX_TITLE),
      detail: WatchProjection.clamp(src.detail, WATCH_MAX_DETAIL),
      options: options,
      recommendedKey: recommendedKey,
      ts: nowTs
    };
    return card;
  }

  /**
   * 到站打卡卡（F8：打卡不属于 CompanionPrompt，单独建模）。
   * options 固定「打卡 / 跳过」，推荐打卡；detail 只说明后果，不承诺落库成功。
   */
  static checkinCard(tripId: string, stopKey: string, stopTitle: string, nowTs: number): WatchCard {
    const options: WatchOption[] = [
      { key: WATCH_OPTION_CHECKIN, label: '打卡', subline: '' },
      { key: WATCH_OPTION_SKIP, label: '跳过', subline: '' }
    ];
    const card: WatchCard = {
      v: WATCH_PROTOCOL_VERSION,
      type: WATCH_TYPE_CARD,
      cardId: WatchCardId.checkin(tripId, stopKey),
      kind: WATCH_KIND_CHECKIN,
      title: WatchProjection.clamp(`到「${stopTitle}」了，打卡吗？`, WATCH_MAX_TITLE),
      detail: '打卡后行程进度立即更新',
      options: options,
      recommendedKey: WATCH_OPTION_CHECKIN,
      ts: nowTs
    };
    return card;
  }

  /** 截断到手表可读长度；超长补省略号（不静默丢字） */
  static clamp(text: string, max: number): string {
    if (max <= 0) {
      return '';
    }
    if (text.length <= max) {
      return text;
    }
    if (max === 1) {
      return '…';
    }
    return `${text.substring(0, max - 1)}…`;
  }
}
