/**
 * 伴随助手 · 全局状态（AppStorage  backed，跨组件单点）。
 *
 * 提示以 JSON 串存 AppStorage（避免 V1 复杂嵌套对象 @StorageProp 的刷新坑），
 * 浮层组件 @StorageLink 该键、按需 parse。集成层（Phase 3）调 show() 浮出请示卡，
 * 用户点选/划掉后 dismiss()。默认空串 = 休眠，不扰现有 UI。
 */

import { CompanionAction, CompanionPrompt } from './CompanionTypes';
import { CompanionPrefs } from './CompanionPrefs';

export const COMPANION_PROMPT_KEY: string = 'companionPromptJson';

export class CompanionStore {
  /** 共享偏好（OnTrip 生成提示与浮层记录点选共用同一实例，降级闭环才成立） */
  static readonly prefs: CompanionPrefs = new CompanionPrefs();

  /** 执行委托：浮层在全局壳层，改行程的能力在 OnTrip，由它注册执行器 */
  private static executor: ((action: CompanionAction) => void) | null = null;
  /**
   * 待执行意图：浮层在别的页签被点选、但执行器只在 OnTrip 注册时，
   * 先跳进行程页并把意图暂存于此，OnTrip 首次 reload 完成后取走执行。
   * 没有它，「我累了/跳过这站」在行程页之外就是静默空操作（用户报「点了没反应」）。
   */
  private static pending: CompanionAction | null = null;

  static registerExecutor(fn: (action: CompanionAction) => void): void {
    CompanionStore.executor = fn;
  }

  static clearExecutor(): void {
    CompanionStore.executor = null;
  }

  /** 执行意图；返回是否已被执行器接手（false = 当前不在行程页，调用方需兜底） */
  static execute(action: CompanionAction): boolean {
    if (CompanionStore.executor !== null) {
      CompanionStore.executor(action);
      return true;
    }
    return false;
  }

  /** 暂存一条意图，等 OnTrip 挂载后取走执行（跳转前调） */
  static queueAction(action: CompanionAction): void {
    CompanionStore.pending = action;
  }

  /** 取走暂存意图（取后即清，避免下次进页面重复执行）；无则 null */
  static takePendingAction(): CompanionAction | null {
    const p: CompanionAction | null = CompanionStore.pending;
    CompanionStore.pending = null;
    return p;
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