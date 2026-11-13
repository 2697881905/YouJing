/**
 * @kit.PerformanceAnalysisKit 的离线替身（只给 skill_check 用）。
 * Logger 只调 hilog 的四个级别，替身不输出——断言只看返回值，不看日志。
 */
export namespace hilog {
  export function debug(domain: number, tag: string, format: string, message: string): void {
  }
  export function info(domain: number, tag: string, format: string, message: string): void {
  }
  export function warn(domain: number, tag: string, format: string, message: string): void {
  }
  export function error(domain: number, tag: string, format: string, message: string): void {
  }
}
