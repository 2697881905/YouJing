/**
 * 顶部系统带（状态栏那 33.9vp）的底色，单点。
 *
 * 为什么需要它：窗口铺满物理屏之后，页面 `root` 仍被页面级安全区推到 33.9vp，
 * 而 `Swiper` / `TabContent` 都报 `clip=true` —— 满铺底图的屏（地图格、屏15）
 * 画不进这条带子，只能由系统涂。默认涂画布色，于是**画布色的带子压在夜色底图上**
 * 出现一条硬色差（真机实测：带子 18、底图 56~75）。四格纯色页画布就是它们的顶边，
 * 所以那四屏本来就没缝，只有底图类屏要把带子换成底图基色。
 *
 * 颜色不写死：只存**资源名**，按当前生效配置用 `getColorByNameSync` 解 ——
 * 与 `EntryAbility.seedDarkMode` 同一手法，深浅两档一份实现，
 * 也不会出现"两处各写一遍 2A3A53"。
 */

import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Logger } from '../common/logger/Logger';

const TAG: string = 'Ui.TopStrip';
/** 系统栏透明：带子颜色交给视图层，见 paint() 里的 A 档说明 */
const TRANSPARENT_BAR: string = '#00000000';

/** AppStorage 键：当前该涂这条带子的颜色**资源名**（不是色值，色值按档现解） */
export const TOP_STRIP_KEY: string = 'topStripColorName';
/** 默认：跟着画布走（四格纯色页就是它） */
export const STRIP_CANVAS: string = 'canvas';
/** 满铺底图类屏：跟夜色底图基色走（深色档实测主色 #2A3A53，占底图区 48.5%） */
export const STRIP_MAP: string = 'map_strip_base';

/** ARGB 数值 → '#AARRGGBB'；解不出来退回画布深色，不让带子变黑 */
function toArgb(argb: number): string {
  return `#${(argb >>> 0).toString(16).padStart(8, '0')}`;
}

export class TopStrip {
  /** 按当前生效配置解出资源名对应的 ARGB 串 */
  static resolveColor(ctx: common.Context, resName: string): string {
    try {
      return toArgb(ctx.resourceManager.getColorByNameSync(resName));
    } catch (err) {
      Logger.warn(TAG, `解 ${resName} 失败，退回画布: ${(err as Error).message}`);
      try {
        return toArgb(ctx.resourceManager.getColorByNameSync(STRIP_CANVAS));
      } catch (e2) {
        return '#FF121212';
      }
    }
  }

  /**
   * 把带子涂成 `resName`。窗口由调用方给（Ability 侧有主窗口句柄，
   * 页面侧走 `window.getLastWindow`），两边共用同一份涂色逻辑。
   */
  static paint(win: window.Window, ctx: common.Context, resName: string): void {
    const color: string = TopStrip.resolveColor(ctx, resName);
    try {
      // 手势导航下 navigationBarColor 不生效，底部那条透传的是窗口背景色，
      // 所以两处一起涂才会上下对称（同族工程实测）
      win.setWindowBackgroundColor(color);
    } catch (e) {
      Logger.warn(TAG, `setWindowBackgroundColor 失败: ${(e as Error).message}`);
    }
    // A 档（2026-11-05）：两条系统栏改**透明**，带子的颜色只由视图层决定——
    // `pages/Index` 那层根 Column 已经按 `stripName` 涂 canvas / map_strip_base，
    // 系统层再涂一份是多余的第二个图层：它不参与顶栏材质与模糊采样，
    // 滚动时和页面之间永远留一条硬边，用户读到的就是「通知栏区域与其他地方有色差、
    // 布局没撑满整屏」。透明后带子就是页面本身，缝没有第二个来源。
    //
    // 代价：图标从此压在页面色上，必须显式给明暗，否则深色档白画布…反过来说，
    // 浅色档配默认白图标会直接看不见。判据取 AppStorage 的 isDarkMode（与 seedDarkMode 同源）。
    const isDark: boolean = AppStorage.get<boolean>('isDarkMode') ?? false;
    const props: window.SystemBarProperties = {
      statusBarColor: TRANSPARENT_BAR,
      navigationBarColor: TRANSPARENT_BAR,
      isStatusBarLightIcon: isDark
    };
    win.setWindowSystemBarProperties(props).catch((err: Error): void => {
      Logger.warn(TAG, `setWindowSystemBarProperties 失败: ${err.message}`);
    });
  }

  /**
   * 页面侧入口：记下当前该用哪个色，再把已存在的窗口涂掉。
   * 只写 AppStorage 不涂，切换时会有一帧留着上一页的颜色。
   */
  static apply(ctx: common.Context, resName: string): void {
    AppStorage.setOrCreate(TOP_STRIP_KEY, resName);
    window.getLastWindow(ctx).then((win: window.Window): void => {
      TopStrip.paint(win, ctx, resName);
    }).catch((err: Error): void => {
      Logger.warn(TAG, `取窗口失败，带子色留到下次: ${err.message}`);
    });
  }

  /** 当前该涂哪个色（EntryAbility 在配置变化/回前台时按这个重涂） */
  static current(): string {
    return AppStorage.get<string>(TOP_STRIP_KEY) ?? STRIP_CANVAS;
  }
}
