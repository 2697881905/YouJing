/**
 * 全工程统一日志出口 · 基于 hilog 封装。
 *
 * 纪律：禁止直接调用 console.log / console.error（P6 由 lint 规则固化）；
 * tag 按模块命名并传入本类（如 'Data.TripDao'），输出统一带 YouJing. 前缀，
 * 设备端可用 hilog 过滤 "YouJing." 抓取全部应用日志。
 * debug 级别仅在 BuildConfig.IS_DEBUG 为 true 时输出。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { BuildConfig } from '../constants/BuildConfig';

export class Logger {
  private static readonly DOMAIN: number = 0x0100;
  private static readonly TAG_PREFIX: string = 'YouJing.';

  static debug(tag: string, message: string): void {
    if (!BuildConfig.IS_DEBUG) {
      return;
    }
    hilog.debug(Logger.DOMAIN, Logger.TAG_PREFIX + tag, '%{public}s', message);
  }

  static info(tag: string, message: string): void {
    hilog.info(Logger.DOMAIN, Logger.TAG_PREFIX + tag, '%{public}s', message);
  }

  static warn(tag: string, message: string): void {
    hilog.warn(Logger.DOMAIN, Logger.TAG_PREFIX + tag, '%{public}s', message);
  }

  static error(tag: string, message: string): void {
    hilog.error(Logger.DOMAIN, Logger.TAG_PREFIX + tag, '%{public}s', message);
  }
}
