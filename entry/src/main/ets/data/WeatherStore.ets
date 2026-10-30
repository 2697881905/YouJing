/**
 * 天气取数与缓存（切片 3 T1）。
 *
 * 只把「当日首站坐标四舍五入到 0.1°（约 11km）」发给 Open-Meteo：
 * 天气不需要精确位置，也不该把实时定位发给第三方。
 * 内存 + preferences 双层缓存，30 分钟内不重复请求——屏15 每次打卡都会 reload。
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Logger } from '../common/logger/Logger';
import { WeatherClient } from '../common/weather/WeatherClient';
import { WeatherParser } from '../common/weather/WeatherParser';
import { WeatherDay } from '../model/Weather';
import { TripDay } from '../model/Trip';
import { DateUtils } from '../utils/DateUtils';
import { Geo } from '../utils/Geo';

const TAG: string = 'Weather.Store';
const STORE_NAME: string = 'weather';
const KEY_CACHE: string = 'weatherCache';
const TTL_MS: number = 30 * 60 * 1000;

interface WeatherTarget {
  latitude: number;
  longitude: number;
}

interface MemoryEntry {
  key: string;
  at: number;
  day: WeatherDay;
}

interface CacheEntry {
  key: string;
  at: number;
  text: string;
}

export class WeatherStore {
  private static memory: MemoryEntry | null = null;
  private static prefs: preferences.Preferences | null = null;
  private static prefsReady: boolean = false;

  /** 当日天气；没有坐标/失败/解析不过都返回 null（界面不出天气行） */
  static async load(context: common.Context, day: TripDay): Promise<WeatherDay | null> {
    const target: WeatherTarget | null = WeatherStore.targetOf(day);
    if (target === null) {
      return null;
    }
    const today: string = DateUtils.todayIso();
    const key: string = `${target.latitude.toFixed(1)},${target.longitude.toFixed(1)},${today}`;
    const now: number = Date.now();
    const mem: MemoryEntry | null = WeatherStore.memory;
    if (mem !== null && mem.key === key && now - mem.at < TTL_MS) {
      return mem.day;
    }
    const prefs: preferences.Preferences | null = await WeatherStore.ensure(context);
    const cached: WeatherDay | null = WeatherStore.readCache(prefs, key, today, now);
    if (cached !== null) {
      const entry: MemoryEntry = { key: key, at: now, day: cached };
      WeatherStore.memory = entry;
      return cached;
    }
    const text: string | null = await WeatherClient.fetch(target.latitude, target.longitude);
    if (text === null) {
      return null;
    }
    try {
      const parsed: WeatherDay = WeatherParser.parse(text, today);
      const entry: MemoryEntry = { key: key, at: now, day: parsed };
      WeatherStore.memory = entry;
      WeatherStore.writeCache(prefs, key, now, text);
      return parsed;
    } catch (err) {
      Logger.warn(TAG, `天气解析失败: ${(err as Error).message}`);
      return null;
    }
  }

  /** 当日第一个带可用坐标的活动；餐次没有坐标，不够用 */
  private static targetOf(day: TripDay): WeatherTarget | null {
    for (const a of day.activities) {
      if (!Geo.usable(a.latitude, a.longitude)) {
        continue;
      }
      const target: WeatherTarget = { latitude: a.latitude, longitude: a.longitude };
      return target;
    }
    return null;
  }

  private static async ensure(context: common.Context): Promise<preferences.Preferences | null> {
    if (WeatherStore.prefsReady) {
      return WeatherStore.prefs;
    }
    WeatherStore.prefsReady = true;
    try {
      WeatherStore.prefs = await preferences.getPreferences(context, STORE_NAME);
    } catch (err) {
      Logger.warn(TAG, `天气缓存偏好不可用: ${(err as Error).message}`);
      WeatherStore.prefs = null;
    }
    return WeatherStore.prefs;
  }

  private static readCache(prefs: preferences.Preferences | null, key: string,
    today: string, now: number): WeatherDay | null {
    if (prefs === null) {
      return null;
    }
    try {
      const raw: preferences.ValueType = prefs.getSync(KEY_CACHE, '');
      if (typeof raw !== 'string' || (raw as string).length === 0) {
        return null;
      }
      const parsed: Object = JSON.parse(raw as string) as Object;
      if (typeof parsed !== 'object' || parsed === null) {
        return null;
      }
      const obj: Record<string, Object> = parsed as Record<string, Object>;
      const cachedKey: Object | undefined = obj['key'];
      const at: Object | undefined = obj['at'];
      const text: Object | undefined = obj['text'];
      if (typeof cachedKey !== 'string' || (cachedKey as string) !== key) {
        return null;
      }
      if (typeof at !== 'number' || now - (at as number) >= TTL_MS) {
        return null;
      }
      if (typeof text !== 'string' || (text as string).length === 0) {
        return null;
      }
      return WeatherParser.parse(text as string, today);
    } catch (err) {
      Logger.warn(TAG, `天气缓存读取失败: ${(err as Error).message}`);
      return null;
    }
  }

  private static writeCache(prefs: preferences.Preferences | null, key: string,
    at: number, text: string): void {
    if (prefs === null) {
      return;
    }
    try {
      const entry: CacheEntry = { key: key, at: at, text: text };
      prefs.putSync(KEY_CACHE, JSON.stringify(entry));
      prefs.flush().catch((err: Error): void => {
        Logger.warn(TAG, `天气缓存写入失败: ${err.message}`);
      });
    } catch (err) {
      Logger.warn(TAG, `天气缓存写入异常: ${(err as Error).message}`);
    }
  }
}
