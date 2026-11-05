/**
 * 系统栏图标明暗的「补设」通道。
 *
 * 为什么需要：HDS 标题栏在挂载期与滚动特效回位（滚回顶部）时会回写系统栏属性，
 * 把应用按自身主题显式设的 `isStatusBarLightIcon` 覆盖成按**系统**深浅渲染
 * （系统深 + 应用浅的组合态下渲成白色，浅色画布上直接看不见）。
 * SDK 没有关停该联动的人口（只有整体隐藏的 hideStatusBar），只能在每次被覆盖后补设。
 *
 * 为什么是四连发而不是单发：有据真机两次复现分别落在 <0.6s 与 ~2.9s，
 * 与单发 400ms 去抖构成竞速、有输有赢。连发四发、最后一发 3s 与挂载期补设同刻，
 * 任何 ≤3s 的回写都会被最后一发压住；HDS 的回写只发生一次，连发不会互相打架。
 */
let refresher: (() => void) | null = null;
const REFRESH_SHOTS_MS: number[] = [400, 1000, 1800, 3000];
let pendingTimers: number[] = [];

export function setSystemBarRefresher(fn: () => void): void {
  refresher = fn;
}

export function requestSystemBarRefresh(): void {
  for (const t of pendingTimers) {
    clearTimeout(t);
  }
  pendingTimers = [];
  for (const delay of REFRESH_SHOTS_MS) {
    const id: number = setTimeout((): void => {
      if (refresher !== null) {
        refresher();
      }
      pendingTimers = pendingTimers.filter((t: number): boolean => t !== id);
    }, delay) as number;
    pendingTimers.push(id);
  }
}
