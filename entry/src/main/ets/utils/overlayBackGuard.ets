/**
 * 页内覆盖层的「返回守卫」——与有据 `utils/overlayBackGuard.ets` 同构。
 *
 * 问题（2026-11-08 真机）：`Index.onBackPress` 把「非地图格的根页返回」改成切回「地图」，
 * 但根页上的弹层（`bindSheet`）与就地展开的法务文书是**页内 if 分支渲染的图层**，
 * 不由 Navigation 栈托管，返回键会先落到 `Index.onBackPress`——
 * 实测费用「记一笔」、我的「隐私政策」按返回都直接跳回「地图」，弹层该关的那一次被抢走。
 *
 * 解法：页面把「覆盖层开没开 + 怎么关」登记成守卫，由**壳层的返回拦截**统一消费一次。
 *
 * 约定（照有据）：
 *   · 登记是幂等的：持有页在 aboutToAppear 登记一次、aboutToDisappear 注销，
 *     不要在每次开关覆盖层时反复登记；
 *   · 回调闭包持有页面实例，必须成对注销，否则会拖住已销毁的页面；
 *   · 按页面 id 消费——TabContent 不销毁，五个根页会长期登记，全局无差别消费会关错页。
 */
type OverlayProbe = () => boolean;
type OverlayCloser = () => void;

interface OverlayBackGuard {
  id: string;
  isOpen: OverlayProbe;
  close: OverlayCloser;
}

const guards: OverlayBackGuard[] = [];

/** 费用根页：记一笔 / 分类预算两张半模态 */
export const OVERLAY_GUARD_EXPENSE_TAB: string = 'expenseTab';
/** 我的根页：隐私政策/用户协议/关于 就地展开的整页文书 */
export const OVERLAY_GUARD_MINE_TAB: string = 'mineTab';

export function registerOverlayBackGuard(id: string, isOpen: OverlayProbe, close: OverlayCloser): void {
  unregisterOverlayBackGuard(id);
  guards.push({ id: id, isOpen: isOpen, close: close });
}

export function unregisterOverlayBackGuard(id: string): void {
  for (let i: number = guards.length - 1; i >= 0; i--) {
    if (guards[i].id === id) {
      guards.splice(i, 1);
    }
  }
}

/** 该页的覆盖层开着就关掉并返回 true；没登记或没开返回 false（把返回让给下一档） */
export function consumeOverlayBackFor(id: string): boolean {
  for (let i: number = guards.length - 1; i >= 0; i--) {
    const guard: OverlayBackGuard = guards[i];
    if (guard.id !== id) {
      continue;
    }
    if (guard.isOpen()) {
      guard.close();
      return true;
    }
    return false;
  }
  return false;
}
