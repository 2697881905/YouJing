// 主导航的自定义转场挂钩（自「有据」Index.customNavContentTransition 抽出，行为逐字保留）。
// 抽成共享函数是因为有径是「每格自带 HdsNavigation」，挂钩要挂在**持有该栈的那层**，
// 不是宿主 Navigation；哪个页签要一镜到底就在它的 HdsNavigation 上挂这一条。
//
// ⚠ 三条前提照技能核对过，抄官方示例会连带抄进错误前提：
//  1) 官方写 `if (!from.navDestinationId || !to.navDestinationId) return undefined`，前提是
//     源页本身也是 NavDestination。有径的行程列表是 tab 根内容（navBar 位），PUSH 时
//     from.navDestinationId 为空 → 照抄会让转场整条失效（症状：只看到一张放大的卡片截图）。
//     所以这里只用 id 查表，取不到即视为未注册。
//  2) 未注册的目的地走系统默认转场（返回 undefined），不影响其它页面。
//  3) operation 只判 PUSH/POP 由 Properties.doAnimation 内部处理，第三种取值在那里落终态放行。
import { CustomTransition, AnimateCallback } from './customNavigationUtils';

export function longTakeTransitionHook(from: NavContentInfo, to: NavContentInfo,
  operation: NavigationOperation): NavigationAnimatedTransition | undefined {
  const toParam: AnimateCallback = CustomTransition.getInstance().getAnimateParam(to.navDestinationId ?? '');
  const fromParam: AnimateCallback =
    CustomTransition.getInstance().getAnimateParam(from.navDestinationId ?? '');
  if (fromParam.animation === undefined && toParam.animation === undefined) {
    return undefined;
  }
  CustomTransition.getInstance().operation = operation;
  const customAnimation: NavigationAnimatedTransition = {
    // PUSH 交 to、POP 交 from
    timeout: operation === NavigationOperation.PUSH ? toParam.timeout : fromParam.timeout,
    onTransitionEnd: (): void => {
      CustomTransition.getInstance().proxy = undefined;
    },
    transition: (transitionProxy: NavigationTransitionProxy): void => {
      CustomTransition.getInstance().proxy = transitionProxy;
      const animateParam: AnimateCallback =
        operation === NavigationOperation.PUSH ? toParam : fromParam;
      if (animateParam.animation !== undefined) {
        animateParam.animation(transitionProxy);
      } else {
        transitionProxy.finishTransition();
      }
    }
  };
  return customAnimation;
}
