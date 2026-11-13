/**
 * @kit.AbilityKit 的离线替身（只给 skill_check 用）。
 *
 * 只补 skill 脚本真正用到的那几个符号：scriptManager.completeArkTSScriptInApp
 * 是脚本回报结果的唯一出口，替身把回包存进全局数组让断言取用；
 * common.UIAbilityContext.startAbility 在替身里**抛 201**——真机上手机
 * 后台拉起就是这个错（START_ABILITIES_FROM_BACKGROUND 仅系统应用），
 * 脚本必须自己吞掉它并仍回 success。替身照抄这个行为。
 */

export namespace common {
  export interface UIAbilityContext {
    startAbility(want: Want): Promise<void>;
  }
  export interface Context {
  }
}

export interface Want {
  bundleName: string;
  abilityName: string;
  parameters?: Record<string, Object>;
}

/** 手机后台拉起 UIAbility 的系统错误码 */
const ERR_START_FROM_BACKGROUND: number = 201;

export namespace scriptManager {
  export interface ArkTSScriptInfo {
    context: common.Context;
    requestCode: number;
  }
  export interface ExecuteResult {
    code: number;
    result: Object;
  }
  export function completeArkTSScriptInApp(
    context: common.Context, requestCode: number, result: ExecuteResult
  ): Promise<void> {
    const g: Record<string, Object> = globalThis as unknown as Record<string, Object>;
    const arr: Object[] = (g['__captured'] as Object[]) ?? [];
    arr.push(result as unknown as Object);
    g['__captured'] = arr;
    return Promise.resolve();
  }
}

/** 供替身注入的 startAbility 行为：默认按手机语义抛 201 */
export function makeContext(): common.UIAbilityContext {
  return {
    startAbility(want: Want): Promise<void> {
      const err: Error = new Error('startAbility failed: ' + ERR_START_FROM_BACKGROUND);
      (err as unknown as Record<string, Object>)['code'] = ERR_START_FROM_BACKGROUND;
      return Promise.reject(err);
    }
  };
}
