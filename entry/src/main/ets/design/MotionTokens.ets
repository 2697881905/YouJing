/**
 * 动效 tokens · 契约 v2 `motion:` 段逐字落值（时长单位 ms，缩放为无量纲倍率）。
 *
 * 契约锚点：`motion.press 140ms` / `control 220ms` / `container 320ms` / `shimmer 1200ms` /
 * `press-scale 0.97`；`curve-standard = cubic-bezier(0.2, 0.8, 0.2, 1)`、
 * `curve-decelerate = cubic-bezier(0, 0, 0.2, 1)`。
 *
 * 本页只收「批次一已拍定的五档 + 三条曲线」。契约里的 `page`/`emphasis`/`stagger`/
 * `shared-element`/`press-opacity`/`press-slide-scale`/`success-scale`/`enter-scale` 与
 * spring/emphasized 曲线属 P3 动效层，接入时才在此登记，禁止页面各自调参。
 * spring 预留：弹性效果用 curves.springMotion(response, dampingFraction)，时长由弹簧参数决定。
 * 禁令（§8-10）：不许用 opacity 表达状态（完成/禁用/选中一律换 token 或加图标）。
 *
 * 消费方（P2 的 BaseCard/Pressable、P3 的转场工厂）写动效只准引用这里；
 * tools/audit_motion.py 拦裸时长、枚举曲线与 .animation()/.stateStyles() 顺序倒置。
 */

import { curves } from '@kit.ArkUI';

export interface MotionTokensType {
  /** 微反馈：主按钮按下、勾选（契约 motion.press） */
  press: number;
  /** 控件级过渡：分段切换、开关、折叠（契约 motion.control） */
  control: number;
  /** 容器级过渡：卡片展开、弹层进出（契约 motion.container） */
  container: number;
  /** 骨架屏流光循环（契约 motion.shimmer） */
  shimmer: number;
  /** 按下缩放倍率（契约 motion.press-scale，勿改） */
  pressScale: number;
}

export const MotionTokens: MotionTokensType = {
  press: 140,
  control: 220,
  container: 320,
  shimmer: 1200,
  pressScale: 0.97
};

/** 契约 curve-standard = cubic-bezier(0.2, 0.8, 0.2, 1)。ArkTS 的 Curve 是枚举，
 *  自定义贝塞尔必须走 curves.cubicBezierCurve 返回 ICurve（有据 motion.ets:32 已在用）。 */
export class MotionCurves {
  static readonly standard: ICurve = curves.cubicBezierCurve(0.2, 0.8, 0.2, 1);
  static readonly decelerate: ICurve = curves.cubicBezierCurve(0, 0, 0.2, 1);
  static readonly linear: ICurve = curves.cubicBezierCurve(0, 0, 1, 1);
  /** dock 选中胶囊落定的回弹（有据 §7.6.32 同款果冻感）。
   *  response/damping 是动效层参数，按本文件约定只在这里登记一次，页面不许各自调。 */
  static readonly springBounce: ICurve = curves.springMotion(0.4, 0.55);
}
