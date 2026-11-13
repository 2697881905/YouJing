/**
 * @kit.ArkData 的离线替身（只给 skill_check 用）。
 *
 * preferences 分片替身：按 name 分桶，Map 存键值。必须**跨调用保持同一桶**——
 * SkillPrefill.save 与 SkillPrefill.take 是两次 getPreferencesSync，
 * 每次返回新桶的话，取回来必为空，「取后即删」这条断言就成了假绿。
 */

export namespace preferences {
  export type ValueType = string | number | boolean | Object;

  export interface Preferences {
    putSync(key: string, value: ValueType): void;
    getSync(key: string, defaultValue: ValueType): ValueType;
    deleteSync(key: string): void;
    flushSync(): void;
  }

  export interface Options {
    name: string;
  }

  export function getPreferencesSync(context: Object, options: Options): Preferences {
    const g: Record<string, Object> = globalThis as unknown as Record<string, Object>;
    const store: Map<string, Map<string, ValueType>> =
      (g['__skill_prefs'] as Map<string, Map<string, ValueType>>) ?? new Map();
    g['__skill_prefs'] = store;
    if (!store.has(options.name)) {
      store.set(options.name, new Map());
    }
    const bucket: Map<string, ValueType> = store.get(options.name) as Map<string, ValueType>;
    return {
      putSync(key: string, value: ValueType): void {
        bucket.set(key, value);
      },
      getSync(key: string, defaultValue: ValueType): ValueType {
        const found: ValueType | undefined = bucket.get(key);
        return found === undefined ? defaultValue : found;
      },
      deleteSync(key: string): void {
        bucket.delete(key);
      },
      flushSync(): void {
      }
    };
  }
}
