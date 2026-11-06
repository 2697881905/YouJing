/**
 * 离线跑用例时缺的 ArkUI 运行时全局，给**最小**替身。
 * 每条都只做到"存在且行为可预期"，不做语义仿真——所以离线过了不等于真机过了，
 * 设备可用时仍以真机 `aa test` 为准。
 */
class MemoryStorage {
  constructor() {
    this.map = new Map();
  }

  setOrCreate(key, value) {
    this.map.set(key, value);
  }

  set(key, value) {
    this.map.set(key, value);
  }

  get(key) {
    return this.map.get(key);
  }

  delete(key) {
    this.map.delete(key);
  }

  clear() {
    this.map.clear();
  }
}

class StubProperty {
  constructor(key, init) {
    this.key = key;
    this.value = init;
  }

  get() {
    return this.value;
  }

  set(v) {
    this.value = v;
  }
}

class StubNavPathStack {
  constructor() {
    this.stack = [];
  }

  pushPath(info, options) {
    this.stack.push(info);
  }

  pushUrl(info) {
    this.stack.push(info);
  }

  pop(result) {
    return this.stack.pop();
  }

  popToName(name) {
    const i = this.stack.map((p) => p.name).lastIndexOf(name);
    if (i >= 0) {
      this.stack.length = i + 1;
    }
  }

  replacePath(info) {
    if (this.stack.length) {
      this.stack[this.stack.length - 1] = info;
    }
  }

  getAllPathName() {
    return this.stack.map((p) => p.name);
  }

  size() {
    return this.stack.length;
  }

  clear() {
    this.stack = [];
  }
}

export function install() {
  if (!globalThis.AppStorage) {
    const mem = new MemoryStorage();
    globalThis.AppStorage = class {
      static setOrCreate(key, value) {
        mem.setOrCreate(key, value);
      }

      static set(key, value) {
        mem.set(key, value);
      }

      static get(key) {
        return mem.get(key);
      }

      static link(key) {
        return new StubProperty(key, mem.get(key));
      }

      static prop(key, init) {
        if (mem.get(key) === undefined) {
          mem.set(key, init);
        }
        return new StubProperty(key, mem.get(key));
      }

      static remove(key) {
        mem.delete(key);
      }
    };
    globalThis.__offlineAppStorage = mem;
  }
  if (!globalThis.$r) {
    // 资源引用只需要"非空且可比较"；真实图标/文案在设备侧才谈得上
    globalThis.$r = (name) => ({ id: name.hashCode ? name.hashCode() : 0, name, type: 3, params: [] });
  }
  if (!globalThis.NavPathStack) {
    globalThis.NavPathStack = StubNavPathStack;
  }
}
