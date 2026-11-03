#!/usr/bin/env node
/**
 * 上线前自检：把「部署这个 BFF 之前必须成立的事」变成可执行的闸门。
 *
 * 为什么要有它：本轮验收已经证明 BFF 在**功能**上能跑通（激活→扣额度→付费墙→付费），
 * 但**安全与合规**上还不能上线（见 Docs/analysis/商业化链路真实验收-2026-11-03.md 的 D1–D8）。
 * 这份自检只回答一件事：**现在把它暴露到公网，会不会漏钱 / 泄密**。
 * 它故意在当前状态下返回非 0——红是真话，不是坏掉的闸门。
 *
 * 用法：cd bff && npm run preflight
 * 退出码：0 = 可以对外提供服务；1 = 有阻断项（逐条打印）。
 */
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import dotenv from 'dotenv';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');
dotenv.config({ path: join(ROOT, '.env') });

const fails = [];
const warns = [];
const oks = [];

function read(rel) {
  return readFileSync(join(ROOT, rel), 'utf8');
}

function ok(name) { oks.push(name); console.log(`PASS  ${name}`); }
function bad(name, why) { fails.push(`${name}：${why}`); console.log(`FAIL  ${name} — ${why}`); }
function warn(name, why) { warns.push(`${name}：${why}`); console.log(`WARN  ${name} — ${why}`); }

// 1) 密钥不能是示例值/缺省值 ------------------------------------------------
const secret = process.env.JWT_SECRET || '';
if (secret.length === 0) {
  bad('JWT_SECRET 未配置', 'auth.js 会退回硬编码开发密钥，任何人都能自签设备票据');
} else if (secret === 'youjing-bff-dev-secret' || secret === 'youjing-bff-secret-change-in-prod') {
  bad('JWT_SECRET 仍是示例值', `当前值 "${secret}"，公开仓库里人人可见`);
} else if (secret.length < 24) {
  warn('JWT_SECRET 偏短', `长度 ${secret.length}，建议 ≥32 字节随机串`);
} else {
  ok('JWT_SECRET 已换成独立密钥');
}

const llmKey = process.env.DEEPSEEK_API_KEY || '';
if (llmKey.length === 0 || llmKey === 'sk-your-key-here') {
  bad('DEEPSEEK_API_KEY 未配置', 'LLM 代理会直接 500');
} else {
  ok('DEEPSEEK_API_KEY 已配置');
}

// 2) 支付校验不能还是桩（D1/D3/D4 的根因） --------------------------------
const iap = read('src/services/iap.js');
if (/return \{ verified: true/.test(iap)) {
  bad('IAP 校验仍是恒真桩', 'src/services/iap.js 无条件返回 verified:true ⇒ 假收据可换订阅与通行证');
} else {
  ok('IAP 校验已实现真实校验');
}

// 3) /v1/iap 两条入口各自的守门方式 -----------------------------------------
// /verify 用设备票据（内联 jwt.verify）；/notify 是华为推来的，不可能带设备票据，
// 它必须验 RSA 签名（D7 修复后的形态）。以前这里查"整条 /v1/iap 挂没挂 authMiddleware"，
// 那个判据会逼着人把华为回调也挂上票据、反而永远收不到通知。
const iapRoute = read('src/routes/iap.js');
if (/TOKEN_INVALID/.test(iapRoute) && /jwt\.verify/.test(iapRoute)) {
  ok('/v1/iap/verify 要求设备票据');
} else {
  bad('/v1/iap/verify 未校验设备票据', 'src/routes/iap.js 里找不到 token 校验，假收据可直接入库');
}
if (/notifySignatureOk\(/.test(iapRoute) && /IAP_NOTIFY_PUBLIC_KEY/.test(iapRoute)) {
  ok('/v1/iap/notify 走签名校验');
} else {
  bad('/v1/iap/notify 未验签', '任何人都能伪造续费/退款事件改用户权益');
}
if (process.env.IAP_NOTIFY_PUBLIC_KEY) {
  ok('IAP_NOTIFY_PUBLIC_KEY 已配置（值本身需与 AGC 控制台核对）');
} else {
  bad('IAP_NOTIFY_PUBLIC_KEY 未配置', 'notify 会按 fail-closed 返回 503，到期与退款无法生效');
}

// 4) 数据库路径能否在容器/云函数里落地 ------------------------------------
const db = read('src/db.js');
if (/join\(__dirname,\s*'\.\.',\s*'data',\s*'youjing\.db'\)/.test(db) && !/process\.env\.DB_PATH/.test(db)) {
  warn('DB 路径硬编码', 'src/db.js 写死 ../data/youjing.db 且不读 DB_PATH；' +
    '上云（云函数/只读根文件系统）必须先支持环境变量或挂载卷');
} else {
  ok('DB 路径可配置');
}

// 5) Prompt/Schema 生成物是否在库且与 SOT 同步（hash 由 npm test 校验） ----
if (existsSync(join(ROOT, 'src', 'prompt', 'generated', 'manifest.json'))) {
  ok('Prompt/Schema 生成物在位（hash 由 npm test 校验）');
} else {
  bad('缺 Prompt/Schema 生成物', '先跑 npm run sync:prompt');
}

// 6) 若本机已在跑，顺手探一次 /health -------------------------------------
const port = process.env.PORT || 3000;
try {
  const resp = await fetch(`http://127.0.0.1:${port}/health`, { signal: AbortSignal.timeout(1200) });
  if (resp.ok) ok(`本地实例健康（:${port}/health）`);
  else warn('本地实例 /health 非 200', `status=${resp.status}`);
} catch (e) {
  console.log(`INFO  本地 :${port} 没有在跑的服务（跳过健康探测）`);
}

console.log('\n──────────── 上线自检 ────────────');
console.log(`通过 ${oks.length} · 警告 ${warns.length} · 阻断 ${fails.length}`);
if (fails.length > 0) {
  console.log('阻断项（修完再谈对外提供服务）：');
  fails.forEach((f, i) => console.log(`  ${i + 1}. ${f}`));
  process.exit(1);
}
console.log('可以对外提供服务（警告项仍需人工确认）。');
process.exit(0);
