/**
 * 动效 tokens · 2026-11-07 全量对齐「有据」源码（YU/design/tokens/motion.ets）。
 *
 * 保留原有五档名与值（press/control/container/shimmer/pressScale）与三条曲线名，
 * 因为 644 个调用点、StyleConfig.test.ets 的曲线指纹断言、audit_motion.py 白名单都依赖它们。
 * 新增的只是有据源码里「有实现、有消费方」的档位别名，禁止页面各自调参。
 *
 * 状态表达允许 opacity（2026-11-07 决议）：禁用 0.45、按下 0.92；
 * `.animation()` 必须紧贴 `.stateStyles()` **之前**，见 components/Pressable.ets。
 * 三处栏面 blur 50 与 `scrolled ? 50 : 0` 绝对偏移门控仍由 HdsChrome 承担。
 */

import { curves } from '@kit.ArkUI';

export interface MotionTokensType {
  /** 微反馈：主按钮按下、勾选（契约 motion.press，= 有据 fast） */
  press: number;
  /** 控件级过渡：分段切换、开关、折叠（契约 motion.control，= 有据 base） */
  control: number;
  /** 容器级过渡：卡片展开、弹层进出（契约 motion.container，= 有据 slow） */
  container: number;
  /** 骨架屏流光循环 */
  shimmer: number;
  /** 按下缩放倍率 */
  pressScale: number;
  /** 有据 instant / none */
  instant: number;
  none: number;
  /** 有据档名别名（值与上面三档同源） */
  fast: number;
  base: number;
  slow: number;
  enter: number;
  page: number;
  emphasis: number;
  stagger: number;
  staggerEmphasis: number;
  /** 有据按下/入场/成功倍率 */
  pressSlideScale: number;
  pressOpacity: number;
  successScale: number;
  enterScale: number;
  /**
   * dock 选中胶囊「行进」时长（有据 `DOCK_PILL_TRAVEL_MS` 同值 300）。
   * 为什么不是 container(320)：胶囊与页面翻页同批起飞，300 是有据真机定档值，
   * 多 20ms 会读成「玻璃晚半拍」。唯一消费方是 pages/Index 的 dockPillTravel。
   */
  dockTravel: number;
  /**
   * dock 选中胶囊「落定回弹」时长（有据 `DOCK_PILL_SETTLE_MS` 同值 400）。
   * springBounce(0.4,0.7) 走完整段物理行程需要这个余量，短了果冻感会断在半路。
   */
  dockSettle: number;
}

export const MotionTokens: MotionTokensType = {
  press: 140,
  control: 220,
  container: 320,
  shimmer: 1200,
  pressScale: 0.97,
  instant: 100,
  none: 0,
  fast: 140,
  base: 220,
  slow: 320,
  enter: 360,
  page: 420,
  emphasis: 460,
  stagger: 40,
  staggerEmphasis: 56,
  pressSlideScale: 0.94,
  pressOpacity: 0.92,
  successScale: 1.045,
  enterScale: 0.975,
  dockTravel: 300,
  dockSettle: 400
};

/**
 * 曲线集合。standard / decelerate / linear / springBounce(0.4, 0.55) 四条是既有值，
 * 其中 springBounce 的 ICurve 指纹被 StyleConfig.test.ets:120-140 逐值钉死，不许改参数；
 * 有据 springBounce(0.4, 0.7) 另以 springBounceYu 别名登记。
 */
export class MotionCurves {
  static readonly standard: ICurve = curves.cubicBezierCurve(0.2, 0.8, 0.2, 1);
  static readonly decelerate: ICurve = curves.cubicBezierCurve(0, 0, 0.2, 1);
  static readonly linear: ICurve = curves.cubicBezierCurve(0, 0, 1, 1);
  static readonly springBounce: ICurve = curves.springMotion(0.4, 0.55);
  static readonly accelerate: ICurve = curves.cubicBezierCurve(0.4, 0, 1, 1);
  static readonly spring: ICurve = curves.cubicBezierCurve(0.34, 1.56, 0.64, 1);
  static readonly springSoft: ICurve = curves.cubicBezierCurve(0.22, 1.22, 0.36, 1);
  static readonly emphasized: ICurve = curves.cubicBezierCurve(0.16, 1, 0.3, 1);
  static readonly springInteract: ICurve = curves.springMotion(0.6, 0.85);
  static readonly springBounceYu: ICurve = curves.springMotion(0.4, 0.7);
  static readonly springRelease: ICurve = curves.springMotion(0.5, 0.75);
  static readonly springSettle: ICurve = curves.springMotion(0.3, 0.62);
  static readonly springTrack: ICurve = curves.springMotion(0.25, 0.72);
}
