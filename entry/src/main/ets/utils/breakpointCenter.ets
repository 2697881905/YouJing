/**
 * 全局断点中心：一多适配的**唯一**断点源（照「有据」utils/breakpointCenter.ets 移植）。
 *
 * 关键原则：断点依据 = **应用窗口宽度（vp）**，不是机型。
 * 2in1 自由窗口随意缩放、折叠屏展开/折叠、分屏都随窗口走——
 * 官方最佳实践口径是「别识别机型，去测容器」。
 *
 * 有径此前**完全没有**这一层：全仓 grep 无 breakpoint / isWidePane / foldStatus /
 * windowSizeChange，所有布局按单台手机宽度写死。这就是「屏幕适配哪哪都是问题」的根因，
 * 本文件是补的第一块地基。
 *
 * 系统断点（窗口宽 vp）：sm(320-599) / md(600-839) / lg(840+)。
 * 宽屏判定 isWidePane = md 及以上。
 *
 * 消费方式（必须用 @StorageProp，且要在 build 里直读变量才建立绑定）：
 *   @StorageProp(KEY_CURRENT_BREAKPOINT) bp: string = 'sm';
 *   @StorageProp(KEY_IS_WIDE_PANE) isWidePane: boolean = false;
 * 不要再各自注册 windowSizeChange——监听只在这里一处。
 */

import { window, display } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Logger } from '../common/logger/Logger';

export const KEY_CURRENT_BREAKPOINT: string = 'currentBreakpoint';
export const KEY_IS_WIDE_PANE: string = 'isWidePane';
export const KEY_FOLD_STATUS: string = 'foldStatus';
/** 窗口实测宽（vp）。卡片类容器不能用 `constraintSize.maxWidth` 收窄时
 *  （它的子级全是 `width('100%')`），用它算对称内缩量——见 responsive.symmetricInsetForCap */
export const KEY_WINDOW_WIDTH_VP: string = 'windowWidthVp';

const TAG: string = 'Breakpoint';

/** md/lg 的窗口宽下限（vp）。命名而不是散在第 40 行的三元里，
 *  是为了让「每列至少多宽」这件事能被测试钉住（Responsive.test.ets） */
export const BP_MD_MIN_VP: number = 600;
export const BP_LG_MIN_VP: number = 840;

let started: boolean = false;
let density: number = 0;

export function isWideBreakpoint(bp: string): boolean {
  return bp === 'md' || bp === 'lg';
}

function applyWindowWidth(widthPx: number): void {
  const wVp: number = widthPx / (density > 0 ? density : 3.3);
  const bp: string = wVp >= BP_LG_MIN_VP ? 'lg' : (wVp >= BP_MD_MIN_VP ? 'md' : 'sm');
  AppStorage.setOrCreate<string>(KEY_CURRENT_BREAKPOINT, bp);
  AppStorage.setOrCreate<boolean>(KEY_IS_WIDE_PANE, isWideBreakpoint(bp));
  AppStorage.setOrCreate<number>(KEY_WINDOW_WIDTH_VP, Number(wVp.toFixed(1)));
  Logger.info(TAG, `窗口宽 ${wVp.toFixed(1)}vp → 断点 ${bp}`);
}

/** 应用启动时调用一次（EntryAbility.onWindowStageCreate，loadContent 之前）。幂等。 */
export function initBreakpointCenter(ctx: common.Context): void {
  if (started) {
    return;
  }
  started = true;
  // 先落确定性初值：窗口实测值异步就绪后覆盖，消费方 @StorageProp 会即时收到更新
  AppStorage.setOrCreate<string>(KEY_CURRENT_BREAKPOINT, 'sm');
  AppStorage.setOrCreate<boolean>(KEY_IS_WIDE_PANE, false);
  // 0 = 还没实测到窗口宽，消费方按"不收窄"处理
  AppStorage.setOrCreate<number>(KEY_WINDOW_WIDTH_VP, 0);
  try {
    const disp: display.Display = display.getDefaultDisplaySync();
    density = disp.densityPixels;
    AppStorage.setOrCreate<number>(KEY_FOLD_STATUS, Number(display.getFoldStatus()));
  } catch (e) {
    // display 不可用：density 兜底 3.3，断点仍可用
  }
  window.getLastWindow(ctx)
    .then((win: window.Window): void => {
      applyWindowWidth(win.getWindowProperties().windowRect.width);
      win.on('windowSizeChange', (size: window.Size): void => {
        applyWindowWidth(size.width);
      });
    })
    .catch((): void => {
      Logger.warn(TAG, 'getLastWindow 失败，断点回落到 sm');
      AppStorage.setOrCreate<string>(KEY_CURRENT_BREAKPOINT, 'sm');
      AppStorage.setOrCreate<boolean>(KEY_IS_WIDE_PANE, false);
    });
  try {
    display.on('foldStatusChange', (data: display.FoldStatus): void => {
      AppStorage.setOrCreate<number>(KEY_FOLD_STATUS, Number(data));
    });
  } catch (e) {
    // 非折叠设备不支持该事件：忽略
  }
}
