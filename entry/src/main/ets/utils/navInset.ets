/**
 * 底部避让的纯计算层（零 @kit 依赖，因此可进 hypium）。
 *
 * 为什么要和系统读取分开：判定要读 `settings 'float_navigation_info'` 与
 * `getWindowAvoidArea`，那些在测试上下文里拿不到（ohosTest 只有 ApplicationContext，
 * 偏好/DB 类还会被拒）。把「算」抽出来，胶水层只负责取数与发布。
 *
 * 判据来源（有据 navMode.ets 文件头，两条真机实测换来的）：
 *  · 手势指示条是居中窄胶囊（模拟器实测宽 137vp / 屏宽 391vp = 35%）
 *  · 三键栏的避让矩形必然横贯整屏（左右两颗键不可能落在避让区之外）
 *  · **只看高度判不开**：模拟器手势条 27.9vp 与真机三键栏 27.8vp 区间完全重叠，
 *    旧注释「16-24 / 28-42 不重叠」是错的，后果是把手势条当三键、Dock 白抬 28.9vp。
 * 因此三键必须「高度 > 24 **且** 宽度 ≥ 屏宽 90%」同时成立；上报缺项一律保守判手势。
 */

export const NAV_MODE_GESTURE: string = 'gesture';
export const NAV_MODE_THREE_BUTTON: string = 'three-button';
export const NAV_MODE_FLOATING_BALL: string = 'floating-ball';

/** 高度阈值：≤ 此值绝不判三键 */
export const GESTURE_INDICATOR_MAX: number = 24;
/** 三键判定所需的最小宽度占比，0.9 给分屏/小窗留余量 */
export const THREE_BUTTON_MIN_WIDTH_RATIO: number = 0.9;
/** 三键栏高之外的呼吸量（vp） */
export const NAV_INSET_EXTRA: number = 1;
/** 内容级底部内边距：手势档下的指示条预留（vp） */
export const GESTURE_INDICATOR_INSET: number = 16;

export function spansFullWidth(bottomRectWidthVp: number, windowWidthVp: number): boolean {
  if (windowWidthVp <= 0 || bottomRectWidthVp <= 0) {
    return false;
  }
  return bottomRectWidthVp >= windowWidthVp * THREE_BUTTON_MIN_WIDTH_RATIO;
}

export function isThreeButton(heightVp: number, bottomRectWidthVp: number, windowWidthVp: number): boolean {
  return heightVp > GESTURE_INDICATOR_MAX && spansFullWidth(bottomRectWidthVp, windowWidthVp);
}

/** 悬浮 dock 的底部边距增量：手势档恒 0（底栏维持原设计，不整体顶高） */
export function computeNavInset(heightVp: number, bottomRectWidthVp: number, windowWidthVp: number): number {
  return isThreeButton(heightVp, bottomRectWidthVp, windowWidthVp) ? heightVp + NAV_INSET_EXTRA : 0;
}

/** 内容级底部内边距：三键 = 栏高 + 呼吸；手势 = 指示条常量 */
export function computeBarInset(heightVp: number, bottomRectWidthVp: number, windowWidthVp: number): number {
  return isThreeButton(heightVp, bottomRectWidthVp, windowWidthVp)
    ? heightVp + NAV_INSET_EXTRA : GESTURE_INDICATOR_INSET;
}
