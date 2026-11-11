/**
 * 伴随助手 · 核心引擎（纯逻辑，无 @kit/UI 依赖，可离线断言）。
 *
 * 立场：助手站在「现实」这边。计划 vs 现实有真实后果时才开口；没后果就安静吸收。
 * 开口即「请示」——端出带默认推荐的可点选选项，把后果算清，用户一键拍板。
 * Phase 1 旗舰能力：规划外到访（用户去了计划外的地方）。
 *
 * 引擎只产出 CompanionPrompt（结构化意图），不直接改行程；执行由集成层接 SkipPlanner/commitDay。
 */

import { Activity, ActivityCategory, TripDay } from '../model/Trip';
import { DateUtils } from '../utils/DateUtils';
import { CompanionPrefs } from './CompanionPrefs';
import {
  CompanionAction, CompanionOption, CompanionPrompt, UnplannedInput
} from './CompanionTypes';

/** 偏好降级键：规划外到访「挪明天」决定 */
const KEY_MOVE_TOMORROW: string = 'unplanned_move_tomorrow';

export class CompanionEngine {
  /**
   * 规划外到访请示。返回 null = 无后果，安静吸收（不打扰）。
   * 未识别地点 → 轻问卡；已识别且有后果 → 三选项请示卡。
   */
  static unplannedArrival(input: UnplannedInput, prefs: CompanionPrefs): CompanionPrompt | null {
    if (!input.recognized) {
      return CompanionEngine.unknownPlacePrompt();
    }
    const next: Activity | null = CompanionEngine.nextStop(input.day, input.nowMin);
    if (next === null) {
      return null; // 后面没有会被挤占的站，安静吸收
    }
    const nextStart: number = DateUtils.minutesOf(next.time);
    if (input.nowMin + input.estVisitMin <= nextStart) {
      return null; // 塞得下，无后果，不打扰
    }
    return CompanionEngine.conflictPrompt(input, next, prefs);
  }

  /** 当日 nowMin 之后第一个真实景点（剔除交通/住宿腿）。 */
  private static nextStop(day: TripDay, nowMin: number): Activity | null {
    for (const a of day.activities) {
      if (a.category === ActivityCategory.TRANSPORT || a.category === ActivityCategory.HOTEL) {
        continue;
      }
      if (DateUtils.minutesOf(a.time) > nowMin) {
        return a;
      }
    }
    return null;
  }

  /** 未识别地点：轻问，不硬判（测不准留余地）。永远请示，不降级。 */
  private static unknownPlacePrompt(): CompanionPrompt {
    const recordAction: CompanionAction = {
      kind: 'record_place', targetId: '', deltaMin: 0, placeName: ''
    };
    const skipAction: CompanionAction = {
      kind: 'none', targetId: '', deltaMin: 0, placeName: ''
    };
    const record: CompanionOption = {
      key: 'record_place', label: '记下来', subline: '记进这趟行程，行后能回顾', action: recordAction
    };
    const skip: CompanionOption = {
      key: 'skip', label: '跳过', subline: '路过而已，不用记', action: skipAction
    };
    const prompt: CompanionPrompt = {
      id: 'unknown_place', kind: 'unknown_place',
      title: '到了个新地方', detail: '这地方叫什么？要不要记进这趟行程？',
      options: [record, skip], recommendedIndex: 0, stake: 'low', mode: 'ask'
    };
    return prompt;
  }

  /** 已识别且挤占下一站：三选项请示，推荐「挪明天」。 */
  private static conflictPrompt(input: UnplannedInput, next: Activity, prefs: CompanionPrefs): CompanionPrompt {
    const place: string = input.placeName;
    const moveAction: CompanionAction = {
      kind: 'move_tomorrow', targetId: next.id, deltaMin: 0, placeName: place
    };
    const quickAction: CompanionAction = {
      kind: 'quick_visit', targetId: '', deltaMin: 0, placeName: place
    };
    const keepAction: CompanionAction = {
      kind: 'record_place', targetId: '', deltaMin: 0, placeName: place
    };
    const move: CompanionOption = {
      key: 'move_tomorrow', label: `留着${place}，${next.title}挪明天`,
      subline: '今天从容逛，明天我提醒你', action: moveAction
    };
    const quick: CompanionOption = {
      key: 'quick_visit', label: `快逛一下，赶得上${next.title}`,
      subline: '压缩游览，刚好不挤占下一站', action: quickAction
    };
    const keep: CompanionOption = {
      key: 'keep_plan', label: '按原计划走',
      subline: `${place}记下来下次去`, action: keepAction
    };
    const prompt: CompanionPrompt = {
      id: `unplanned-${place}-${next.id}`, kind: 'unplanned_arrival',
      title: `你到了${place}——不在今天计划里`,
      detail: `它大概要 ${input.estVisitMin} 分钟，会挤占 ${next.title}（${next.time}）。怎么安排？`,
      options: [move, quick, keep], recommendedIndex: 0, stake: 'low',
      mode: prefs.modeFor(KEY_MOVE_TOMORROW)
    };
    return prompt;
  }
}