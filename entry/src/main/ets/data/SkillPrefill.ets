/**
 * 小艺 Skill → App 的跨生命周期预填位（阶段 9 真机修正）。
 *
 * 为什么不是 Want：手机（非 PC/2in1）上后台应用无权拉起 UIAbility，
 * Skill 脚本里 startAbility 必报 201（START_ABILITIES_FROM_BACKGROUND 仅系统应用）。
 * 所以脚本先把四参落到这里，用户打开「有径」时由 EntryAbility 取走并推屏2；
 * 取后即删，超过两小时视为过期，避免隔天打开突然跳页。
 */

import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../common/logger/Logger';
import { DateUtils } from '../utils/DateUtils';

const TAG: string = 'Data.SkillPrefill';
const PREFS_NAME: string = 'youjing_skill_prefill';
const KEY_DESTINATION: string = 'destination';
const KEY_START: string = 'start';
const KEY_DAYS: string = 'days';
const KEY_PEOPLE: string = 'people';
const KEY_SAVED_AT: string = 'savedAt';
const MAX_AGE_MS: number = 2 * 60 * 60 * 1000;
const CLOCK_SKEW_MS: number = 5 * 60 * 1000;

export interface SkillPrefillRecord {
  destination: string;
  start: string;
  days: number;
  people: number;
  savedAt: number;
}

export class SkillPrefill {
  /** 写入一份待消费的预填；同日多次请求以后一次为准 */
  static save(context: common.Context, record: SkillPrefillRecord): boolean {
    try {
      const prefs: preferences.Preferences =
        preferences.getPreferencesSync(context, { name: PREFS_NAME });
      prefs.putSync(KEY_DESTINATION, record.destination);
      prefs.putSync(KEY_START, record.start);
      prefs.putSync(KEY_DAYS, record.days);
      prefs.putSync(KEY_PEOPLE, record.people);
      prefs.putSync(KEY_SAVED_AT, record.savedAt);
      prefs.flushSync();
      Logger.info(TAG, `已写入预填 ${record.destination} ${record.start} ${record.days}天 ${record.people}人`);
      return true;
    } catch (err) {
      Logger.error(TAG, `预填写入失败: ${(err as BusinessError).message}`);
      return false;
    }
  }

  /** 取走并清除；无记录、已过期或字段不合法都返回 null */
  static take(context: common.Context): SkillPrefillRecord | null {
    try {
      const prefs: preferences.Preferences =
        preferences.getPreferencesSync(context, { name: PREFS_NAME });
      const rawAt: preferences.ValueType = prefs.getSync(KEY_SAVED_AT, 0);
      if (typeof rawAt !== 'number' || rawAt <= 0) {
        return null;
      }
      const rawDest: preferences.ValueType = prefs.getSync(KEY_DESTINATION, '');
      const rawStart: preferences.ValueType = prefs.getSync(KEY_START, '');
      const rawDays: preferences.ValueType = prefs.getSync(KEY_DAYS, 0);
      const rawPeople: preferences.ValueType = prefs.getSync(KEY_PEOPLE, 0);
      const record: SkillPrefillRecord = {
        destination: typeof rawDest === 'string' ? rawDest : '',
        start: typeof rawStart === 'string' ? rawStart : '',
        days: typeof rawDays === 'number' ? rawDays : 0,
        people: typeof rawPeople === 'number' ? rawPeople : 0,
        savedAt: rawAt
      };
      SkillPrefill.purge(prefs);
      if (!SkillPrefill.usable(record)) {
        Logger.warn(TAG, `丢弃无效预填 dest=${record.destination} start=${record.start}`);
        return null;
      }
      Logger.info(TAG, `取出预填 ${record.destination} ${record.start} ${record.days}天 ${record.people}人`);
      return record;
    } catch (err) {
      Logger.error(TAG, `预填读取失败: ${(err as BusinessError).message}`);
      return null;
    }
  }

  static clear(context: common.Context): void {
    try {
      SkillPrefill.purge(preferences.getPreferencesSync(context, { name: PREFS_NAME }));
    } catch (err) {
      Logger.error(TAG, `预填清除失败: ${(err as BusinessError).message}`);
    }
  }

  private static purge(prefs: preferences.Preferences): void {
    prefs.deleteSync(KEY_DESTINATION);
    prefs.deleteSync(KEY_START);
    prefs.deleteSync(KEY_DAYS);
    prefs.deleteSync(KEY_PEOPLE);
    prefs.deleteSync(KEY_SAVED_AT);
    prefs.flushSync();
  }

  private static usable(record: SkillPrefillRecord): boolean {
    if (record.destination.length === 0 || !DateUtils.isValidIsoDate(record.start)) {
      return false;
    }
    if (!Number.isInteger(record.days) || record.days < 1 || record.days > 30) {
      return false;
    }
    if (!Number.isInteger(record.people) || record.people < 1 || record.people > 30) {
      return false;
    }
    const now: number = Date.now();
    return record.savedAt <= now + CLOCK_SKEW_MS && now - record.savedAt <= MAX_AGE_MS;
  }
}
