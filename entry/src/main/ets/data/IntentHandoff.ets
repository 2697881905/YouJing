/**
 * 意图执行器 → UIAbility 的交接位（阶段 9 小艺接入）。
 *
 * 为什么要有这一层：InsightIntentExecutor 的 onExecuteInUIAbilityForegroundMode 可能在
 * 页面尚未 load 完时被调用（冷启动顺序 onCreate → onWindowStageCreate → 执行意图 → onForeground），
 * 此时直接 APP_NAV.pushPath 会因为没有挂载的 Navigation 而丢路由。
 * 故执行器只写这一格，EntryAbility 在 bootstrap（页面加载完成）与 onForeground 两处消费，
 * 消费即清空，重复调用无副作用。
 */

export class IntentHandoff {
  static pendingRoute: string = '';
  static pendingParam: string = '';

  static set(route: string, param: string): void {
    IntentHandoff.pendingRoute = route;
    IntentHandoff.pendingParam = param;
  }

  /** 有交接内容时取出并清空 */
  static take(): string {
    const route: string = IntentHandoff.pendingRoute;
    IntentHandoff.pendingRoute = '';
    IntentHandoff.pendingParam = '';
    return route;
  }

  static hasPending(): boolean {
    return IntentHandoff.pendingRoute.length > 0;
  }
}
