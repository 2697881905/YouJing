/**
 * 伴随助手 · 全局状态（AppStorage  backed，跨组件单点）。
 *
 * 提示以 JSON 串存 AppStorage（避免 V1 复杂嵌套对象 @StorageProp 的刷新坑），
 * 浮层组件 @StorageLink 该键、按需 parse。集成层（Phase 3）调 show() 浮出请示卡，
 * 用户点选/划掉后 dismiss()。默认空串 = 休眠，不扰现有 UI。
 */

import { CompanionPrompt } from './CompanionTypes';

export const COMPANION_PROMPT_KEY: string = 'companionPromptJson';

export class CompanionStore {
  /** 浮出一张请示卡（同 id 去重由集成层保证） */
  static show(prompt: CompanionPrompt): void {
    AppStorage.setOrCreate(COMPANION_PROMPT_KEY, JSON.stringify(prompt));
  }

  /** 收起（点选后/划掉/沉默） */
  static dismiss(): void {
    AppStorage.setOrCreate(COMPANION_PROMPT_KEY, '');
  }

  /** 当前提示；无则 null */
  static current(): CompanionPrompt | null {
    const raw: string = AppStorage.get<string>(COMPANION_PROMPT_KEY) ?? '';
    if (raw.length === 0) {
      return null;
    }
    try {
      return JSON.parse(raw) as CompanionPrompt;
    } catch (err) {
      return null;
    }
  }
}