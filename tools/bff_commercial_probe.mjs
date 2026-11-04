/**
 * 商业化链路 · 真实服务器验收探针
 *
 * 为什么要它：bff/ 此前只被 `node --test` 用 `initDb(':memory:')` 装配成 in-process
 * express，**从未作为真实进程启动过**；`grep -rn iap bff/test` 零命中 = 付费路径零测试覆盖。
 * 本探针 import `src/index.js` 本体（含它真实的路由挂载顺序），用 HTTP 走一遍
 * 「激活 → 扣额度 → 付费墙 → 付费 → 高级额度 / 通行证 / 换设备 / 回调」。
 *
 * 成本：上游 LLM 由本机 stub 顶替，零真模型调用。
 * 隔离：由 tools/probe_bff_commercial.sh 拷出独立副本再跑，仓库与 bff/data 零写入。
 *
 * 退出码：0 = 所有必守行为成立且无支付守卫缺陷；1 = 有缺陷。
 */
import http from 'node:http';

const gates = [];
const defects = [];

/** 必守行为：付费之外的记账正确性，红了就是回归 */
function gate(name, cond, detail) {
  gates.push({ name, cond, detail });
  console.log(`${cond ? 'PASS' : 'FAIL'}  ${name}${detail ? ' — ' + detail : ''}`);
  return cond;
}

/** 支付守卫：条件成立表示「守卫不存在」，登记为缺陷 */
function guardAbsent(name, isAbsent, detail) {
  if (isAbsent) {
    defects.push({ name, detail });
    console.log(`DEFECT  ${name} — ${detail}`);
    return false;
  }
  console.log(`PASS  ${name}`);
  return true;
}

const stubCalls = [];
const upstream = http.createServer((req, res) => {
  let raw = '';
  req.on('data', (c) => { raw += c; });
  req.on('end', async () => {
    stubCalls.push(raw);
    const { validTrip } = await import('./test/fixtures/trip.js');
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      choices: [{ message: { content: JSON.stringify(validTrip()) } }],
      usage: { prompt_tokens: 1200, completion_tokens: 2400, model: 'probe-model' }
    }));
  });
});
await new Promise((r) => upstream.listen(0, '127.0.0.1', r));

// 收据校验对表官方后是**本地 JWS 验签**（无校验服务可桩）：把测试根证书交给真实进程，
// 用 fixtures 证书链现签「真收据」JWS——伪造（坏格式/坏签名）被拒、真 JWS 能买到订阅，
// 两半通路都在真实进程上验。测试链只在本探针进程内受信（生产默认信华为根证书）。
const { fileURLToPath } = await import('node:url');
process.env.IAP_ROOT_CERT_PATH = fileURLToPath(
  new URL('./test/fixtures/iap-test-root.cer', import.meta.url)
);
process.env.IAP_APP_ID = '6917619826312400726';
const { makeJws, purchaseOrderPayload, subscriptionStatusPayload, notificationPayload } =
  await import('./test/fixtures/jws.js');

process.env.LLM_BASE_URL = `http://127.0.0.1:${upstream.address().port}/v1`;
process.env.DEEPSEEK_API_KEY = 'probe-key-not-real';
process.env.JWT_SECRET = 'probe-secret';
process.env.LLM_MODEL = 'probe-model';
process.env.LLM_RESPONSE_FORMAT = 'json_object';
process.env.PORT = process.env.PROBE_PORT || '47811';

// IAP 通知验签：与收据同一套本地 JWS 验签（官方 v3：通知体 { jwsNotification }）。
// 「真通知」用 fixtures 证书链现签；**未验**：AGC 配好通知地址后的第一封真实回调。

const BASE = `http://127.0.0.1:${process.env.PORT}`;

// 真实进程启动：index.js 在 import 时就 app.listen
await import('./src/index.js');

async function waitHealth() {
  for (let i = 0; i < 60; i += 1) {
    try {
      const r = await fetch(`${BASE}/health`);
      if (r.ok) {
        const body = await r.json();
        // 健康检查必须真的查过库（db:'ok'），只回静态 status 不算数
        if (body.status === 'ok' && body.db === 'ok') return true;
      }
    } catch (e) {
      // 还没起来，继续等
    }
    await new Promise((r) => setTimeout(r, 100));
  }
  return false;
}

async function req(method, path, opts = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (opts.token) headers.Authorization = `Bearer ${opts.token}`;
  if (opts.signature) headers.Authorization = opts.signature;
  if (opts.key) headers['Idempotency-Key'] = opts.key;
  const resp = await fetch(`${BASE}${path}`, {
    method,
    headers,
    body: opts.raw || (opts.body ? JSON.stringify(opts.body) : undefined)
  });
  const text = await resp.text();
  let parsed = null;
  try {
    parsed = JSON.parse(text);
  } catch (e) {
    parsed = { _raw: text.slice(0, 200) };
  }
  return { status: resp.status, body: parsed, replayed: resp.headers.get('idempotency-replayed') };
}

const booted = await waitHealth();
gate('真实进程可启动并响应 /health', booted);
if (!booted) {
  defects.push({ name: 'BFF 起不来', detail: 'import src/index.js 后 6 秒内 /health 无响应' });
  upstream.close();
  process.exit(1);
}

const { richRequest } = await import('./test/fixtures/trip.js');
function planBody() {
  const p = richRequest();
  p.startDate = '2026-11-06';
  p.endDate = '2026-11-06';
  p.selectedSpots = (p.spots || []).map((s) => ({ spotId: s.id, priority: 'must' }));
  return p;
}

// ── 1. 设备激活（游客路径：不带 unionId） ─────────────────────────────
const act = await req('POST', '/v1/device/activate', { body: { deviceId: 'probe-device-a' } });
const tokenA = act.body && act.body.deviceToken;
gate('匿名设备激活拿到票据', act.status === 200 && !!tokenA, `status=${act.status}`);
gate('新设备赠 3 次', !!(act.body && act.body.entitlement && act.body.entitlement.giftRemaining === 3),
  `giftRemaining=${act.body && act.body.entitlement && act.body.entitlement.giftRemaining}`);

// ── 2. 鉴权中间件真的在守（正对照，防止把「探针没打到」读成「安全」） ──
const noAuth = await req('GET', '/v1/entitlement');
gate('无票据读权益被 401 拦下', noAuth.status === 401, `status=${noAuth.status}`);

// ── 3. 真实 HTTP 上的扣费与幂等 ───────────────────────────────────────
const g1 = await req('POST', '/v1/trip/generate', { token: tokenA, key: 'probe-k1', body: planBody() });
gate('首次生成 200 且落 trip', g1.status === 200 && !!(g1.body && g1.body.trip), `status=${g1.status}`);
gate('生成一次后 gift 3→2', !!(g1.body && g1.body.quota && g1.body.quota.giftRemaining === 2),
  `giftRemaining=${g1.body && g1.body.quota && g1.body.quota.giftRemaining} source=${g1.body && g1.body.quota && g1.body.quota.source}`);

const callsAfterFirst = stubCalls.length;
const g1r = await req('POST', '/v1/trip/generate', { token: tokenA, key: 'probe-k1', body: planBody() });
gate('同键重放带 Idempotency-Replayed', g1r.status === 200 && g1r.replayed === 'true',
  `status=${g1r.status} replayed=${g1r.replayed}`);
gate('重放没有二次打上游', stubCalls.length === callsAfterFirst,
  `上游调用数 ${callsAfterFirst}→${stubCalls.length}`);
gate('重放没有二次扣额度', !!(g1r.body && g1r.body.quota && g1r.body.quota.giftRemaining === 2),
  `giftRemaining=${g1r.body && g1r.body.quota && g1r.body.quota.giftRemaining}`);

await req('POST', '/v1/trip/generate', { token: tokenA, key: 'probe-k2', body: planBody() });
const g3 = await req('POST', '/v1/trip/generate', { token: tokenA, key: 'probe-k3', body: planBody() });
gate('三次用尽赠送额度', !!(g3.body && g3.body.quota && g3.body.quota.giftRemaining === 0),
  `giftRemaining=${g3.body && g3.body.quota && g3.body.quota.giftRemaining}`);

const g4 = await req('POST', '/v1/trip/generate', { token: tokenA, key: 'probe-k4', body: planBody() });
gate('额度用尽后 402 QUOTA_EXHAUSTED（付费墙可诚实到达）',
  g4.status === 402 && g4.body && g4.body.error === 'QUOTA_EXHAUSTED',
  `status=${g4.status} error=${g4.body && g4.body.error}`);

// ── 4. 付费守卫：伪造一张收据能否换来订阅（D1 已修：本地 JWS 验签 fail-closed） ──
const forgeSub = await req('POST', '/v1/iap/verify', {
  token: tokenA,
  body: {
    jwsPurchaseOrder: 'totally-forged-receipt-123',
    productType: 'subscription',
    productId: 'youjing_sub_monthly'
  }
});
const forgedAccepted = forgeSub.status === 200 && forgeSub.body && forgeSub.body.verified === true;
const sub = forgeSub.body && forgeSub.body.entitlement && forgeSub.body.entitlement.subscription;
gate('伪造订阅收据被校验服务拒绝', forgeSub.status === 200 && forgeSub.body.verified === false,
  `status=${forgeSub.status} verified=${forgeSub.body && forgeSub.body.verified}`);
guardAbsent('伪造收据不能换来订阅', forgedAccepted,
  `假 purchaseToken 直接拿到 subscription=${JSON.stringify(sub)}`);

const afterForge = await req('POST', '/v1/trip/generate', { token: tokenA, key: 'probe-k5', body: planBody() });
guardAbsent('伪造订阅不该兑换成真额度', afterForge.status === 200,
  `赠送已 0 的账号靠假收据又生成成功：status=${afterForge.status}`);
gate('伪造失败后额度仍为 0（真的没换到额度）', afterForge.status === 402,
  `status=${afterForge.status}`);

// ── 5. 通行证：伪造能否解锁导出墙与生成额度 ───────────────────────────
const forgePass = await req('POST', '/v1/iap/verify', {
  token: tokenA,
  body: { jwsPurchaseOrder: 'totally-forged-receipt-456', productType: 'pass', localTripId: 'local-trip-free' }
});
const passGranted = forgePass.status === 200 && forgePass.body && forgePass.body.passId === 'local-trip-free';
gate('伪造通行证收据被拒绝',
  forgePass.status === 200 && forgePass.body.verified === false,
  `status=${forgePass.status} verified=${forgePass.body && forgePass.body.verified}`);
guardAbsent('伪造收据不能换来行程通行证', passGranted,
  `passId=${forgePass.body && forgePass.body.passId}`);

const actC = await req('POST', '/v1/device/activate', { body: { deviceId: 'probe-device-c' } });
const tokenC = actC.body && actC.body.deviceToken;
for (let i = 0; i < 3; i += 1) {
  await req('POST', '/v1/trip/generate', { token: tokenC, key: `probe-c-clean-${i}`, body: planBody() });
}
const cExhausted = await req('POST', '/v1/trip/generate',
  { token: tokenC, key: 'probe-c-exhausted', body: planBody() });
gate('干净账号 C 的赠送已用尽（通行证测试的前提）',
  cExhausted.status === 402, `status=${cExhausted.status}`);

const forgePassC = await req('POST', '/v1/iap/verify', {
  token: tokenC,
  body: { jwsPurchaseOrder: 'totally-forged-receipt-789', productType: 'pass', localTripId: 'local-trip-free' }
});
gate('账号 C 的伪造通行证同样被拒', forgePassC.body && forgePassC.body.verified === false,
  `verified=${forgePassC.body && forgePassC.body.verified}`);

const withPass = await req('POST', '/v1/trip/generate', {
  token: tokenC, key: 'probe-k6', body: Object.assign(planBody(), { passId: 'local-trip-free' })
});
const pw = withPass.body && withPass.body.quota;
guardAbsent('伪造通行证不该买到无限生成额度',
  withPass.status === 200 && pw && pw.source === 'pass',
  `额度已尽的干净账号靠伪造 pass 拿到 source=${pw && pw.source} status=${withPass.status}`);
gate('伪造失败后账号 C 仍是 402', withPass.status === 402, `status=${withPass.status}`);

// ── 5b. 正对照：真收据（fixtures 证书链现签的订阅 JWS）必须能买到订阅并兑换成额度 ──
const actE = await req('POST', '/v1/device/activate', { body: { deviceId: 'probe-device-e' } });
const tokenE = actE.body && actE.body.deviceToken;
const realSubJws = makeJws(subscriptionStatusPayload());
const realSubToken = subscriptionStatusPayload().lastSubscriptionStatus.purchaseToken;
const realSub = await req('POST', '/v1/iap/verify', {
  token: tokenE,
  body: {
    jwsSubscriptionStatus: realSubJws,
    productType: 'subscription',
    productId: 'youjing_sub_monthly'
  }
});
gate('真收据通过校验并拿到订阅',
  realSub.status === 200 && realSub.body.verified === true &&
  !!(realSub.body.entitlement && realSub.body.entitlement.subscription &&
    realSub.body.entitlement.subscription.status === 'active'),
  `status=${realSub.status} subscription=${JSON.stringify(realSub.body && realSub.body.entitlement && realSub.body.entitlement.subscription)}`);

const realGen = await req('POST', '/v1/trip/generate', { token: tokenE, key: 'probe-e-real', body: planBody() });
gate('真订阅兑换成生成额度（source=subscription，且 quota 回传 subscription 快照）',
  realGen.status === 200 && realGen.body.quota.source === 'subscription' &&
  realGen.body.quota.subscription && realGen.body.quota.subscription.status === 'active',
  `status=${realGen.status} source=${realGen.body && realGen.body.quota && realGen.body.quota.source} ` +
  `subscription=${JSON.stringify(realGen.body && realGen.body.quota && realGen.body.quota.subscription)}`);

// ── 6. 赠送额度是否真的「终身不重置」 ─────────────────────────────────
const actB = await req('POST', '/v1/device/activate', { body: { deviceId: 'probe-device-b' } });
const giftB = actB.body && actB.body.entitlement && actB.body.entitlement.giftRemaining;
guardAbsent('换设备不该白送 3 次', giftB === 3,
  `新 deviceId 拿到 giftRemaining=${giftB}；/v1/device/activate 不带 unionId 就建 ` +
  'anon-<deviceId> 账号并赠 3 次，而 deviceId 由端侧 DeviceTokenStore 本地随机生成，' +
  '清数据或换机即重置 —— 与商业化方案 §2「注册赠 3 次（终身不重置）」冲突');

// ── 7. 上限口径与续费回调 ─────────────────────────────────────────────
const ent = await req('GET', '/v1/entitlement', { token: tokenA });
const cap = ent.body && ent.body.dailyCap;
const used = ent.body && ent.body.usedToday;
// D6 已修（2026-11-03）：口径从「20 次/天」改成「20 次/月」，与方案 §2 和付费页文案一致。
// 窗口本身在 HTTP 上看不出来，由 bff/test/quota-window.test.js 断言；这里只钉值。
gate('订阅档上限值应为 20（窗口=按月，见 quota-window.test.js）', cap === 20,
  `dailyCap=${cap} usedToday=${used}`);

// D7 已修（2026-11-03，2026-11-04 对表官方 v3）：通知体 { jwsNotification }，
// 与收据同一套本地 JWS 验签、按 notificationRequestId 幂等。
// 先证「拒收」（坏 JWS / 缺字段），再用真 JWS 证「到期真的让订阅失效」——只测拒收等于没测通路。
const unsigned = await req('POST', '/v1/iap/notify', {
  body: { notificationType: 'EXPIRE', purchaseToken: realSubToken, eventId: 'probe-unsigned' }
});
gate('不符合 v3 契约（缺 jwsNotification）的通知被拒绝', unsigned.status === 400,
  `status=${unsigned.status} error=${unsigned.body && unsigned.body.error}`);

const forgedNotify = await req('POST', '/v1/iap/notify', {
  body: { jwsNotification: 'forged.header.signature' }
});
gate('伪造的 jwsNotification 被验签拒绝（不能撤销别人的权益）', forgedNotify.status === 401,
  `status=${forgedNotify.status} error=${forgedNotify.body && forgedNotify.body.error}`);

const expireNotify = makeJws(notificationPayload({
  notificationType: 'EXPIRE',
  notificationSubtype: 'VOLUNTARY',
  notificationRequestId: 'probe-expire-signed',
  notificationMetaData: {
    environment: 'SANDBOX',
    applicationId: '6917619826312400726',
    packageName: 'com.youjing.app',
    type: 2,
    purchaseToken: realSubToken
  }
}));
const notify = await req('POST', '/v1/iap/notify', { body: { jwsNotification: expireNotify } });
const entAfterNotify = await req('GET', '/v1/entitlement', { token: tokenE });
gate('已验签的 EXPIRE 通知让订阅失效（真实进程、真 JWS）',
  notify.status === 200 && notify.body && notify.body.applied === true &&
  entAfterNotify.body && entAfterNotify.body.subscription === null,
  `status=${notify.status} applied=${notify.body && notify.body.applied} ` +
  `subscription=${JSON.stringify(entAfterNotify.body && entAfterNotify.body.subscription)}`);

const dupToken = await req('POST', '/v1/iap/verify', {
  token: tokenA,
  body: {
    jwsSubscriptionStatus: realSubJws,
    productType: 'subscription',
    productId: 'youjing_sub_yearly'
  }
});
gate('同一收据重复提交不把服务打成 500', dupToken.status < 500,
  `status=${dupToken.status} error=${dupToken.body && dupToken.body.error}`);

// ── 汇总 ──────────────────────────────────────────────────────────────
const passed = gates.filter((g) => g.cond).length;
console.log('\n──────── 商业化链路验收 ────────');
console.log(`必守行为 ${passed}/${gates.length} 通过；支付守卫缺陷 ${defects.length} 条；` +
  `上游 stub 真实调用 ${stubCalls.length} 次；LLM 花费 0`);
defects.forEach((d, i) => console.log(`  ${i + 1}. ${d.name}`));
upstream.close();
process.exit(defects.length || passed !== gates.length ? 1 : 0);
