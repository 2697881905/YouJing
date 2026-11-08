/**
 * 跳过与重排的端侧纯逻辑（方案 §3.3 / §3.5）。
 *
 * 分工：LLM 只决定「保留谁、每站停多久、空档放哪」；时间算术全部在这里，
 * 可离线断言，不依赖 @kit / RDB / UI。
 */

import { DurationCn } from '../utils/DurationCn';
import {
  Activity, ActivityCategory, ActivityStatus, Meal, TransportInfo, TripDay
} from '../model/Trip';
import {
  FreeBlock, KeepStop, ReplanDecision, ReplanOutcome, ReplanRequest, ReplanRequestActivity,
  ReplanRequestDay, ReplanRequestMeal, ReplanTransport, REPLAN_ADD_BUDGET_MIN, REPLAN_MAX_DWELL,
  REPLAN_MAX_FREE_BLOCKS, REPLAN_MAX_FREE_MIN, REPLAN_MAX_KEEP, REPLAN_MAX_NOTE, REPLAN_MIN_DWELL,
  REPLAN_MIN_FREE_MIN, REPLAN_SCHEMA_VERSION
} from '../model/Replan';
import { DateUtils } from '../utils/DateUtils';
import { DayLoad, DayLoadCalc } from '../utils/DayLoad';

const DAY_END: number = 1439;
const MEAL_ANCHOR_MIN: number = 60;
const DEFAULT_DWELL_MIN: number = 60;
const CARRY_MARK: string = '待调整';
const FREE_TITLE: string = '空闲';
const SKIP_NOTE_PREFIX: string = '已跳过：';
const MAX_SETTLE_LOOP: number = 32;

interface Span {
  start: number;
  end: number;
}

interface FreeState {
  afterId: string;
  minutes: number;
  used: boolean;
  expired: boolean;
}

interface ScheduleResult {
  overflow: boolean;
  overflowFrom: number;
}

interface FallbackResult {
  day: TripDay;
  overflow: boolean;
}

export class SkipPlanner {
  /** 旅行中页的「不去」入口只看这条；排程的 remaining 口径更宽（REST 仍算站点）。 */
  static isSkippable(category: ActivityCategory | null, status: ActivityStatus | null): boolean {
    if (category === null || status === null || status === ActivityStatus.BOOKED) {
      return false;
    }
    return category !== ActivityCategory.TRANSPORT && category !== ActivityCategory.HOTEL &&
      category !== ActivityCategory.REST;
  }

  /** 上一次跳过留下的空闲段：界面上不再当可打卡站点展示，但它仍是排程锚点。 */
  static isSkippedMarker(a: Activity): boolean {
    return a.category === ActivityCategory.REST && a.status === ActivityStatus.NO_NEED &&
      a.title === FREE_TITLE;
  }

  /** 深拷贝当日，供改写 / 撤销快照使用；TripDay 的字段全部显式复制。 */
  static cloneDay(day: TripDay): TripDay {
    const acts: Activity[] = [];
    for (const a of day.activities) {
      acts.push(SkipPlanner.cloneActivity(a));
    }
    const meals: Meal[] = [];
    for (const m of day.meals) {
      meals.push(SkipPlanner.cloneMeal(m));
    }
    const copy: TripDay = {
      dayIndex: day.dayIndex,
      date: day.date,
      theme: day.theme,
      intensity: day.intensity,
      dailyCost: day.dailyCost,
      activities: acts,
      meals: meals
    };
    if (day.risk !== undefined) {
      copy.risk = day.risk;
    }
    if (day.accommodation !== undefined) {
      copy.accommodation = day.accommodation;
    }
    return copy;
  }

  /**
   * 方案 §3.3 的「剩余站点」：当日 activities 中
   * id ≠ skippedId、category ∉ {TRANSPORT, HOTEL}、status ≠ BOOKED、time ≥ nowMinutes。
   * 注意：REST 不是锚点，仍会出现在这里（只有本次被跳过的那个 id 排除）。
   */
  static remainingIds(day: TripDay, skippedId: string, nowMin: number): string[] {
    const ids: string[] = [];
    for (const a of day.activities) {
      if (a.id === skippedId) {
        continue;
      }
      if (a.category === ActivityCategory.TRANSPORT || a.category === ActivityCategory.HOTEL) {
        continue;
      }
      if (a.status === ActivityStatus.BOOKED) {
        continue;
      }
      if (DateUtils.minutesOf(a.time) < nowMin) {
        continue;
      }
      ids.push(a.id);
    }
    return ids;
  }

  /** 请求发送「重写前」的整日；剩余列表由云函数自行重算（§3.4）。 */
  static buildRequest(day: TripDay, skippedId: string, nowMin: number): ReplanRequest {
    const request: ReplanRequest = SkipPlanner.baseRequest(day, nowMin);
    request.skippedId = skippedId;
    return request;
  }

  /** 加一站：把新站带临时时刻放进请求，云函数据此把它排进 keep。 */
  static buildAddRequest(day: TripDay, newStop: Activity, nowMin: number): ReplanRequest {
    const work: TripDay = SkipPlanner.cloneDay(day);
    const added: Activity = SkipPlanner.cloneActivity(newStop);
    work.activities.push(added);
    SkipPlanner.provisionalSlot(work, added, nowMin);
    const request: ReplanRequest = SkipPlanner.baseRequest(work, nowMin);
    request.addStopId = added.id;
    return request;
  }

  /** P3 对话式：把自然语言意愿 + 候选池发给云函数，由它映射四种动作。 */
  static buildIntentRequest(day: TripDay, intentText: string, candidates: Activity[],
    nowMin: number): ReplanRequest {
    const request: ReplanRequest = SkipPlanner.baseRequest(day, nowMin);
    request.intentText = intentText;
    const list: ReplanRequestActivity[] = [];
    for (const a of candidates) {
      list.push(SkipPlanner.requestActivityOf(a));
    }
    if (list.length > 0) {
      request.candidates = list;
    }
    return request;
  }

  private static requestActivityOf(a: Activity): ReplanRequestActivity {
    const item: ReplanRequestActivity = {
      id: a.id,
      time: a.time,
      endTime: a.endTime,
      title: a.title,
      category: a.category,
      status: a.status,
      longitude: a.longitude,
      latitude: a.latitude
    };
    if (a.transport !== undefined) {
      const t: ReplanTransport = { duration: a.transport.duration };
      item.transport = t;
    }
    return item;
  }

  private static baseRequest(day: TripDay, nowMin: number): ReplanRequest {
    const acts: ReplanRequestActivity[] = [];
    for (const a of day.activities) {
      acts.push(SkipPlanner.requestActivityOf(a));
    }
    const meals: ReplanRequestMeal[] = [];
    for (const m of day.meals) {
      const item: ReplanRequestMeal = { type: m.type };
      if (m.time !== undefined) {
        item.time = m.time;
      }
      meals.push(item);
    }
    const requestDay: ReplanRequestDay = { date: day.date, activities: acts, meals: meals };
    const request: ReplanRequest = {
      schemaVersion: REPLAN_SCHEMA_VERSION,
      now: DateUtils.hhmmOf(nowMin),
      day: requestDay
    };
    return request;
  }

  /**
   * 主入口。decision 为 null 或未通过守卫 → 本地兜底。
   * 无论走哪条路，都会完成「被跳过项原地改写」。
   */
  static plan(day: TripDay, skippedId: string, nowMin: number,
    decision: ReplanDecision | null): ReplanOutcome {
    const index: number = SkipPlanner.indexOf(day, skippedId);
    if (index < 0) {
      const copy: TripDay = SkipPlanner.cloneDay(day);
      const missNote: string = '未找到要跳过的站点';
      const miss: ReplanOutcome = { day: copy, note: missNote, usedFallback: false };
      return miss;
    }
    const skipped: Activity = day.activities[index];
    const title: string = skipped.title;
    const startMin: number = SkipPlanner.startOf(skipped);
    const endMin: number = SkipPlanner.normalizedEnd(skipped, startMin);
    const remainIds: string[] = SkipPlanner.remainingIds(day, skippedId, nowMin);

    if (decision !== null && SkipPlanner.accept(day, decision, remainIds)) {
      const work: TripDay = SkipPlanner.cloneDay(day);
      SkipPlanner.rewriteSkipped(work.activities[index], startMin, endMin, title);
      const scheduled: ScheduleResult = SkipPlanner.schedule(work, skippedId, startMin, endMin,
        nowMin, decision);
      const placedIds: string[] = [];
      for (let i = 0; i < scheduled.overflowFrom; i++) {
        placedIds.push(decision.keep[i].id);
      }
      const carryIds: string[] = [];
      for (let i = scheduled.overflowFrom; i < decision.keep.length; i++) {
        carryIds.push(decision.keep[i].id);
      }
      if (SkipPlanner.valid(work, day, skippedId, nowMin, placedIds, carryIds)) {
        const note: string = SkipPlanner.noteFor(title, decision, scheduled.overflow, false);
        const okOutcome: ReplanOutcome = { day: work, note: note, usedFallback: false };
        return okOutcome;
      }
    }

    const fallback: FallbackResult = SkipPlanner.fallback(day, skippedId, index, startMin, endMin,
      nowMin, remainIds);
    const fallbackNote: string = SkipPlanner.noteFor(title, null, fallback.overflow, true);
    const outcome: ReplanOutcome = {
      day: fallback.day,
      note: fallbackNote,
      usedFallback: true
    };
    return outcome;
  }

  // ---- 加一站 / 换一站（P2）----

  /**
   * 加一站：云函数决策可用就按 keep 重排未来站点，否则本地追加到日末。
   * 两条路最后都过同一道 480min 预算闸；超预算不改行程，changed=false。
   */
  static planWithAddition(day: TripDay, newStop: Activity, nowMin: number,
    decision: ReplanDecision | null): ReplanOutcome {
    if (SkipPlanner.indexOf(day, newStop.id) >= 0) {
      return SkipPlanner.unchanged(day, '这一站已经在今天的行程里');
    }
    const work: TripDay = SkipPlanner.cloneDay(day);
    const added: Activity = SkipPlanner.cloneActivity(newStop);
    work.activities.push(added);
    SkipPlanner.provisionalSlot(work, added, nowMin);
    const remainIds: string[] = SkipPlanner.remainingIds(work, '', nowMin);
    if (decision !== null && SkipPlanner.accept(work, decision, remainIds)) {
      const scheduled: ScheduleResult = SkipPlanner.scheduleAddition(work, added.id, nowMin, decision);
      if (!scheduled.overflow) {
        const placedIds: string[] = decision.keep.map((k: KeepStop): string => k.id);
        if (SkipPlanner.validAddition(work, day, added.id, nowMin, placedIds)) {
          const over: string = SkipPlanner.budgetNote(work, added.title);
          if (over.length === 0) {
            const note: string = decision.note.length > 0 ? decision.note : `已加入「${added.title}」`;
            const ok: ReplanOutcome = { day: work, note: note, usedFallback: false, changed: true };
            return ok;
          }
          return SkipPlanner.unchanged(day, over);
        }
      }
    }
    const local: TripDay = SkipPlanner.cloneDay(day);
    const localAdded: Activity = SkipPlanner.cloneActivity(newStop);
    local.activities.push(localAdded);
    if (!SkipPlanner.placeAtEnd(local, localAdded, nowMin)) {
      return SkipPlanner.unchanged(day, `今天排不下了，未加入「${localAdded.title}」`);
    }
    const over: string = SkipPlanner.budgetNote(local, localAdded.title);
    if (over.length > 0) {
      return SkipPlanner.unchanged(day, over);
    }
    const ok: ReplanOutcome = {
      day: local, note: `已加入「${localAdded.title}」`, usedFallback: true, changed: true
    };
    return ok;
  }

  /** 换一站：确定性改写，保留原槽位时间与通勤（屏9「换节点不换槽」语义）。 */
  static planWithReplacement(day: TripDay, replaceId: string, newStop: Activity): ReplanOutcome {
    const index: number = SkipPlanner.indexOf(day, replaceId);
    if (index < 0) {
      return SkipPlanner.unchanged(day, '未找到要替换的站点');
    }
    if (SkipPlanner.indexOf(day, newStop.id) >= 0) {
      return SkipPlanner.unchanged(day, '这一站已经在今天的行程里');
    }
    const work: TripDay = SkipPlanner.cloneDay(day);
    const old: Activity = work.activities[index];
    const fresh: Activity = SkipPlanner.cloneActivity(newStop);
    fresh.time = old.time;
    fresh.endTime = old.endTime;
    fresh.transport = old.transport;
    // 只保留原槽时间与通勤；旧站的 note/reason 描述的是旧站内容，
    // 继续挂在替换后的博物馆上就是错误信息（真机实测「规划馆」下面还写「傍晚沿渭河散步」）。
    fresh.reason = undefined;
    work.activities[index] = fresh;
    // 换节点不换槽：时段与通勤都不变，日负载不会因为替换而增加，
    // 480min 预算闸只属于「加一站」，这里不能再拦（真机实测会误拒原本就排满的一天）。
    const ok: ReplanOutcome = {
      day: work, note: `已把「${old.title}」换成「${fresh.title}」`, usedFallback: false, changed: true
    };
    return ok;
  }

  /**
   * 对话式「我累了 / 想回酒店」：把今天所有未开始的可跳站改为空闲，
   * 保留交通/住宿/已预约/餐次这些锚点；可撤销。
   */
  static skipRemaining(day: TripDay, nowMin: number): ReplanOutcome {
    const work: TripDay = SkipPlanner.cloneDay(day);
    let count: number = 0;
    for (const a of work.activities) {
      if (a.category === ActivityCategory.TRANSPORT || a.category === ActivityCategory.HOTEL ||
        a.status === ActivityStatus.BOOKED) {
        continue;
      }
      if (SkipPlanner.isSkippedMarker(a)) {
        continue;
      }
      const start: number = DateUtils.minutesOf(a.time);
      if (start < 0 || start < nowMin) {
        continue;
      }
      const end: number = SkipPlanner.normalizedEnd(a, start);
      const title: string = a.title;
      SkipPlanner.rewriteSkipped(a, start, end, title);
      count++;
    }
    const note: string = count > 0
      ? `已提前结束今天剩余 ${count} 站，早点休息` : '今天没有可提前结束的站点';
    const outcome: ReplanOutcome = {
      day: work, note: note, usedFallback: false, changed: count > 0
    };
    return outcome;
  }

  private static unchanged(day: TripDay, note: string): ReplanOutcome {
    const outcome: ReplanOutcome = {
      day: SkipPlanner.cloneDay(day), note: note, usedFallback: false, changed: false
    };
    return outcome;
  }

  // ---- 顺延（切片 3 T3）----

  /** 顺延的移动对象：尚未开始、非交通/住宿、未预约、非跳过占位 */
  static isShiftTarget(a: Activity, nowMin: number): boolean {
    if (a.category === ActivityCategory.TRANSPORT || a.category === ActivityCategory.HOTEL) {
      return false;
    }
    if (a.status === ActivityStatus.BOOKED) {
      return false;
    }
    if (SkipPlanner.isSkippedMarker(a)) {
      return false;
    }
    const start: number = DateUtils.minutesOf(a.time);
    return start >= 0 && start >= nowMin;
  }

  /**
   * 用户确认「顺延」后的确定性排程：把未开始站点整体后移 delta 分钟，
   * 撞上锚点（预约/交通/住宿/有时刻的餐次/当前站剩余时段）就继续后移。
   * 越过 23:59 的项及其后保持原时间并追加「待调整」——宁可让用户手动改，
   * 也不把站点藏到第二天。
   */
  static shiftRemaining(day: TripDay, nowMin: number, deltaMin: number): ReplanOutcome {
    const work: TripDay = SkipPlanner.cloneDay(day);
    const delta: number = Math.floor(deltaMin);
    const targetIds: string[] = [];
    if (nowMin >= 0 && delta > 0) {
      for (const a of work.activities) {
        if (SkipPlanner.isShiftTarget(a, nowMin)) {
          targetIds.push(a.id);
        }
      }
    }
    if (targetIds.length === 0) {
      const none: ReplanOutcome = {
        day: work,
        note: '没有需要顺延的站点',
        usedFallback: false,
        changed: false
      };
      return none;
    }

    // 每站先加 delta，再按时间轴 settle 避开锚点；站间次序只前进不回退。
    const anchors: Span[] = SkipPlanner.shiftAnchors(work, nowMin);
    const placedIds: string[] = [];
    const carryIds: string[] = [];
    let cursor: number = 0;
    let overflowed: boolean = false;
    for (const id of targetIds) {
      const a: Activity | null = SkipPlanner.activityOf(work, id);
      if (a === null) {
        continue;
      }
      if (overflowed) {
        a.note = SkipPlanner.appendCarry(a.note);
        carryIds.push(id);
        continue;
      }
      const originalStart: number = DateUtils.minutesOf(a.time);
      const originalEnd: number = SkipPlanner.normalizedEnd(a, originalStart);
      const duration: number = Math.max(1, originalEnd - originalStart);
      let start: number = Math.max(originalStart + delta, cursor);
      start = SkipPlanner.settle(start, duration, anchors);
      if (start + duration > DAY_END) {
        overflowed = true;
        a.note = SkipPlanner.appendCarry(a.note);
        carryIds.push(id);
        continue;
      }
      a.time = DateUtils.hhmmOf(start);
      a.endTime = DateUtils.hhmmOf(start + duration);
      cursor = start + duration;
      placedIds.push(id);
    }

    if (!SkipPlanner.shiftValid(work, day, nowMin, placedIds, carryIds)) {
      const restored: TripDay = SkipPlanner.cloneDay(day);
      const failed: ReplanOutcome = {
        day: restored,
        note: '顺延失败，行程未改变',
        usedFallback: false,
        changed: false
      };
      return failed;
    }
    const suffix: string = carryIds.length > 0 ? '（部分站点待调整）' : '';
    // 时长统一走 DurationCn：顺延量可到 120 分钟，写成「120 分钟」不如「2小时」
    const note: string = `已顺延 ${DurationCn.text(delta)}，后续行程整体后移${suffix}`;
    const outcome: ReplanOutcome = { day: work, note: note, usedFallback: false, changed: true };
    return outcome;
  }

  /** 顺延锚点：预约/交通/住宿活动、有时刻的餐次、当前站的剩余时段 [now, end) */
  private static shiftAnchors(work: TripDay, nowMin: number): Span[] {
    const spans: Span[] = [];
    let current: Activity | null = null;
    let currentStart: number = -1;
    for (const a of work.activities) {
      const start: number = DateUtils.minutesOf(a.time);
      const anchored: boolean = a.category === ActivityCategory.TRANSPORT ||
        a.category === ActivityCategory.HOTEL || a.status === ActivityStatus.BOOKED;
      if (start < 0) {
        continue;
      }
      if (anchored) {
        const end: number = SkipPlanner.normalizedEnd(a, start);
        if (end > start) {
          spans.push({ start: start, end: end });
        }
        continue;
      }
      if (SkipPlanner.isSkippedMarker(a)) {
        continue;
      }
      if (start <= nowMin && start > currentStart) {
        current = a;
        currentStart = start;
      }
    }
    if (current !== null) {
      const end: number = SkipPlanner.normalizedEnd(current, currentStart);
      if (end > nowMin) {
        spans.push({ start: nowMin, end: end });
      }
    }
    for (const m of work.meals) {
      if (m.time === undefined) {
        continue;
      }
      const start: number = DateUtils.minutesOf(m.time);
      if (start < 0) {
        continue;
      }
      const end: number = Math.min(DAY_END, start + MEAL_ANCHOR_MIN);
      if (end > start) {
        spans.push({ start: start, end: end });
      }
    }
    return spans;
  }

  private static shiftValid(work: TripDay, original: TripDay, nowMin: number,
    placedIds: string[], carryIds: string[]): boolean {
    if (work.activities.length !== original.activities.length ||
      work.meals.length !== original.meals.length) {
      return false;
    }
    for (let i = 0; i < original.activities.length; i++) {
      if (work.activities[i].id !== original.activities[i].id) {
        return false;
      }
    }
    for (let i = 0; i < original.meals.length; i++) {
      if (work.meals[i].type !== original.meals[i].type ||
        work.meals[i].time !== original.meals[i].time) {
        return false;
      }
    }

    const anchors: Span[] = SkipPlanner.shiftAnchors(work, nowMin);
    const placed: Span[] = [];
    for (const id of placedIds) {
      const a: Activity | null = SkipPlanner.activityOf(work, id);
      if (a === null) {
        return false;
      }
      const start: number = DateUtils.minutesOf(a.time);
      const end: number = DateUtils.minutesOf(a.endTime);
      if (start < nowMin || end <= start || end > DAY_END) {
        return false;
      }
      for (const anchor of anchors) {
        if (start < anchor.end && anchor.start < end) {
          return false;
        }
      }
      placed.push({ start: start, end: end });
    }
    for (let i = 0; i < placed.length; i++) {
      for (let j = i + 1; j < placed.length; j++) {
        if (placed[i].start < placed[j].end && placed[j].start < placed[i].end) {
          return false;
        }
      }
    }

    for (const id of carryIds) {
      const now: Activity | null = SkipPlanner.activityOf(work, id);
      const was: Activity | null = SkipPlanner.activityOf(original, id);
      if (now === null || was === null || now.time !== was.time || now.endTime !== was.endTime) {
        return false;
      }
      if (now.note === undefined || now.note.indexOf(CARRY_MARK) < 0) {
        return false;
      }
    }

    for (const before of original.activities) {
      if (placedIds.indexOf(before.id) >= 0 || carryIds.indexOf(before.id) >= 0) {
        continue;
      }
      const now: Activity | null = SkipPlanner.activityOf(work, before.id);
      if (now === null || now.time !== before.time || now.endTime !== before.endTime) {
        return false;
      }
    }
    return true;
  }

  // ---- 守卫 ----

  private static accept(day: TripDay, decision: ReplanDecision, remainIds: string[]): boolean {
    if (decision.schemaVersion !== REPLAN_SCHEMA_VERSION) {
      return false;
    }
    if (decision.keep.length > REPLAN_MAX_KEEP || decision.keep.length !== remainIds.length) {
      return false;
    }
    const seen: string[] = [];
    for (const k of decision.keep) {
      if (k.id.length === 0 || remainIds.indexOf(k.id) < 0 || seen.indexOf(k.id) >= 0) {
        return false;
      }
      if (Math.floor(k.dwellMin) !== k.dwellMin ||
        k.dwellMin < REPLAN_MIN_DWELL || k.dwellMin > REPLAN_MAX_DWELL) {
        return false;
      }
      seen.push(k.id);
    }
    if (decision.freeBlocks.length > REPLAN_MAX_FREE_BLOCKS) {
      return false;
    }
    for (const b of decision.freeBlocks) {
      if (SkipPlanner.indexOf(day, b.afterId) < 0) {
        return false;
      }
      if (Math.floor(b.minutes) !== b.minutes ||
        b.minutes < REPLAN_MIN_FREE_MIN || b.minutes > REPLAN_MAX_FREE_MIN) {
        return false;
      }
    }
    return decision.note.length <= REPLAN_MAX_NOTE;
  }

  // ---- 排程 ----

  private static schedule(work: TripDay, skippedId: string, skippedStart: number,
    skippedEnd: number, nowMin: number, decision: ReplanDecision): ScheduleResult {
    const anchors: Span[] = SkipPlanner.anchors(work, skippedId, skippedStart, skippedEnd);
    const initialCursor: number = Math.max(nowMin, skippedEnd);
    const blocks: FreeState[] = [];
    for (const b of decision.freeBlocks) {
      const state: FreeState = {
        afterId: b.afterId,
        minutes: b.minutes,
        used: false,
        expired: SkipPlanner.endOf(work, b.afterId) < initialCursor
      };
      blocks.push(state);
    }

    let cursor: number = initialCursor;
    for (let i = 0; i < decision.keep.length; i++) {
      const keep: KeepStop = decision.keep[i];
      const act: Activity | null = SkipPlanner.activityOf(work, keep.id);
      if (act === null) {
        continue;
      }
      // 通勤表示「到达该站之前」；keep 第一项也加（方案 §3.3）。
      cursor += SkipPlanner.transportMin(act);
      let guard: number = 0;
      while (guard < MAX_SETTLE_LOOP) {
        guard += 1;
        const settled: number = SkipPlanner.settle(cursor, keep.dwellMin, anchors);
        let consumed: boolean = false;
        for (const b of blocks) {
          if (b.used || b.expired) {
            continue;
          }
          if (settled >= SkipPlanner.endOf(work, b.afterId)) {
            b.used = true;
            cursor = settled + b.minutes;
            consumed = true;
            break;
          }
        }
        if (!consumed) {
          cursor = settled;
          break;
        }
      }
      if (cursor + keep.dwellMin > DAY_END) {
        SkipPlanner.markCarry(work, decision.keep, i);
        const overflow: ScheduleResult = { overflow: true, overflowFrom: i };
        return overflow;
      }
      act.time = DateUtils.hhmmOf(cursor);
      act.endTime = DateUtils.hhmmOf(cursor + keep.dwellMin);
      cursor += keep.dwellMin;
    }
    const done: ScheduleResult = { overflow: false, overflowFrom: decision.keep.length };
    return done;
  }

  /** 把 t 推到不与任何锚点相交；一次只处理最远的冲突锚点，循环到稳定。 */
  private static settle(t: number, dwell: number, anchors: Span[]): number {
    let cursor: number = t;
    for (let guard = 0; guard < MAX_SETTLE_LOOP; guard++) {
      let hit: Span | null = null;
      for (const a of anchors) {
        if (cursor < a.end && a.start < cursor + dwell) {
          if (hit === null || a.end > hit.end) {
            hit = a;
          }
        }
      }
      if (hit === null) {
        return cursor;
      }
      cursor = hit.end;
    }
    return cursor;
  }

  private static anchors(work: TripDay, skippedId: string, skippedStart: number,
    skippedEnd: number): Span[] {
    const spans: Span[] = [];
    for (const a of work.activities) {
      if (a.id === skippedId) {
        continue;
      }
      const anchored: boolean = a.category === ActivityCategory.TRANSPORT ||
        a.category === ActivityCategory.HOTEL || a.status === ActivityStatus.BOOKED;
      if (!anchored) {
        continue;
      }
      const start: number = DateUtils.minutesOf(a.time);
      if (start < 0) {
        continue;
      }
      const end: number = SkipPlanner.normalizedEnd(a, start);
      if (end > start) {
        spans.push({ start: start, end: end });
      }
    }
    for (const m of work.meals) {
      if (m.time === undefined) {
        continue;
      }
      const start: number = DateUtils.minutesOf(m.time);
      if (start < 0) {
        continue;
      }
      const end: number = Math.min(DAY_END, start + MEAL_ANCHOR_MIN);
      if (end > start) {
        spans.push({ start: start, end: end });
      }
    }
    if (skippedEnd > skippedStart) {
      spans.push({ start: skippedStart, end: skippedEnd });
    }
    return spans;
  }

  // ---- 本地兜底 ----

  private static fallback(day: TripDay, skippedId: string, skippedIndex: number,
    skippedStart: number, skippedEnd: number, nowMin: number, remainIds: string[]): FallbackResult {
    const work: TripDay = SkipPlanner.cloneDay(day);
    const title: string = day.activities[skippedIndex].title;
    SkipPlanner.rewriteSkipped(work.activities[skippedIndex], skippedStart, skippedEnd, title);
    const shift: number = Math.max(0, skippedEnd - skippedStart);

    const tailIds: string[] = [];
    const originals: Activity[] = [];
    const tail: Activity[] = [];
    for (const id of remainIds) {
      const original: Activity | null = SkipPlanner.activityOf(day, id);
      const copy: Activity | null = SkipPlanner.activityOf(work, id);
      if (original === null || copy === null) {
        continue;
      }
      if (DateUtils.minutesOf(original.time) < skippedStart) {
        continue;
      }
      tailIds.push(id);
      originals.push(original);
      tail.push(copy);
    }

    const starts: number[] = [];
    const ends: number[] = [];
    for (const original of originals) {
      const start: number = DateUtils.minutesOf(original.time) + shift;
      const duration: number = Math.max(1,
        DateUtils.minutesOf(original.endTime) - DateUtils.minutesOf(original.time));
      starts.push(start);
      ends.push(start + duration);
    }

    // 与锚点冲突时整体再顺延；冲突由「整体移动」解决，绝不丢站。
    const anchors: Span[] = SkipPlanner.anchors(work, skippedId, skippedStart, skippedEnd);
    for (let guard = 0; guard < MAX_SETTLE_LOOP; guard++) {
      let needed: number = 0;
      for (let i = 0; i < starts.length; i++) {
        for (const anchor of anchors) {
          if (starts[i] < anchor.end && anchor.start < ends[i]) {
            needed = Math.max(needed, anchor.end - starts[i]);
          }
        }
      }
      if (needed <= 0) {
        break;
      }
      for (let i = 0; i < starts.length; i++) {
        starts[i] += needed;
        ends[i] += needed;
      }
    }

    let overflowFrom: number = starts.length;
    for (let i = 0; i < ends.length; i++) {
      if (ends[i] > DAY_END) {
        overflowFrom = i;
        break;
      }
    }
    for (let i = 0; i < overflowFrom; i++) {
      tail[i].time = DateUtils.hhmmOf(starts[i]);
      tail[i].endTime = DateUtils.hhmmOf(ends[i]);
    }
    for (let i = overflowFrom; i < tail.length; i++) {
      tail[i].note = SkipPlanner.appendCarry(tail[i].note);
    }

    const placedIds: string[] = tailIds.slice(0, overflowFrom);
    const carryIds: string[] = tailIds.slice(overflowFrom);
    if (!SkipPlanner.valid(work, day, skippedId, nowMin, placedIds, carryIds)) {
      // 兜底也过不了约束：整段恢复原时间并全部标待调整，绝不落一个更坏的结果。
      for (let i = 0; i < tail.length; i++) {
        tail[i].time = originals[i].time;
        tail[i].endTime = originals[i].endTime;
        tail[i].note = SkipPlanner.appendCarry(tail[i].note);
      }
      const degraded: FallbackResult = { day: work, overflow: true };
      return degraded;
    }
    const result: FallbackResult = { day: work, overflow: overflowFrom < tail.length };
    return result;
  }

  // ---- 校验 ----

  private static valid(work: TripDay, original: TripDay, skippedId: string, nowMin: number,
    placedIds: string[], carryIds: string[]): boolean {
    if (work.activities.length !== original.activities.length ||
      work.meals.length !== original.meals.length) {
      return false;
    }
    for (let i = 0; i < original.activities.length; i++) {
      if (work.activities[i].id !== original.activities[i].id) {
        return false;
      }
    }
    for (let i = 0; i < original.meals.length; i++) {
      if (work.meals[i].type !== original.meals[i].type ||
        work.meals[i].time !== original.meals[i].time) {
        return false;
      }
    }

    const skipped: Activity | null = SkipPlanner.activityOf(work, skippedId);
    const before: Activity | null = SkipPlanner.activityOf(original, skippedId);
    if (skipped === null || before === null) {
      return false;
    }
    if (skipped.category !== ActivityCategory.REST || skipped.status !== ActivityStatus.NO_NEED ||
      skipped.title !== FREE_TITLE || skipped.time !== before.time) {
      return false;
    }
    if (DateUtils.minutesOf(skipped.endTime) < DateUtils.minutesOf(skipped.time)) {
      return false;
    }

    for (const a of original.activities) {
      if (a.id === skippedId) {
        continue;
      }
      const anchored: boolean = a.category === ActivityCategory.TRANSPORT ||
        a.category === ActivityCategory.HOTEL || a.status === ActivityStatus.BOOKED;
      if (!anchored) {
        continue;
      }
      const now: Activity | null = SkipPlanner.activityOf(work, a.id);
      if (now === null || now.time !== a.time || now.endTime !== a.endTime) {
        return false;
      }
    }

    for (const id of carryIds) {
      const now: Activity | null = SkipPlanner.activityOf(work, id);
      const was: Activity | null = SkipPlanner.activityOf(original, id);
      if (now === null || was === null || now.time !== was.time || now.endTime !== was.endTime) {
        return false;
      }
      if (now.note === undefined || now.note.indexOf(CARRY_MARK) < 0) {
        return false;
      }
    }

    const anchors: Span[] = SkipPlanner.anchors(work, skippedId,
      DateUtils.minutesOf(skipped.time), DateUtils.minutesOf(skipped.endTime));
    const placed: Span[] = [];
    for (const id of placedIds) {
      const a: Activity | null = SkipPlanner.activityOf(work, id);
      if (a === null) {
        return false;
      }
      const start: number = DateUtils.minutesOf(a.time);
      const end: number = DateUtils.minutesOf(a.endTime);
      if (start < nowMin || end <= start || end > DAY_END) {
        return false;
      }
      for (const anchor of anchors) {
        if (start < anchor.end && anchor.start < end) {
          return false;
        }
      }
      placed.push({ start: start, end: end });
    }
    for (let i = 0; i < placed.length; i++) {
      for (let j = i + 1; j < placed.length; j++) {
        if (placed[i].start < placed[j].end && placed[j].start < placed[i].end) {
          return false;
        }
      }
    }
    return true;
  }

  // ---- 加站排程小工具 ----

  /** 请求里的临时时刻：保证云函数把它当成「未来剩余站点」，不参与任何真实排程。 */
  private static provisionalSlot(work: TripDay, added: Activity, nowMin: number): void {
    let maxEnd: number = nowMin;
    for (const a of work.activities) {
      if (a.id === added.id) {
        continue;
      }
      const start: number = DateUtils.minutesOf(a.time);
      if (start < 0) {
        continue;
      }
      maxEnd = Math.max(maxEnd, SkipPlanner.normalizedEnd(a, start));
    }
    const dwell: number = SkipPlanner.dwellOf(added);
    let start: number = Math.max(nowMin, maxEnd + 15);
    if (start + dwell > DAY_END) {
      start = Math.max(nowMin, DAY_END - dwell);
    }
    added.time = DateUtils.hhmmOf(start);
    added.endTime = DateUtils.hhmmOf(start + dwell);
  }

  /** 本地兜底：追加到当日最后一个节点之后；越过 23:59 就拒绝，不藏到第二天。 */
  private static placeAtEnd(work: TripDay, added: Activity, nowMin: number): boolean {
    let maxEnd: number = nowMin;
    for (const a of work.activities) {
      if (a.id === added.id) {
        continue;
      }
      const start: number = DateUtils.minutesOf(a.time);
      if (start < 0) {
        continue;
      }
      maxEnd = Math.max(maxEnd, SkipPlanner.normalizedEnd(a, start));
    }
    const dwell: number = SkipPlanner.dwellOf(added);
    const anchors: Span[] = SkipPlanner.additionAnchors(work, added.id, nowMin);
    const start: number = SkipPlanner.settle(Math.max(nowMin, maxEnd + 15), dwell, anchors);
    if (start + dwell > DAY_END) {
      return false;
    }
    added.time = DateUtils.hhmmOf(start);
    added.endTime = DateUtils.hhmmOf(start + dwell);
    return true;
  }

  private static dwellOf(a: Activity): number {
    const start: number = DateUtils.minutesOf(a.time);
    const end: number = DateUtils.minutesOf(a.endTime);
    const span: number = start >= 0 && end > start ? end - start : DEFAULT_DWELL_MIN;
    return Math.max(REPLAN_MIN_DWELL, Math.min(REPLAN_MAX_DWELL, span));
  }

  /** 加站时的锚点：预约/交通/住宿、有时刻的餐次、当前正在进行的站点剩余时段。 */
  private static additionAnchors(work: TripDay, addedId: string, nowMin: number): Span[] {
    const spans: Span[] = [];
    for (const a of work.activities) {
      if (a.id === addedId) {
        continue;
      }
      const start: number = DateUtils.minutesOf(a.time);
      if (start < 0) {
        continue;
      }
      const end: number = SkipPlanner.normalizedEnd(a, start);
      const anchored: boolean = a.category === ActivityCategory.TRANSPORT ||
        a.category === ActivityCategory.HOTEL || a.status === ActivityStatus.BOOKED;
      if (anchored) {
        if (end > start) {
          spans.push({ start: start, end: end });
        }
        continue;
      }
      if (start <= nowMin && end > nowMin) {
        spans.push({ start: nowMin, end: end });
      }
    }
    for (const m of work.meals) {
      if (m.time === undefined) {
        continue;
      }
      const start: number = DateUtils.minutesOf(m.time);
      if (start < 0) {
        continue;
      }
      const end: number = Math.min(DAY_END, start + MEAL_ANCHOR_MIN);
      if (end > start) {
        spans.push({ start: start, end: end });
      }
    }
    return spans;
  }

  /** 按云函数 keep 重排「今天还没开始的站点 + 新增站」，时间算术仍全部在端侧。 */
  private static scheduleAddition(work: TripDay, addedId: string, nowMin: number,
    decision: ReplanDecision): ScheduleResult {
    const anchors: Span[] = SkipPlanner.additionAnchors(work, addedId, nowMin);
    const blocks: FreeState[] = [];
    for (const b of decision.freeBlocks) {
      blocks.push({
        afterId: b.afterId,
        minutes: b.minutes,
        used: false,
        expired: SkipPlanner.endOf(work, b.afterId) < nowMin
      });
    }
    let cursor: number = nowMin;
    for (let i = 0; i < decision.keep.length; i++) {
      const keep: KeepStop = decision.keep[i];
      const act: Activity | null = SkipPlanner.activityOf(work, keep.id);
      if (act === null) {
        continue;
      }
      cursor += SkipPlanner.transportMin(act);
      let guard: number = 0;
      while (guard < MAX_SETTLE_LOOP) {
        guard += 1;
        const settled: number = SkipPlanner.settle(cursor, keep.dwellMin, anchors);
        let consumed: boolean = false;
        for (const b of blocks) {
          if (b.used || b.expired) {
            continue;
          }
          if (settled >= SkipPlanner.endOf(work, b.afterId)) {
            b.used = true;
            cursor = settled + b.minutes;
            consumed = true;
            break;
          }
        }
        if (!consumed) {
          cursor = settled;
          break;
        }
      }
      if (cursor + keep.dwellMin > DAY_END) {
        SkipPlanner.markCarry(work, decision.keep, i);
        const overflow: ScheduleResult = { overflow: true, overflowFrom: i };
        return overflow;
      }
      act.time = DateUtils.hhmmOf(cursor);
      act.endTime = DateUtils.hhmmOf(cursor + keep.dwellMin);
      cursor += keep.dwellMin;
    }
    const done: ScheduleResult = { overflow: false, overflowFrom: decision.keep.length };
    return done;
  }

  private static validAddition(work: TripDay, original: TripDay, addedId: string,
    nowMin: number, placedIds: string[]): boolean {
    if (work.activities.length !== original.activities.length + 1 ||
      work.meals.length !== original.meals.length) {
      return false;
    }
    if (SkipPlanner.activityOf(work, addedId) === null || placedIds.indexOf(addedId) < 0) {
      return false;
    }
    for (let i = 0; i < original.meals.length; i++) {
      if (work.meals[i].type !== original.meals[i].type ||
        work.meals[i].time !== original.meals[i].time) {
        return false;
      }
    }
    for (const a of original.activities) {
      const now: Activity | null = SkipPlanner.activityOf(work, a.id);
      if (now === null) {
        return false;
      }
      const anchored: boolean = a.category === ActivityCategory.TRANSPORT ||
        a.category === ActivityCategory.HOTEL || a.status === ActivityStatus.BOOKED;
      if ((anchored || placedIds.indexOf(a.id) < 0) &&
        (now.time !== a.time || now.endTime !== a.endTime)) {
        return false;
      }
    }
    const anchors: Span[] = SkipPlanner.additionAnchors(work, addedId, nowMin);
    const placed: Span[] = [];
    for (const id of placedIds) {
      const a: Activity | null = SkipPlanner.activityOf(work, id);
      if (a === null) {
        return false;
      }
      const start: number = DateUtils.minutesOf(a.time);
      const end: number = DateUtils.minutesOf(a.endTime);
      if (start < nowMin || end <= start || end > DAY_END) {
        return false;
      }
      for (const anchor of anchors) {
        if (start < anchor.end && anchor.start < end) {
          return false;
        }
      }
      placed.push({ start: start, end: end });
    }
    for (let i = 0; i < placed.length; i++) {
      for (let j = i + 1; j < placed.length; j++) {
        if (placed[i].start < placed[j].end && placed[j].start < placed[i].end) {
          return false;
        }
      }
    }
    return true;
  }

  /** 加站后的日负载闸：与 DayLoad 同一口径，但预算更紧（480min）。 */
  private static budgetNote(work: TripDay, title: string): string {
    const load: DayLoad = DayLoadCalc.of(work);
    if (load.minutes <= REPLAN_ADD_BUDGET_MIN) {
      return '';
    }
    return `今天活动约 ${DayLoadCalc.hours(load.minutes)}h，超过 ` +
      `${DayLoadCalc.hours(REPLAN_ADD_BUDGET_MIN)}h 上限，未加入「${title}」`;
  }

  // ---- 小工具 ----

  private static cloneActivity(a: Activity): Activity {
    const copy: Activity = {
      id: a.id,
      time: a.time,
      endTime: a.endTime,
      title: a.title,
      location: a.location,
      address: a.address,
      longitude: a.longitude,
      latitude: a.latitude,
      status: a.status,
      category: a.category
    };
    if (a.note !== undefined) {
      copy.note = a.note;
    }
    if (a.reason !== undefined) {
      copy.reason = a.reason;
    }
    if (a.advanceDays !== undefined) {
      copy.advanceDays = a.advanceDays;
    }
    if (a.transport !== undefined) {
      const t: TransportInfo = {
        mode: a.transport.mode,
        duration: a.transport.duration,
        detail: a.transport.detail
      };
      copy.transport = t;
    }
    return copy;
  }

  private static cloneMeal(m: Meal): Meal {
    const copy: Meal = {
      type: m.type,
      name: m.name,
      location: m.location,
      estimatedCost: m.estimatedCost
    };
    if (m.time !== undefined) {
      copy.time = m.time;
    }
    if (m.note !== undefined) {
      copy.note = m.note;
    }
    return copy;
  }

  /** 原地改写（方案 §3.2）：id 不变，其余字段按表清空/复位。 */
  private static rewriteSkipped(a: Activity, startMin: number, endMin: number, title: string): void {
    a.category = ActivityCategory.REST;
    a.title = FREE_TITLE;
    a.status = ActivityStatus.NO_NEED;
    a.note = `${SKIP_NOTE_PREFIX}${title}`;
    a.reason = undefined;
    a.transport = undefined;
    a.location = '';
    a.address = '';
    a.longitude = 0;
    a.latitude = 0;
    a.time = DateUtils.hhmmOf(startMin);
    a.endTime = DateUtils.hhmmOf(endMin);
  }

  private static markCarry(work: TripDay, keep: KeepStop[], fromIndex: number): void {
    for (let i = fromIndex; i < keep.length; i++) {
      const a: Activity | null = SkipPlanner.activityOf(work, keep[i].id);
      if (a !== null) {
        a.note = SkipPlanner.appendCarry(a.note);
      }
    }
  }

  private static appendCarry(note: string | undefined): string {
    if (note === undefined || note.length === 0) {
      return CARRY_MARK;
    }
    if (note.indexOf(CARRY_MARK) >= 0) {
      return note;
    }
    return `${note} · ${CARRY_MARK}`;
  }

  private static noteFor(title: string, decision: ReplanDecision | null, overflow: boolean,
    isFallback: boolean): string {
    let body: string = '后续行程已重排';
    if (isFallback) {
      body = '离线重排';
    } else if (decision !== null && decision.note.length > 0) {
      body = decision.note;
    }
    const suffix: string = overflow ? '（部分站点待调整）' : '';
    return `已跳过「${title}」，${body}${suffix}`;
  }

  private static startOf(a: Activity): number {
    const min: number = DateUtils.minutesOf(a.time);
    return min < 0 ? 0 : min;
  }

  /** endTime 缺失/不晚于 time 时取 time+60，并夹到 23:59（方案 §3.2）。 */
  private static normalizedEnd(a: Activity, startMin: number): number {
    const end: number = DateUtils.minutesOf(a.endTime);
    const candidate: number = end < 0 || end <= startMin ? startMin + DEFAULT_DWELL_MIN : end;
    return Math.min(DAY_END, candidate);
  }

  private static endOf(work: TripDay, id: string): number {
    const a: Activity | null = SkipPlanner.activityOf(work, id);
    if (a === null) {
      return -1;
    }
    const start: number = DateUtils.minutesOf(a.time);
    if (start < 0) {
      return -1;
    }
    return SkipPlanner.normalizedEnd(a, start);
  }

  private static transportMin(a: Activity): number {
    if (a.transport === undefined) {
      return 0;
    }
    return a.transport.duration > 0 ? Math.floor(a.transport.duration) : 0;
  }

  private static indexOf(day: TripDay, id: string): number {
    for (let i = 0; i < day.activities.length; i++) {
      if (day.activities[i].id === id) {
        return i;
      }
    }
    return -1;
  }

  private static activityOf(day: TripDay, id: string): Activity | null {
    const index: number = SkipPlanner.indexOf(day, id);
    return index < 0 ? null : day.activities[index];
  }
}
