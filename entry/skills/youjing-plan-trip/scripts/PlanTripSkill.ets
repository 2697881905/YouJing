/**
 * 「规划行程」Skill 入口（薄适配层）。
 *
 * 手机系统禁止后台应用拉起 UIAbility（201，START_ABILITIES_FROM_BACKGROUND 仅系统应用），
 * 所以主路径不是 startAbility，而是先把四参写入 SkillPrefill，
 * 用户打开「有径」时由 EntryAbility 消费并推屏2；startAbility 仅作 PC/2in1 的尽力尝试。
 */

import { common, scriptManager, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../../../src/main/ets/common/logger/Logger';
import { SkillPrefill, SkillPrefillRecord } from '../../../src/main/ets/data/SkillPrefill';
import { DateUtils } from '../../../src/main/ets/utils/DateUtils';
import { TripLimits } from '../../../src/main/ets/utils/TripLimits';

const TAG: string = 'Skill.PlanTrip';
const BUNDLE_NAME: string = 'com.youjing.app';
const ABILITY_NAME: string = 'EntryAbility';
const CITIES: string[] = ['北京', '上海', '广州', '深圳'];
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
  if (!DateUtils.isValidIsoDate(start)) {
    return invalid(`start ${start} is not a valid ISO date`, '请告诉我出发日期，例如 2026 年 12 月 20 日。');
  }
  // 过去日期必须在这里拒掉（2026-11-13 真机实测出的缺陷 A）：
  // 屏2 的日期选择器不允许选过去，写进预填后会被屏2 丢弃并改成今天，
  // 于是小艺说「已记下：8 月 1 日出发」、用户点开有径却看到今天——两边对不上。
  // 在入口拒掉并回 suggestion，小艺就能如实追问一个将来的日期，不会说错话。
  if (!DateUtils.isUpcoming(start, DateUtils.todayIso())) {
    return invalid(`start ${start} is in the past`,
      `出发日期 ${start} 已经过去了，请给一个今天或将来的日期。`);
  }
  const days: number = parseCount(daysRaw, DEFAULT_DAYS, TripLimits.MIN_DAYS, TripLimits.MAX_DAYS);
  if (days < 0) {
    return invalid(`days ${daysRaw} is out of range`, '天数请给 1 到 30 之间的整数。');
  }
  const people: number = parseCount(peopleRaw, DEFAULT_PEOPLE,
    TripLimits.MIN_PEOPLE, TripLimits.MAX_PEOPLE);
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
    const record: SkillPrefillRecord = {
      destination: parsed.args.destination,
      start: parsed.args.start,
      days: parsed.args.days,
      people: parsed.args.people,
      savedAt: Date.now()
    };
    if (!SkillPrefill.save(info.context, record)) {
      // 落盘失败等于什么都没做成，不能回 success；让用户进 App 手动填
      await this.report(info, PlanTripSkill.failure('ERR_INTERNAL',
        'prefill persist failed', '没能记下这次规划，请打开「有径」手动填写行程信息'));
      return;
    }

    let launched: boolean = false;
    try {
      const context: common.UIAbilityContext = info.context as common.UIAbilityContext;
      await context.startAbility(PlanTripSkill.wantOf(parsed.args));
      launched = true;
    } catch (err) {
      // 手机（非 PC/2in1）后台必然 201，这是预期路径而不是故障：
      // 参数已在 SkillPrefill，用户点开 App 后 onForeground 会消费并推屏2。
      const e: BusinessError = err as BusinessError;
      Logger.info(TAG, `startAbility 未获准，保留预填待用户打开: code=${e.code}`);
    }

    const data: Record<string, Object> = {
      'destination': parsed.args.destination,
      'startDate': parsed.args.start,
      'days': parsed.args.days,
      'people': parsed.args.people,
      'route': 'TripInput',
      'launched': launched,
      'message': PlanTripSkill.messageOf(parsed.args, launched)
    };
    const payload: Record<string, Object> = {
      'type': 'result', 'status': 'success', 'data': data
    };
    await this.report(info, { code: 0, result: payload });
  }

  private static messageOf(args: PlanArgs, launched: boolean): string {
    const parts: string[] = args.start.split('-');
    const dateText: string = `${Number(parts[1])}月${Number(parts[2])}日`;
    const summary: string = `${args.destination}，${dateText}出发，${args.days}天，${args.people}人`;
    if (launched) {
      return `已打开「有径」行程规划页：${summary}。`;
    }
    return `已记下：${summary}。打开「有径」会自动进入行程规划页并填好这些信息。`;
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
