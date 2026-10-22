/**
 * 动效 tokens · 时长单位 ms，曲线用系统 Curve 枚举。
 *
 * 契约锚点（handoff §6）：主按钮按下 scale(0.97) + 140ms。
 * spring 预留：弹性效果用 curves.springMotion(damping, mass)（import { curves } from '@kit.ArkUI'），
 * 时长由弹簧参数决定；接入时在此登记统一参数，禁止页面各自调参。
 * 禁令（§8-10）：不许用 opacity 表达状态（完成/禁用/选中一律换 token 或加图标）。
 */

import { Curve } from '@kit.ArkUI';

export interface MotionTokensType {
  /** 微反馈（按压态、勾选） */
  durationFast: number;
  /** 主按钮按下反馈（契约值，勿改） */
  pressDuration: number;
  /** 主按钮按下缩放（契约值，勿改） */
  pressScale: number;
  /** 常规过渡（展开收起、页面内状态切换） */
  durationBase: number;
  /** 大转场（页面级进出、弹层） */
  durationSlow: number;
  curveStandard: Curve;
  curveDecelerate: Curve;
}

export const MotionTokens: MotionTokensType = {
  durationFast: 100,
  pressDuration: 140,
  pressScale: 0.97,
  durationBase: 200,
  durationSlow: 300,
  curveStandard: Curve.EaseInOut,
  curveDecelerate: Curve.Friction
};
