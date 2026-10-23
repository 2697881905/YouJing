/**
 * 「规划行程」意图执行器（开发文档 §6 阶段 9：小艺 Skill 语音唤起并预填参数）。
 *
 * 声明见 resources/base/profile/insight_intent.json（schema 按本机 SDK 的
 * toolchains/modulecheck/insightIntent.json 核对）。执行模式 foreground：
 * 行程规划必须有界面，不做后台静默执行。
 *
 * 参数口径与 hdc 通道完全一致（destination/start/end/days/people/route），
 * 平台侧槽位照 Docs/小艺Skill接入清单.md §C 填即可；非法日期忽略，不覆盖已有草稿。
 */

import { insightIntent, InsightIntentExecutor } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { PlanDraft } from '../data/PlanDraft';
import { IntentHandoff } from '../data/IntentHandoff';
import { TripBasicInput } from '../model/PlanParams';
import { DateUtils } from '../utils/DateUtils';
import { Logger } from '../common/logger/Logger';

const TAG: string = 'Insight.PlanTrip';

function strOf(param: Record<string, Object>, key: string): string {
  const raw: Object | undefined = param[key];
  return typeof raw === 'string' ? raw as string : '';
}

function numOf(param: Record<string, Object>, key: string): number {
  const raw: Object | undefined = param[key];
  if (typeof raw === 'number') {
    return raw as number;
  }
  if (typeof raw === 'string') {
    const parsed: number = Number(raw as string);
    return Number.isNaN(parsed) ? 0 : parsed;
  }
  return 0;
}

export default class PlanTripExecutor extends InsightIntentExecutor {
  onExecuteInUIAbilityForegroundMode(name: string, param: Record<string, Object>,
    pageLoader: window.WindowStage): insightIntent.ExecuteResult {
    const draft: PlanDraft = PlanDraft.get();
    const basic: TripBasicInput = {
      destination: draft.basic.destination, startDate: draft.basic.startDate,
      endDate: draft.basic.endDate, people: draft.basic.people, budget: draft.basic.budget
    };
    const dest: string = strOf(param, 'destination');
    if (dest.length > 0) {
      basic.destination = dest;
    }
    const start: string = strOf(param, 'start');
    if (DateUtils.isValidIsoDate(start)) {
      basic.startDate = start;
    }
    const end: string = strOf(param, 'end');
    if (DateUtils.isValidIsoDate(end)) {
      basic.endDate = end;
    }
    const days: number = numOf(param, 'days');
    if (days > 1) {
      const computed: string = DateUtils.addDays(basic.startDate, days - 1);
      if (computed.length > 0) {
        basic.endDate = computed;
      }
    }
    const people: number = numOf(param, 'people');
    if (people > 0) {
      basic.people = people;
    }
    draft.basic = basic;

    const route: string = strOf(param, 'route');
    IntentHandoff.set(route.length > 0 ? route : 'TripInput', '');
    Logger.info(TAG, `意图 ${name} 预填 ${basic.destination} ${basic.startDate}→${basic.endDate} ${basic.people}人`);

    const output: Record<string, Object> = {
      'accepted': true,
      'destination': basic.destination
    };
    const result: insightIntent.ExecuteResult = { code: 0, result: output };
    return result;
  }
}
