/**
 * AGC 云函数部署自检（部署前跑一遍，避免到控制台才发现缺东西）。
 *
 * 检查项：
 *  1. 两个云函数（replanDay / pickSpots）文件齐全、handler 可加载、单测可跑（--test 时）；
 *  2. pickSpots 的 prompt 目录与 BFF 生成物 sha256 一致（提示词单源未漂移）；
 *  3. bff/.env 里 LLM 三件套齐全，并打印 AGC 控制台要配的环境变量映射（不回显密钥值）；
 *  4. 端侧配置（ApiConfig.REPLAN_URL / PickConfig.URL）是否还留着占位——部署后要回填 HTTP 触发器 URL。
 *
 * 用法：
 *   node tools/check_cloud_deploy.mjs          # 静态检查
 *   node tools/check_cloud_deploy.mjs --test   # 静态检查 + 两个云函数单测
 */
import { existsSync, readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { join, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const runTests = process.argv.includes('--test');
let failed = 0;

function check(ok, label, detail = '') {
  const mark = ok ? 'PASS' : 'FAIL';
  if (!ok) failed++;
  console.log(`[${mark}] ${label}${detail ? ' — ' + detail : ''}`);
}

function sha256File(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

const functions = [
  { name: 'replanDay', dir: join(ROOT, 'cloud', 'replanDay'), promptSynced: false },
  { name: 'pickSpots', dir: join(ROOT, 'cloud', 'pickSpots'), promptSynced: true }
];

for (const fn of functions) {
  console.log(`\n=== ${fn.name} ===`);

  const indexJs = join(fn.dir, 'index.js');
  const pkgPath = join(fn.dir, 'package.json');
  check(existsSync(indexJs), 'index.js 存在');
  check(existsSync(pkgPath), 'package.json 存在');
  check(existsSync(join(fn.dir, 'README.md')), 'README.md 存在（部署步骤/环境变量说明）');

  if (existsSync(pkgPath)) {
    const pkg = JSON.parse(readFileSync(pkgPath, 'utf8'));
    check(pkg.main === 'index.js', 'package.json main=index.js（AGC 入口约定）');
    check(!pkg.dependencies || Object.keys(pkg.dependencies).length === 0,
      '零依赖（AGC 包不含 node_modules）');
  }

  if (existsSync(indexJs)) {
    const probe = spawnSync('node', ['-e',
      `const m=require(${JSON.stringify(indexJs)});` +
      `if(typeof m.handler!=='function'){process.exit(3);}` +
      `console.log('ok');`], { encoding: 'utf8' });
    check(probe.status === 0 && probe.stdout.trim() === 'ok',
      'module.exports.handler 可加载且为函数',
      probe.status === 0 ? '' : (probe.stderr || `exit=${probe.status}`));
  }

  if (runTests) {
    const t = spawnSync('node', ['--test'], { cwd: fn.dir, encoding: 'utf8' });
    const tail = (t.stdout || '').split('\n').filter(l => /# (pass|fail)/.test(l)).join(' ');
    check(t.status === 0, '单测通过', tail || `exit=${t.status}`);
  }

  if (fn.promptSynced) {
    const pairs = [
      ['prompt/ai/PromptBuilder.js', 'src/prompt/generated/ai/PromptBuilder.js'],
      ['prompt/ai/TripSchema.js', 'src/prompt/generated/ai/TripSchema.js'],
      ['prompt/utils/DateUtils.js', 'src/prompt/generated/utils/DateUtils.js'],
      ['prompt/utils/TripLength.js', 'src/prompt/generated/utils/TripLength.js']
    ];
    for (const [cloudRel, bffRel] of pairs) {
      const cloudPath = join(fn.dir, cloudRel);
      const bffPath = join(ROOT, 'bff', bffRel);
      if (!existsSync(cloudPath) || !existsSync(bffPath)) {
        check(false, `prompt 同步缺失 ${cloudRel}`, '先跑 npm run sync:prompt（bff 目录）');
        continue;
      }
      check(sha256File(cloudPath) === sha256File(bffPath),
        `prompt 单源一致 ${cloudRel}`, relative(ROOT, bffPath));
    }
  }
}

console.log('\n=== 环境变量（AGC 控制台要配的映射；值不回显） ===');
const envPath = join(ROOT, 'bff', '.env');
if (!existsSync(envPath)) {
  check(false, 'bff/.env 存在', 'LLM 密钥的本地单源');
} else {
  const env = {};
  for (const line of readFileSync(envPath, 'utf8').split('\n')) {
    const m = /^([A-Z_]+)=(.*)$/.exec(line.trim());
    if (m) env[m[1]] = m[2];
  }
  const chatUrl = env.LLM_BASE_URL ? `${env.LLM_BASE_URL.replace(/\/$/, '')}/chat/completions` : '';
  check(Boolean(env.LLM_BASE_URL), 'LLM_BASE_URL 已配置', `→ AGC: LLM_CHAT_URL=${chatUrl}`);
  check(Boolean(env.DEEPSEEK_API_KEY), 'DEEPSEEK_API_KEY 已配置', '→ AGC: LLM_API_KEY=<同值>');
  check(Boolean(env.LLM_MODEL), 'LLM_MODEL 已配置', `→ AGC: LLM_MODEL=${env.LLM_MODEL || ''}`);
  console.log('→ AGC: YOUJING_REPLAN_TOKEN / YOUJING_PICK_TOKEN 需你自定并在 AGC 配置同值');
  console.log('→ AGC: 函数超时配 8s；入口函数名 handler（详见各 README）');
}

console.log('\n=== 端侧回填位 ===');
const apiConfig = readFileSync(join(ROOT, 'entry/src/main/ets/common/config/ApiConfig.ets'), 'utf8');
const replanUrl = /REPLAN_URL:\s*'([^']*)'/.exec(apiConfig)?.[1] || '';
if (replanUrl.length === 0) {
  check(false, 'ApiConfig.REPLAN_URL 非空', '部署 replanDay 后把 HTTP 触发器 URL 填到这里');
} else if (/192\.168\.|localhost|127\.0\.0\.1/.test(replanUrl)) {
  console.log(`[INFO] ApiConfig.REPLAN_URL 仍是本地占位（${replanUrl}）— 部署 replanDay 后回填云触发器 URL`);
} else {
  console.log(`[INFO] ApiConfig.REPLAN_URL=${replanUrl}`);
}
const pickConfig = readFileSync(
  join(ROOT, 'entry/src/main/ets/common/config/PickConfig.ets'), 'utf8');
const pickUrl = /URL:\s*'([^']*)'/.exec(pickConfig)?.[1] || '';
console.log(`[INFO] PickConfig.URL='${pickUrl || '(空)'}' — 部署 pickSpots 后把 HTTP 触发器 URL 填到这里`);

console.log('');
if (failed > 0) {
  console.error(`自检未通过：${failed} 项 FAIL。按上面 FAIL 项修复后再部署。`);
  process.exit(1);
}
console.log('自检通过：可以按 cloud/*/README.md 部署。');
