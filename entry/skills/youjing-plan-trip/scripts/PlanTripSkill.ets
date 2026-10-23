/**
 * 「规划行程」Skill 入口（薄适配层）。
 * 只做参数校验与拉起 App；日期/人数/天数的落盘与导航复用 EntryAbility.applyWant，
 * 不在这里写第二套预填逻辑。
 */

import { common, scriptManager, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../../../src/main/ets/common/logger/Logger';

const TAG: string = 'Skill.PlanTrip';
const BUNDLE_NAME: string = 'com.youjing.app';
const ABILITY_NAME: string = 'EntryAbility';
const CITIES: string[] = ['北京', '上海', '广州', '深圳'];
const ISO_DATE: RegExp = /^\d{4}-\d{2}-\d{2}$/;
const DEFAULT_DAYS: number = 3;
const DEFAULT_PEOPLE: number = 2;

interface PlanArgs {
  destination: string;
  start: string;
  days: number;
  people: number;
}

interface ParsedArgs {
  valid: boolean;
  args: PlanArgs;
  errMsg: string;
  suggestion: string;
}

function isIsoDate(text: string): boolean {
  if (!ISO_DATE.test(text)) {
    return false;
  }
  const parts: string[] = text.split('-');
  const year: number = Number(parts[0]);
  const month: number = Number(parts[1]);
  const day: number = Number(parts[2]);
  const date: Date = new Date(year, month - 1, day);
  return date.getFullYear() === year && date.getMonth() === month - 1 && date.getDate() === day;
}

/** 空串取默认值；非法或越界返回 -1 */
function parseCount(text: string, fallback: number, min: number, max: number): number {
  if (text.length === 0) {
    return fallback;
  }
  const value: number = Number(text);
  if (!Number.isInteger(value) || value < min || value > max) {
    return -1;
  }
  return value;
}

function invalid(errMsg: string, suggestion: string): ParsedArgs {
  const args: PlanArgs = { destination: '', start: '', days: DEFAULT_DAYS, people: DEFAULT_PEOPLE };
  const parsed: ParsedArgs = { valid: false, args: args, errMsg: errMsg, suggestion: suggestion };
  return parsed;
}

function parseArgs(argv: string[]): ParsedArgs {
  const destination: string = argv.length > 0 ? argv[0].trim() : '';
  const start: string = argv.length > 1 ? argv[1].trim() : '';
  const daysRaw: string = argv.length > 2 ? argv[2].trim() : '';
  const peopleRaw: string = argv.length > 3 ? argv[3].trim() : '';

  if (destination.length === 0) {
    return invalid('destination is empty', '你想去哪个城市？目前支持北京、上海、广州、深圳。');
  }
  if (CITIES.indexOf(destination) < 0) {
    return invalid(`destination ${destination} is not supported`,
      '目前只支持北京、上海、广州、深圳，你想去哪一个？');
  }
  if (!isIsoDate(start)) {
    return invalid(`start ${start} is not a valid ISO date`, '请告诉我出发日期，例如 2026 年 8 月 1 日。');
  }
  const days: number = parseCount(daysRaw, DEFAULT_DAYS, 1, 30);
  if (days < 0) {
    return invalid(`days ${daysRaw} is out of range`, '天数请给 1 到 30 之间的整数。');
  }
  const people: number = parseCount(peopleRaw, DEFAULT_PEOPLE, 1, 30);
  if (people < 0) {
    return invalid(`people ${peopleRaw} is out of range`, '同行人数请给 1 到 30 之间的整数。');
  }
  const args: PlanArgs = {
    destination: destination, start: start, days: days, people: people
  };
  const parsed: ParsedArgs = { valid: true, args: args, errMsg: '', suggestion: '' };
  return parsed;
}

export default class PlanTripSkill {
  public async planTrip(info: scriptManager.ArkTSScriptInfo, ...argv: string[]): Promise<void> {
    const parsed: ParsedArgs = parseArgs(argv);
    if (!parsed.valid) {
      await this.report(info,
        PlanTripSkill.failure('ERR_INVALID_PARAMS', parsed.errMsg, parsed.suggestion));
      return;
    }
    try {
      const context: common.UIAbilityContext = info.context as common.UIAbilityContext;
      await context.startAbility(PlanTripSkill.wantOf(parsed.args));
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      await this.report(info, PlanTripSkill.failure('ERR_INTERNAL',
        `startAbility failed: ${e.code} ${e.message}`, '打开有径失败了，请手动打开应用再试'));
      return;
    }
    const data: Record<string, Object> = {
      'destination': parsed.args.destination,
      'startDate': parsed.args.start,
      'days': parsed.args.days,
      'people': parsed.args.people,
      'route': 'TripInput',
      'launched': true
    };
    const payload: Record<string, Object> = {
      'type': 'result', 'status': 'success', 'data': data
    };
    await this.report(info, { code: 0, result: payload });
  }

  private static wantOf(args: PlanArgs): Want {
    const parameters: Record<string, Object> = {
      'route': 'TripInput',
      'destination': args.destination,
      'start': args.start,
      'days': args.days,
      'people': args.people
    };
    const want: Want = {
      bundleName: BUNDLE_NAME,
      abilityName: ABILITY_NAME,
      parameters: parameters
    };
    return want;
  }

  private static failure(errCode: string, errMsg: string,
    suggestion: string): scriptManager.ExecuteResult {
    const payload: Record<string, Object> = {
      'type': 'result', 'status': 'failed',
      'errCode': errCode, 'errMsg': errMsg, 'suggestion': suggestion
    };
    const result: scriptManager.ExecuteResult = { code: -1, result: payload };
    return result;
  }

  private async report(info: scriptManager.ArkTSScriptInfo,
    result: scriptManager.ExecuteResult): Promise<void> {
    try {
      await scriptManager.completeArkTSScriptInApp(info.context, info.requestCode, result);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.error(TAG, `completeArkTSScriptInApp failed, code: ${e.code}, message: ${e.message}`);
    }
  }
}
