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

// 1b) 回顾海报生图代理（2026-11-11 新增能力） --------------------------------
// 未配置只让 /v1/image 回 503、端侧降级模板海报，不影响主链，所以是 WARN 不是阻断。
const imageKey = process.env.IMAGEGEN_API_KEY || '';
const imageSecret = process.env.IMAGEGEN_SECRET_KEY || '';
const imageModel = process.env.IMAGEGEN_MODEL || '';
if (imageKey.startsWith('bce-v3/') && imageModel) {
  ok('生图代理已配置（千帆 V2 API Key）');
} else if (imageKey.startsWith('sk-') && imageModel) {
  ok('生图代理已配置（阿里百炼 API Key）');
} else if (imageKey && imageSecret && imageModel) {
  warn('生图代理仍是旧版凭证', '旧版应用需先发布文生图服务，否则 error_code 6；建议改用千帆 V2 的 bce-v3/ALTAK-... API Key，无需勾选接口');
} else {
  warn('生图代理未配置', '/v1/image/generate 会回 503，端侧降级模板海报；主链不受影响');
}
// 安全结构闸门：订阅门禁必须在服务端实时校验，且入口必须挂鉴权与限流。
const imageRoute = read('src/routes/image.js');
const appIndex = read('src/index.js');
if (/subscriptionAllowsImage/.test(imageRoute) &&
    /app\.use\('\/v1\/image'[^\n]*authMiddleware[^\n]*rateLimitMiddleware/.test(appIndex)) {
  ok('/v1/image 订阅门禁 + 鉴权 + 限流在位');
} else {
  bad('/v1/image 门禁缺失', '生图成本高，必须服务端实时校验订阅并挂 authMiddleware / rateLimitMiddleware');
}

// 2) 收据校验必须是对表官方的本地 JWS 验签（D1/D3/D4 的根因） ----------------
// 现行方案：客户端上报 jwsPurchaseOrder/jwsSubscriptionStatus，服务端用
// Huawei CBG Root CA G2 证书链本地验签（官方「对返回结果验签」，沙盒/生产都通）。
// 判据用「正向结构」：验签模块必须有 x5c 链/ES256/根信任/OID 四要素，业务层必须 fail-closed。
const iap = read('src/services/iap.js');
const iapJws = read('src/services/iapJws.js');
const iapLocal = /verifyPurchaseReceipt/.test(iap) && /IAP_NOT_CONFIGURED/.test(iap);
const jwsVerifier = /x5c/.test(iapJws) && /ES256/.test(iapJws) &&
  /ROOT_MISMATCH/.test(iapJws) && /LEAF_CERT_OID/.test(iapJws);
if (iapLocal && jwsVerifier) {
  ok('IAP 收据走本地 JWS 验签（x5c 链+ES256+OID，fail-closed）');
} else {
  bad('IAP 校验结构不对', 'src/services/iap.js 或 iapJws.js 缺少本地 JWS 验签要素 ⇒ 假收据可能可换订阅与通行证');
}
if (process.env.IAP_APP_ID) {
  ok('IAP_APP_ID 已配置（收据 applicationId 比对）');
} else {
  bad('IAP_APP_ID 未配置', '收据的 applicationId 无从比对，跨应用收据可复用；未配置时 /v1/iap/verify 一律 503');
}
const rootCertPath = process.env.IAP_ROOT_CERT_PATH || join(ROOT, 'certs', 'RootCaG2Ecdsa.cer');
if (existsSync(rootCertPath)) {
  ok(`IAP 根证书在位（${rootCertPath.replace(ROOT + '/', '')}）`);
} else {
  bad('IAP 根证书缺失', `${rootCertPath} 不存在；从 https://pki.consumer.huawei.com/ca/cer/RootCaG2Ecdsa.cer 下载`);
}
// 沙盒/开发单不花钱：验签通过也不该发货。默认只认 environment=Production，
// 真机沙盒验收要显式开 IAP_ALLOW_SANDBOX=1——开着就不能当生产对外。
if (process.env.IAP_ALLOW_SANDBOX === '1') {
  warn('沙盒收据放行中', 'IAP_ALLOW_SANDBOX=1：非生产环境收据可换权益，仅供真机验收；正式对外前必须去掉这一行');
} else {
  ok('收据环境闸门收紧（只认 environment=Production）');
}

// 3) /v1/iap 两条入口各自的守门方式 -----------------------------------------
// /verify 用设备票据（内联 jwt.verify）；/notify 是华为推来的，不可能带设备票据，
// 官方 v3 通知体是 { jwsNotification }——与收据同一套 JWS 验签（D7 对表后的形态）。
const iapRoute = read('src/routes/iap.js');
if (/TOKEN_INVALID/.test(iapRoute) && /jwt\.verify/.test(iapRoute)) {
  ok('/v1/iap/verify 要求设备票据');
} else {
  bad('/v1/iap/verify 未校验设备票据', 'src/routes/iap.js 里找不到 token 校验，假收据可直接入库');
}
const iapNotify = read('src/services/iapNotify.js');
if (/verifyNotification\(/.test(iapRoute) && /jwsNotification/.test(iapRoute)) {
  ok('/v1/iap/notify 收 JWS 并验签（v3 契约）');
} else {
  bad('/v1/iap/notify 未验签', 'src/routes/iap.js 里找不到 verifyNotification/jwsNotification，任何人都能伪造续费/退款事件改用户权益');
}
if (/verifyJws\(/.test(iapNotify) && /notificationRequestId/.test(iapNotify)) {
  ok('/v1/iap/notify 复用 JWS 验签并按 notificationRequestId 幂等');
} else {
  bad('/v1/iap/notify 幂等缺失', 'src/services/iapNotify.js 必须验 JWS 且以 notificationRequestId 幂等，重推会重复改权益');
}

// 4) 设备激活不能信任客户端自报的 unionId（账号冒用） ----------------------
// 端侧登录后把 unionId 放进请求体；BFF 直接拿它建/取账号并签发设备票据。
// 只要知道他人 unionId，就能换到对方的票据与权益（含订阅/通行证）。
// 正解：端侧改传 Account Kit 的 idToken，服务端验签 + 校验 audience(Client ID)。
const device = read('src/routes/device.js');
if (/verifyHuaweiIdToken/.test(device)) {
  ok('设备激活校验华为 idToken（unionId 不再自报）');
} else {
  bad('设备激活信任客户端 unionId', 'unionId 直接取自 req.body ⇒ 账号可被冒用；' +
    '修法：端侧传 idToken，服务端验签并校验 audience');
}
if (process.env.HUAWEI_CLIENT_ID) {
  ok('HUAWEI_CLIENT_ID 已配置（idToken audience）');
} else {
  bad('HUAWEI_CLIENT_ID 未配置', 'idToken 无法校验 aud ⇒ 所有带身份票据的激活都会 401');
}

// 5) 数据库路径能否在容器/云函数里落地 ------------------------------------
const db = read('src/db.js');
if (/join\(__dirname,\s*'\.\.',\s*'data',\s*'youjing\.db'\)/.test(db) && !/process\.env\.DB_PATH/.test(db)) {
  warn('DB 路径硬编码', 'src/db.js 写死 ../data/youjing.db 且不读 DB_PATH；' +
    '上云（云函数/只读根文件系统）必须先支持环境变量或挂载卷');
} else {
  ok('DB 路径可配置');
}

// 6) Prompt/Schema 生成物是否在库且与 SOT 同步（hash 由 npm test 校验） ----
if (existsSync(join(ROOT, 'src', 'prompt', 'generated', 'manifest.json'))) {
  ok('Prompt/Schema 生成物在位（hash 由 npm test 校验）');
} else {
  bad('缺 Prompt/Schema 生成物', '先跑 npm run sync:prompt');
}

// 7) 若本机已在跑，顺手探一次 /health -------------------------------------
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
