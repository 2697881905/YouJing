/**
 * 伴随助手 · 偏好降级（纯逻辑，Phase 1 内存态，持久化留 Phase 5）。
 *
 * 请示的最高境界是越来越不需要请示：同一类低风险决定，用户连续选推荐项 ≥3 次，
 * 助手就从「请示」降为「通知」（仍透明、可撤销）。但降得慢、回升快——用户纠正一次立刻回请示。
 * 高风险决定永不降级（由引擎按 stake 控制，不经过本类的 notify）。
 */

import { CompanionMode } from './CompanionTypes';

/** 连续选推荐项达到此数才降级（降得慢） */
const DEGRADE_STREAK: number = 3;

export class CompanionPrefs {
  /** 每键连续选推荐项的次数 */
  private streak: Record<string, number> = {};
  /** 已降级为通知的键 */
  private notified: Record<string, boolean> = {};

  modeFor(key: string): CompanionMode {
    return this.notified[key] === true ? 'notify' : 'ask';
  }

  /**
   * 记录一次用户选择。选推荐项则累加连续计数，达阈值降级；
   * 选了别的（说明偏好不稳）则计数归零并撤销降级。
   */
  recordChoice(key: string, optionKey: string, recommendedKey: string): void {
    if (optionKey === recommendedKey) {
      const next: number = (this.streak[key] ?? 0) + 1;
      this.streak[key] = next;
      if (next >= DEGRADE_STREAK) {
        this.notified[key] = true;
      }
    } else {
      this.streak[key] = 0;
      this.notified[key] = false;
    }
  }

  /** 用户纠正：立刻回请示（回升快），连续计数清零。 */
  correct(key: string): void {
    this.streak[key] = 0;
    this.notified[key] = false;
  }
}