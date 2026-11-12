/**
 * 重排/意图提示词 · 端侧直连版（搬自 cloud/replanDay/index.js 的 promptFor / intentPromptFor）。
 *
 * 云函数未部署时，ReplanClient 用本件把 ReplanRequest 转成 DirectChat messages，
 * 端侧直连真 LLM 做决策；输出契约与云函数一致，仍交 ReplanParser.parseDecision 守卫。
 * 只做决策提示，不做时间算术（具体时刻由 SkipPlanner 计算）；任何失败回 null 走本地兜底。
 */

import { DateUtils } from '../utils/DateUtils';
import { ActivityCategory, ActivityStatus } from '../model/Trip';
import { ReplanRequest, ReplanRequestActivity } from '../model/Replan';
import { DirectChatMessage } from './DirectChat';

interface PromptActivity {
  id: string;
  title: string;
  time: string;
  endTime: string;
  category: string;
}

interface PromptIntentActivity {
  id: string;
  title: string;
  time: string;
  endTime: string;
  category: string;
  status: string;
}

interface PromptAnchor {
  label: string;
  start: string;
  end: string;
}

interface PromptTarget {
  action: string;
  id: string;
  title: string;
  time: string;
  endTime: string;
}

interface ReplanUserPayload {
  now: string;
  date: string;
  target: PromptTarget;
  remaining: PromptActivity[];
  anchors: PromptAnchor[];
  meals: Object[];
}

interface IntentUserPayload {
  now: string;
  date: string;
  intentText: string;
  activities: PromptIntentActivity[];
  candidates: ReplanRequestActivity[];
}

function isAnchor(category: ActivityCategory): boolean {
  return category === ActivityCategory.TRANSPORT || category === ActivityCategory.HOTEL;
}

function hhmmOf(minutes: number): string {
  const clamped: number = Math.max(0, Math.min(1439, Math.round(minutes)));
  const h: string = `${Math.floor(clamped / 60)}`;
  const m: string = `${clamped % 60}`;
  return `${h.length < 2 ? `0${h}` : h}:${m.length < 2 ? `0${m}` : m}`;
}

export class ReplanPromptBuilder {
  /** 是否需要 LLM 决策：换节点端侧确定性改写、剩余为空都不必问模型 */
  static needsLlm(request: ReplanRequest): boolean {
    if (request.replaceStopId !== undefined && request.replaceStopId.length > 0) {
      return false;
    }
    const hasIntent: boolean = request.intentText !== undefined && request.intentText.trim().length > 0;
    if (hasIntent) {
      return true;
    }
    return ReplanPromptBuilder.remainingOf(request).length > 0;
  }

  static messages(request: ReplanRequest): DirectChatMessage[] {
    const hasIntent: boolean = request.intentText !== undefined && request.intentText.trim().length > 0;
    if (hasIntent) {
      return ReplanPromptBuilder.intentMessages(request);
    }
    return ReplanPromptBuilder.replanMessages(request);
  }

  /** 剩余可重排站点：排除被跳过站、锚点（交通/住宿）与已预约，只留今天还没开始的 */
  private static remainingOf(request: ReplanRequest): ReplanRequestActivity[] {
    const nowMin: number = DateUtils.minutesOf(request.now);
    const skippedId: string = request.skippedId ?? '';
    const list: ReplanRequestActivity[] = request.day.activities.filter((a: ReplanRequestActivity): boolean => {
      if (skippedId.length > 0 && a.id === skippedId) {
        return false;
      }
      return !isAnchor(a.category) && a.status !== ActivityStatus.BOOKED &&
        DateUtils.minutesOf(a.time) >= nowMin;
    });
    list.sort((x: ReplanRequestActivity, y: ReplanRequestActivity): number =>
      DateUtils.minutesOf(x.time) - DateUtils.minutesOf(y.time));
    return list;
  }

  /** 固定锚点段：交通/住宿/已预约 + 有时刻的餐次 + 被跳过站腾出的空闲段 */
  private static anchorsOf(request: ReplanRequest): PromptAnchor[] {
    const skippedId: string = request.skippedId ?? '';
    const addStopId: string = request.addStopId ?? '';
    const spans: PromptAnchor[] = [];
    let skipped: ReplanRequestActivity | null = null;
    for (const a of request.day.activities) {
      if (skippedId.length > 0 && a.id === skippedId) {
        skipped = a;
        continue;
      }
      if (addStopId.length > 0 && a.id === addStopId) {
        continue;
      }
      if (!isAnchor(a.category) && a.status !== ActivityStatus.BOOKED) {
        continue;
      }
      const span: PromptAnchor = { label: a.title, start: a.time, end: a.endTime };
      spans.push(span);
    }
    for (const m of request.day.meals) {
      if (m.time === undefined || m.time.length === 0) {
        continue;
      }
      const start: number = DateUtils.minutesOf(m.time);
      const span: PromptAnchor = { label: `餐次 ${m.type}`, start: m.time, end: hhmmOf(start + 60) };
      spans.push(span);
    }
    if (skipped !== null) {
      const span: PromptAnchor = { label: '本次空闲段', start: skipped.time, end: skipped.endTime };
      spans.push(span);
    }
    return spans;
  }

  private static replanMessages(request: ReplanRequest): DirectChatMessage[] {
    const isAdd: boolean = request.addStopId !== undefined && request.addStopId.length > 0;
    const targetId: string = isAdd ? (request.addStopId ?? '') : (request.skippedId ?? '');
    const target: ReplanRequestActivity | undefined =
      request.day.activities.find((a: ReplanRequestActivity): boolean => a.id === targetId);
    const remaining: ReplanRequestActivity[] = ReplanPromptBuilder.remainingOf(request);
    const system: string = [
      isAdd
        ? '你是有径 App 的行程重排助手。用户在当日行程中新增了一站，需要你对剩余站点（含新增站）重新排序并给出停留时长。'
        : '你是有径 App 的行程重排助手。用户放弃了下一站，需要你对当日剩余站点重新排序并给出停留时长。',
      '你只做决策，不做时间算术：不要输出任何具体开始/结束时刻。',
      '必须遵守：',
      '1. keep 必须恰好包含 remaining 里的每个 id 一次，不得新增、遗漏或重复；',
      '2. 每个 dwellMin 是 15–240 的整数分钟；',
      '3. freeBlocks 最多 3 块，afterId 必须是 activities 里已存在的 id，minutes 是 15–480 的整数；',
      '4. note 不超过 200 字，给用户一句中文说明；',
      '5. 只输出 JSON，不要 Markdown 围栏或解释。',
      '输出格式：{"schemaVersion":1,"keep":[{"id":"...","dwellMin":60}],"freeBlocks":[],"note":"..."}'
    ].join('\n');
    const remainingPayload: PromptActivity[] = remaining.map((a: ReplanRequestActivity): PromptActivity => {
      const p: PromptActivity = { id: a.id, title: a.title, time: a.time, endTime: a.endTime, category: a.category };
      return p;
    });
    const targetPayload: PromptTarget = {
      action: isAdd ? 'add' : 'skip',
      id: target !== undefined ? target.id : '',
      title: target !== undefined ? target.title : '',
      time: target !== undefined ? target.time : '',
      endTime: target !== undefined ? target.endTime : ''
    };
    const mealsPayload: Object[] = request.day.meals.map((m: Object): Object => m);
    const payload: ReplanUserPayload = {
      now: request.now,
      date: request.day.date,
      target: targetPayload,
      remaining: remainingPayload,
      anchors: ReplanPromptBuilder.anchorsOf(request),
      meals: mealsPayload
    };
    const sysMsg: DirectChatMessage = { role: 'system', content: system };
    const userMsg: DirectChatMessage = { role: 'user', content: JSON.stringify(payload) };
    return [sysMsg, userMsg];
  }

  private static intentMessages(request: ReplanRequest): DirectChatMessage[] {
    const nowMin: number = DateUtils.minutesOf(request.now);
    const future: ReplanRequestActivity[] = request.day.activities.filter((a: ReplanRequestActivity): boolean =>
      DateUtils.minutesOf(a.time) >= nowMin);
    const system: string = [
      '你是有径 App 的行程助手。把用户的一句自然语言意愿映射成四种动作之一。',
      '动作含义：',
      '- skip：跳过某一站；skipRemaining=true 表示把今天后续未开始的站一并结束；',
      '- shift：把今天后续行程整体顺延 shiftMinutes 分钟（15–240）；',
      '- add：新增一站（端侧会打开选点面板，newStopId 可给推荐候选）；',
      '- replace：把某一站换成 candidates 里的另一站。',
      '必须遵守：',
      '1. 只输出 JSON：{"action":"skip|shift|add|replace","targetId":"...","newStopId":"...","skipRemaining":false,"note":"..."}；只有 shift 动作才加 "shiftMinutes":30（15–240 整数），其它动作一律不要输出 shiftMinutes 字段；',
      '2. skip/replace 必须给 targetId，且必须是 activities 里已存在的 id；',
      '3. replace 的 newStopId 必须来自 candidates；add 可省略 targetId；',
      '4. 不得编造 activities/candidates 里没有的站点或事实；',
      '5. note 不超过 100 字，用中文复述你理解到的意图；',
      '6. 「我累了/想回酒店/不想逛了/结束今天」这类意愿映射为 skip 且 skipRemaining=true。'
    ].join('\n');
    const activitiesPayload: PromptIntentActivity[] = future.map((a: ReplanRequestActivity): PromptIntentActivity => {
      const p: PromptIntentActivity = {
        id: a.id, title: a.title, time: a.time, endTime: a.endTime, category: a.category, status: a.status
      };
      return p;
    });
    const payload: IntentUserPayload = {
      now: request.now,
      date: request.day.date,
      intentText: (request.intentText ?? '').trim(),
      activities: activitiesPayload,
      candidates: request.candidates ?? []
    };
    const sysMsg: DirectChatMessage = { role: 'system', content: system };
    const userMsg: DirectChatMessage = { role: 'user', content: JSON.stringify(payload) };
    return [sysMsg, userMsg];
  }
}