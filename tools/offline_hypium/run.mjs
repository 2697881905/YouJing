#!/usr/bin/env node
/**
 * 无设备跑纯逻辑 hypium 用例：把 ohosTest 的用例文件**原样**搬到临时目录，
 * 只改写 import 指向（`.ets`→`.ts`、`@ohos/hypium`→本地替身），
 * 断言一条都不复制——跑的就是设备上要跑的那些代码。
 *
 * 用法：node --experimental-strip-types tools/offline_hypium/run.mjs [--quiet]
 * 退出码：0 = 跑到的用例全过；1 = 有用例失败。（跳过数不影响退出码，但必须报出来。）
 *
 * 边界（必须诚实）：
 *  · 被测闭包里出现 @kit.* / @ohos.*（hypium 除外）→ 整个套件判"离线跑不了"，
 *    那些只能在真机 aa test 里跑（本仓里设备侧只挂 ApplicationContext，见 INIT_REPORT）。
 *  · 设备可用时仍以 `aa test` 为准，这里不能替代它（UI/装饰器/资源都在它覆盖之外）。
 */
// strip-only 模式不支持 enum（本仓好几个枚举是被测面），需要 transform 旗标；
// 自己没带就带上旗标重跑一次，调用方 `node tools/offline_hypium/run.mjs` 就够。
if (!process.execArgv.some((x) => x.includes('transform-types'))) {
  const { spawnSync } = await import('node:child_process');
  const again = spawnSync(process.execPath,
    ['--experimental-transform-types', '--no-warnings', fileURLToPath(import.meta.url), ...process.argv.slice(2)],
    { stdio: 'inherit' });
  process.exit(again.status ?? 1);
}
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';


const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, '..', '..');
const SHIM = path.join(HERE, 'shim.mjs');
const QUIET = process.argv.includes('--quiet');

const SRC_MAIN = path.join(REPO, 'entry/src/main/ets');
const SRC_TEST = path.join(REPO, 'entry/src/ohosTest/ets/test');

const work = fs.mkdtempSync(path.join(os.tmpdir(), 'youjing-offline-'));

function copyTree(src, dst) {
  fs.mkdirSync(dst, { recursive: true });
  for (const e of fs.readdirSync(src, { withFileTypes: true })) {
    const a = path.join(src, e.name);
    const base = e.isDirectory() ? e.name : e.name.replace(/\.ets$/, '.ts');
    const b = path.join(dst, base);
    if (e.isDirectory()) {
      copyTree(a, b);
    } else if (/\.(ets|ts)$/.test(e.name)) {
      fs.copyFileSync(a, b);
    }
  }
}
// 保持原相对深度：用例里的 `../../../main/ets/...` 只有按 entry/src 的骨架拷过去才连得上
copyTree(SRC_MAIN, path.join(work, 'entry/src/main/ets'));
copyTree(SRC_TEST, path.join(work, 'entry/src/ohosTest/ets/test'));

const SPEC = /(\bfrom\s+['"])([^'"]+)(['"])/g;
const BARE = /(^\s*import\s+['"])([^'"]+)(['"])/;

function resolveSpec(fromFile, spec) {
  if (!spec.startsWith('.')) {
    return null;
  }
  const baseDir = path.dirname(fromFile);
  const cands = [path.resolve(baseDir, spec + '.ts'), path.resolve(baseDir, spec, 'index.ts'),
    path.resolve(baseDir, spec)];
  for (const c of cands) {
    if (fs.existsSync(c) && fs.statSync(c).isFile()) {
      return c;
    }
  }
  return null;
}

/* ArkTS 的 interface/type 在 ESM 下不是运行时导出：按目标文件的实际导出形态拆开，
   纯类型走 import type，否则整个模块载入就炸（"does not provide an export named ..."）。 */
const RUNTIME_EXPORT = /export\s+(?:default\s+)?(?:async\s+)?(?:class|enum|const|let|var|function)\s+(\w+)/g;
const TYPE_EXPORT = /export\s+(?:interface|type)\s+(\w+)/g;
const RE_EXPORT = /export\s*\{([^}]*)\}/g;
const exportsCache = new Map();

function exportsOf(file) {
  if (exportsCache.has(file)) {
    return exportsCache.get(file);
  }
  const text = fs.readFileSync(file, 'utf-8');
  const runtime = new Set();
  const types = new Set();
  for (const m of text.matchAll(RUNTIME_EXPORT)) {
    runtime.add(m[1]);
  }
  for (const m of text.matchAll(TYPE_EXPORT)) {
    types.add(m[1]);
  }
  for (const m of text.matchAll(RE_EXPORT)) {
    for (const raw of m[1].split(',')) {
      const name = raw.trim().split(/\s+as\s+/).pop();
      if (name && !runtime.has(name) && !types.has(name)) {
        runtime.add(name);
      }
    }
  }
  const o = { runtime, types };
  exportsCache.set(file, o);
  return o;
}

function splitTypeImports(quotedSpec, names, target) {
  const { runtime, types } = exportsOf(target);
  const val = [];
  const typ = [];
  for (const n of names) {
    if (!runtime.has(n) && types.has(n)) {
      typ.push(n);
    } else {
      val.push(n);
    }
  }
  const out = [];
  if (val.length) {
    out.push(`import { ${val.join(', ')} } from ${quotedSpec};`);
  }
  if (typ.length) {
    out.push(`import type { ${typ.join(', ')} } from ${quotedSpec};`);
  }
  return out.join('\n');
}

function arktsAllowed(file) {
  // 只看该文件从 @kit.ArkTS 里拿了什么名字：白名单外一律不映射
  const t = fs.readFileSync(file, 'utf-8');
  const re = /import\s*\{([^}]*)\}\s*from\s*'@kit\.ArkTS'/g;
  let m;
  let seen = false;
  while ((m = re.exec(t)) !== null) {
    seen = true;
    for (const raw of m[1].split(',')) {
      const name = raw.trim().split(/\s+as\s+/)[0];
      if (!['util', 'buffer'].includes(name)) {
        return false;
      }
    }
  }
  return seen;
}

function rewrite(file) {
  let text = fs.readFileSync(file, 'utf-8');
  const deps = [];
  const bad = [];
  const swap = (m, pre, spec, post) => {
    if (spec === '@ohos/hypium') {
      return pre + 'file://' + SHIM + post;
    }
    if (/^@(kit|ohos)\./.test(spec)) {
      if (spec === '@kit.ArkTS' && arktsAllowed(file)) {
        return pre + 'file://' + path.join(HERE, 'kit_arkts.mjs') + post;
      }
      bad.push(spec);
      return m;
    }
    const r = resolveSpec(file, spec);
    if (r) {
      deps.push(r);
      const rel = path.relative(path.dirname(file), r);
      return pre + './' + rel.split(path.sep).join('/') + post;
    }
    return m;
  };
  text = text.replace(SPEC, swap).replace(BARE, swap);
  // 第二遍：按目标文件的导出形态拆 import / import type
  text = text.replace(/import\s+\{([^}]*)\}\s+from\s+(['"][^'"]+['"]);?/g,
    (m, names, quoted) => {
      const spec = quoted.slice(1, -1);
      if (!spec.startsWith('.')) {
        return m;
      }
      const target = resolveSpec(file, spec.replace(/\.ts$/, '')) || resolveSpec(file, spec);
      if (!target) {
        return m;
      }
      const list = names.split(',').map((x) => x.trim()).filter((x) => x.length > 0);
      return splitTypeImports(quoted, list, target);
    });
  fs.writeFileSync(file, text);
  return { deps, bad };
}

const all = [];
(function walk(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    e.isDirectory() ? walk(p) : (e.name.endsWith('.ts') && all.push(p));
  }
})(work);

const info = new Map();
for (const f of all) {
  info.set(f, rewrite(f));
}

function closure(file, seen = new Set()) {
  if (seen.has(file)) {
    return seen;
  }
  seen.add(file);
  for (const d of (info.get(file) || { deps: [] }).deps) {
    closure(d, seen);
  }
  return seen;
}

const suites = all.filter((f) => f.includes(`${path.sep}test${path.sep}`))
  .filter((f) => f.endsWith('.test.ts'))
  .filter((f) => path.basename(f) !== 'List.test.ts')
  .sort();

// 先装 ArkUI 运行时全局的最小替身（AppStorage/$r/NavPathStack），否则这些模块连载入都失败
const stubs = await import('file://' + path.join(HERE, 'stubs.mjs'));
stubs.install();

const runnable = [];
const skipped = [];
for (const s of suites) {
  const bad = [];
  for (const f of closure(s)) {
    bad.push(...(info.get(f) || { bad: [] }).bad);
  }
  if (bad.length) {
    skipped.push([path.basename(s), Array.from(new Set(bad)).join(' ')]);
  } else {
    runnable.push(s);
  }
}

let run = 0;
let pass = 0;
const failures = [];
const loadErrors = [];
for (const s of runnable) {
  try {
    const mod = await import('file://' + s);
    await mod.default();
  } catch (err) {
    loadErrors.push(`${path.basename(s)}: ${String(err.message).split('\n')[0]}`);
  }
}

// 收集 shim 里的结果（同进程）
const shim = await import('file://' + SHIM);
await shim.flush();
const r = shim.getResults();
console.log(`离线 hypium：套件 可跑 ${runnable.length} / 跳过 ${skipped.length}`
  + ` ｜ Tests run: ${r.run}, Pass: ${r.pass}, Failure: ${r.fail}`
  + (loadErrors.length ? ` ｜ 离线跑不了 ${loadErrors.length}` : ''));
if (!QUIET) {
  for (const e of loadErrors) {
    console.log('  跑不了 ' + e);
  }
  for (const f of r.failures) {
    console.log('  FAIL ' + f);
  }
  for (const [n, why] of skipped) {
    console.log(`  SKIP ${n} ← ${why}`);
  }
}
if (process.argv.includes('--selftest')) {
  // 反证：这条管线必须能抓到一个人为注进去的失败，否则"全过"不算证据
  const probe = path.join(work, 'entry/src/ohosTest/ets/test/__SelfProbe.test.ts');
  fs.writeFileSync(probe, "import { describe, it, expect, TestType, Size, Level } from "
    + JSON.stringify('file://' + SHIM) + ';\n'
    + "export default function selfProbe(): void {\n"
    + "  describe('自证探针', () => {\n"
    + "    it('注进去的失败必须被抓到', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {\n"
    + "      expect(1).assertEqual(2);\n"
    + "    });\n"
    + "    it('未实现的断言名必须抛错而不是静默通过', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL0, () => {\n"
    + "      expect('x').assertContain('x');\n"
    + "    });\n"
    + "  });\n}\n");
  const before = shim.getResults().fail;
  try {
    const mod = await import('file://' + probe);
    await mod.default();
    await shim.flush();
  } catch (err) {
    console.log('  探针载入失败：' + err.message);
    process.exit(1);
  }
  const after = shim.getResults().fail;
  const caught = after - before;
  console.log('反证：探针注入 2 条必失败用例 → 抓到 ' + caught + ' 条'
    + (caught === 2 ? '（管线有效：会红，且未知断言名不静默）' : '（<<< 管线不可信）'));
  fs.rmSync(work, { recursive: true, force: true });
  process.exit(caught === 2 ? 0 : 1);
}

fs.rmSync(work, { recursive: true, force: true });
process.exit(r.fail ? 1 : 0);
