/**
 * 手表端日志出口（与手机侧同口径：YouJing. 前缀 + %{public}s）。
 * 手表模块不引用 entry，故单独一份极薄封装。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';

export class Logger {
  private static readonly DOMAIN: number = 0x0100;
  private static readonly TAG_PREFIX: string = 'YouJing.';

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
