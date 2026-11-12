/**
 * 伴随助手 · 状态总线（AppStorage backed，跨组件单点）。
 *
 * 助手只活在行程页（OnTrip）：提示以 JSON 串存 AppStorage（避免 V1 复杂嵌套对象
 * @StorageProp 的刷新坑），行程页 @StorageLink 该键、按需 parse 渲染顶部请示横幅。
 * 集成层调 show() 浮出请示，用户点选/划掉后 dismiss()。默认空串 = 休眠，不扰现有 UI。
 */

import { CompanionAction, CompanionPrompt } from './CompanionTypes';
import { CompanionPrefs } from './CompanionPrefs';

export const COMPANION_PROMPT_KEY: string = 'companionPromptJson';

export class CompanionStore {
  /** 共享偏好（OnTrip 生成提示与浮层记录点选共用同一实例，降级闭环才成立） */
  static readonly prefs: CompanionPrefs = new CompanionPrefs();

  /** 执行委托：助手只活在行程页（OnTrip），改行程的能力由它注册执行器，恒在场 */
  private static executor: ((action: CompanionAction) => void) | null = null;

  static registerExecutor(fn: (action: CompanionAction) => void): void {
    CompanionStore.executor = fn;
  }

  static clearExecutor(): void {
    CompanionStore.executor = null;
  }

  /** 执行意图（执行器由行程页注册；助手只在行程页可点，故必在场） */
  static execute(action: CompanionAction): void {
    if (CompanionStore.executor !== null) {
      CompanionStore.executor(action);
    }
  }

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