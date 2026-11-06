/**
 * 系统导航方式检测 + 底部避让量发布（胶水层；判定数学在 `navInset.ets`，那里可进 hypium）。
 *
 * 两层信号（照搬有据，两条都是真机实测换来的）：
 *  1) 权威信号：settings 的 USER_PROPERTY 域键 `float_navigation_info`，JSON 形如
 *     { showType, region }：showType=0 三键已显示（region[3] 是三键栏真实高度 px）、
 *     =1 悬浮球、=-1 未显示三键（全面屏手势/导航条）。读 USER_PROPERTY 不需要权限。
 *  2) 兜底信号：settings 键缺失（模拟器 / 部分云手机 / 非华为 ROM）时，用 avoidArea 的
 *     高度 + 「避让矩形是否横贯整屏」联合判别。
 *
 * 响应式约定（有据文件头写明的踩坑）：消费方必须 `@StorageLink(BOTTOM_NAV_INSET_KEY)`
 * **并在 build 属性里直接读该变量**——只挂 link 不进 build，ArkUI 不建立更新绑定，刷新全是空操作。
 */
import settings from '@ohos.settings';
import display from '@ohos.display';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';
import { Logger } from '../common/logger/Logger';
import {
  NAV_MODE_GESTURE, NAV_MODE_THREE_BUTTON, NAV_MODE_FLOATING_BALL,
  isThreeButton, computeNavInset, computeBarInset,
  bottomAvoidHeightVp, bottomAvoidRectWidthVp
} from './navInset';

const TAG: string = 'Ui.NavMode';
const FLOAT_NAVIGATION_INFO_KEY: string = 'float_navigation_info';

export const NAV_MODE_KEY: string = 'navMode';
export const NAV_BUTTON_BAR_HEIGHT_KEY: string = 'navButtonBarHeight';
export const BOTTOM_NAV_INSET_KEY: string = 'bottomNavInsetVp';
export const BOTTOM_BAR_INSET_KEY: string = 'bottomBarInsetVp';
export const NAV_BAR_SPANS_WIDTH_KEY: string = 'navBarSpansWidth';
/** 兜底判据的三个输入（由 EntryAbility 在 avoidArea 变化时灌入） */
const NAV_BAR_HEIGHT_KEY: string = 'navBarHeight';
const NAV_BAR_RECT_WIDTH_KEY: string = 'navBarRectWidthVp';
const NAV_WINDOW_WIDTH_KEY: string = 'navWindowWidthVp';
/** 三键栏高之外的呼吸量，与 navInset 同一把尺 */
const INSET_EXTRA_VP: number = 1;

function num(key: string): number {
  return AppStorage.get<number>(key) ?? 0;
}

export function isThreeButtonNav(): boolean {
  return (AppStorage.get<string>(NAV_MODE_KEY) ?? NAV_MODE_GESTURE) === NAV_MODE_THREE_BUTTON;
}

/** 兜底链路的入口：EntryAbility 读到 avoidArea 后把三个物理量交进来 */
export function reportBottomAvoid(heightVp: number, bottomRectWidthVp: number, windowWidthVp: number): void {
  AppStorage.setOrCreate(NAV_BAR_HEIGHT_KEY, heightVp);
  AppStorage.setOrCreate(NAV_BAR_RECT_WIDTH_KEY, bottomRectWidthVp);
  AppStorage.setOrCreate(NAV_WINDOW_WIDTH_KEY, windowWidthVp);
  AppStorage.setOrCreate(NAV_BAR_SPANS_WIDTH_KEY,
    isThreeButton(heightVp, bottomRectWidthVp, windowWidthVp) ? 1 : 0);
  refreshBottomNavInset();
}

/** 用当前缓存的三个物理量重算并发布避让量（settings 信号缺失时的唯一路径） */
export function refreshBottomNavInset(): void {
  const h: number = num(NAV_BAR_HEIGHT_KEY);
  const w: number = num(NAV_BAR_RECT_WIDTH_KEY);
  const win: number = num(NAV_WINDOW_WIDTH_KEY);
  AppStorage.setOrCreate(BOTTOM_NAV_INSET_KEY, computeNavInset(h, w, win));
  AppStorage.setOrCreate(BOTTOM_BAR_INSET_KEY, computeBarInset(h, w, win));
}

/** settings 权威信号：showType 0=三键（region[3] 给真实栏高 px）/ 1=悬浮球 / -1=手势 */
export function refreshNavMode(context: common.Context): void {
  let raw: string = '';
  try {
    raw = settings.getValueSync(context, FLOAT_NAVIGATION_INFO_KEY, '', settings.domainName.USER_PROPERTY);
  } catch (err) {
    Logger.warn(TAG, `读 float_navigation_info 失败，走 avoidArea 兜底: ${(err as Error).message}`);
    return;
  }
  if (raw.length === 0) {
    Logger.info(TAG, 'float_navigation_info 为空，保持 avoidArea 兜底判定');
    return;
  }
  try {
    const info: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
    const showType: number = Number(info['showType'] ?? -1);
    const density: number = display.getDefaultDisplaySync().densityPixels;
    if (showType === 0) {
      const region: Object | undefined = info['region'];
      let barHeightVp: number = 0;
      if (Array.isArray(region) && region.length >= 4 && density > 0) {
        barHeightVp = Number(region[3]) / density;
      }
      AppStorage.setOrCreate(NAV_MODE_KEY, NAV_MODE_THREE_BUTTON);
      AppStorage.setOrCreate(NAV_BUTTON_BAR_HEIGHT_KEY, barHeightVp);
      AppStorage.setOrCreate(BOTTOM_NAV_INSET_KEY, barHeightVp + INSET_EXTRA_VP);
      AppStorage.setOrCreate(BOTTOM_BAR_INSET_KEY, barHeightVp + INSET_EXTRA_VP);
      Logger.info(TAG, `settings=三键 栏高=${barHeightVp.toFixed(1)}vp 避让=${(barHeightVp + INSET_EXTRA_VP).toFixed(1)}vp`);
      return;
    }
    AppStorage.setOrCreate(NAV_MODE_KEY, showType === 1 ? NAV_MODE_FLOATING_BALL : NAV_MODE_GESTURE);
    refreshBottomNavInset();
    Logger.info(TAG, `settings=${showType === 1 ? '悬浮球' : '手势'}，避让量按兜底判据现算`);
  } catch (err) {
    Logger.warn(TAG, `float_navigation_info 解析失败，保持兜底值: ${(err as Error).message}`);
  }
}

/** 观察者：在系统设置里切换导航方式时实时重算（不用重启 App） */
export function initNavModeWatcher(context: common.Context): void {
  refreshBottomNavInset();
  refreshNavMode(context);
  try {
    settings.registerKeyObserver(context, FLOAT_NAVIGATION_INFO_KEY, settings.domainName.USER_PROPERTY,
      (_err: BusinessError): void => {
        refreshNavMode(context);
      });
  } catch (err) {
    Logger.warn(TAG, `注册导航方式观察者失败（模拟器/非华为 ROM 常见）: ${(err as Error).message}`);
  }
}

/** 非响应式取现值：只给无法挂 @StorageLink 的调用点；响应式消费必须 @StorageLink + build 内直读 */
export function bottomNavInset(): number {
  return AppStorage.get<number>(BOTTOM_NAV_INSET_KEY) ?? 0;
}

/**
 * EntryAbility 在 avoidArea 变化/首帧时调用，把窗口真值灌进兜底链路。
 *
 * 两条 rect 都要读（此前只读 `TYPE_NAVIGATION_INDICATOR` 一条）：三键栏的高度在部分
 * ROM 只上报进 `TYPE_SYSTEM.bottomRect`，那条读到 0 就把硬件栏判成「没有」、dock 压在键上。
 * 取法与有据不同（有意偏离，理由写在 `navInset.bottomAvoidHeightVp` 的注释里）：
 * 指示条有读数就用它，为 0 才回退 system；宽度跟着出高度那条走。判据本体在 `navInset.ets`，可进 hypium。
 */
export function publishNavAvoid(win: window.Window): void {
  try {
    const d: display.Display = display.getDefaultDisplaySync();
    const density: number = d.densityPixels;
    const sysRect: window.Rect = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).bottomRect;
    const indRect: window.Rect =
      win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR).bottomRect;
    const sysH: number = density > 0 ? sysRect.height / density : 0;
    const sysW: number = density > 0 ? sysRect.width / density : 0;
    const indH: number = density > 0 ? indRect.height / density : 0;
    const indW: number = density > 0 ? indRect.width / density : 0;
    reportBottomAvoid(bottomAvoidHeightVp(sysH, indH),
      bottomAvoidRectWidthVp(sysH, sysW, indH, indW),
      density > 0 ? d.width / density : 0);
  } catch (err) {
    Logger.warn(TAG, `发布导航避让区失败: ${(err as Error).message}`);
  }
}
