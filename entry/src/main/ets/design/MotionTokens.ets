/**
 * 动效 tokens · 时长单位 ms，曲线用系统 Curve 枚举。
 *
 * spring 动画预留用法：需要弹性效果（如行程编辑拖动排序回弹、卡片按压）时，
 * 不用本文件的固定时长，改用 curves.springMotion(damping, mass) 或
 * curves.responsiveSpringMotion() 生成曲线（import { curves } from '@kit.ArkUI'），
 * 时长由弹簧参数决定；接入时在此登记统一参数，禁止页面各自调参。
 */

import { Curve } from '@kit.ArkUI';

export interface MotionTokensType {
  /** 微反馈（按压态、勾选） */
  durationFast: number;
  /** 常规过渡（展开收起、页面内状态切换） */
  durationBase: number;
  /** 大转场（页面级进出、弹层） */
  durationSlow: number;
  curveStandard: Curve;
  curveDecelerate: Curve;
}

export const MotionTokens: MotionTokensType = {
  durationFast: 100,
  durationBase: 200,
  durationSlow: 300,
  curveStandard: Curve.EaseInOut,
  curveDecelerate: Curve.Friction
};
