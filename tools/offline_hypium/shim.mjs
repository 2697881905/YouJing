/**
 * hypium 的最小离线替身：只为在**没有设备**时把纯逻辑用例真跑一遍。
 * 支持本仓实际用到的 7 个断言方法，其余一律抛错——静默放过比不跑更糟。
 * 设备可用时仍以 `aa test` 的 hypium 为准，这个不替代它。
 */
const results = { suites: [], run: 0, pass: 0, fail: 0, failures: [] };
let current = null;

export function describe(name, fn) {
  current = { name, cases: [] };
  results.suites.push(current);
  fn();
  current = null;
}

export function it(name, _flag, fn) {
  if (!current) {
    throw new Error('it() 必须在 describe() 内');
  }
  current.cases.push({ name, fn });
}

export const TestType = { FUNCTION: 1 };
export const Size = { SMALLTEST: 1, MEDIUMTEST: 2, LONGTEST: 3 };
export const Level = { LEVEL0: 0, LEVEL1: 1, LEVEL2: 2, LEVEL3: 3, LEVEL4: 4 };

function eq(a, b) {
  if (a === b) {
    return true;
  }
  if (typeof a === 'number' && typeof b === 'number') {
    // hypium 的 assertEqual 对数值按值比；0.1+0.2 这类误差由 assertClose 负责
    return Object.is(a, b) || (Number.isNaN(a) && Number.isNaN(b));
  }
  if (Array.isArray(a) && Array.isArray(b)) {
    return a.length === b.length && a.every((x, i) => eq(x, b[i]));
  }
  if (a && b && typeof a === 'object' && typeof b === 'object') {
    const ka = Object.keys(a);
    const kb = Object.keys(b);
    return ka.length === kb.length && ka.every((k) => eq(a[k], b[k]));
  }
  return false;
}

function fail(msg) {
  throw new Error(msg);
}

export function expect(actual) {
  return {
    assertEqual(expected) {
      if (!eq(actual, expected)) {
        fail(`assertEqual: 实得 ${JSON.stringify(actual)} 期望 ${JSON.stringify(expected)}`);
      }
    },
    assertTrue() {
      if (actual !== true) {
        fail(`assertTrue: 实得 ${JSON.stringify(actual)}`);
      }
    },
    assertFalse() {
      if (actual !== false) {
        fail(`assertFalse: 实得 ${JSON.stringify(actual)}`);
      }
    },
    assertNull() {
      if (actual !== null) {
        fail(`assertNull: 实得 ${JSON.stringify(actual)}`);
      }
    },
    assertUndefined() {
      if (actual !== undefined) {
        fail(`assertUndefined: 实得 ${JSON.stringify(actual)}`);
      }
    },
    assertClose(expected, precision = 1e-6) {
      if (typeof actual !== 'number' || typeof expected !== 'number'
        || Math.abs(actual - expected) > precision) {
        fail(`assertClose: 实得 ${actual} 与 ${expected} 差大于 ${precision}`);
      }
    },
    assertLarger(expected) {
      if (!(actual > expected)) {
        fail(`assertLarger: 实得 ${actual} 不大于 ${expected}`);
      }
    },
  };
  // 未实现的断言名（assertContain / assertEqualNeg 等）一律抛错，
  // 避免"跑了但什么都没断"——静默 undefined 会被当成通过，那是假绿。
  return new Proxy(api, {
    get(target, prop) {
      if (typeof prop === 'string' && !(prop in target)) {
        return () => {
          throw new Error('离线替身不支持 expect().' + prop
            + '()：请把它补进 tools/offline_hypium/shim.mjs');
        };
      }
      return target[prop];
    }
  });
}


export async function flush() {
  for (const suite of results.suites) {
    for (const c of suite.cases) {
      results.run += 1;
      try {
        await c.fn();
        results.pass += 1;
      } catch (err) {
        results.fail += 1;
        results.failures.push(`${suite.name} / ${c.name}: ${err.message}`);
      }
    }
  }
  return results;
}

export function getResults() {
  return results;
}
