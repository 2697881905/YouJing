/**
 * 收据校验（D1/D3 的根因）。
 *
 * 改前：`return { verified: true }`——任何伪造的 purchaseToken 都能换到订阅与通行证，
 * 并进一步兑换成真额度（D2/D4 利用链）。
 *
 * 现在的安全方向是 **fail-closed**：
 * - 未配置校验服务（`IAP_VERIFY_URL` / `IAP_APP_ID` / `IAP_VERIFY_TOKEN` 任一缺失）⇒ 一律拒绝。
 *   宁可拒收真实收据（可运维修复、用户重试），也绝不接受伪造收据（漏钱且不可追）。
 * - 配置了就把收据交给校验服务判：只有 HTTP 2xx **且** 响应体 `verified === true` 才算通过；
 *   超时、5xx、网络错、响应形状不对，全部按未通过处理（不抛异常、不放行）。
 *
 * 与华为真实接口的对表：`IAP_VERIFY_URL` 填**完整端点**，请求体是
 * `{ purchaseToken, productType, appId }` + `Authorization: Bearer <IAP_VERIFY_TOKEN>`，
 * 成功时返回 `{ "verified": true }`。这段是**我方与校验服务之间的契约**，
 * 接华为官方订单校验 API 时只需改本文件（端到端联调前不算已验）。
 */

const TIMEOUT_MS = 8000;

export function iapVerifierConfigured() {
  const url = process.env.IAP_VERIFY_URL || '';
  const appId = process.env.IAP_APP_ID || '';
  const token = process.env.IAP_VERIFY_TOKEN || '';
  return url.length > 0 && appId.length > 0 && token.length > 0;
}

/** 返回 { verified:boolean, reason?:string }。任何异常都不冒泡，一律视为未通过。 */
export async function verifyPurchase(purchaseToken, productType) {
  if (!purchaseToken || !productType) {
    return { verified: false, reason: 'MISSING_PARAMS' };
  }
  if (!iapVerifierConfigured()) {
    return { verified: false, reason: 'IAP_NOT_CONFIGURED' };
  }

  const url = process.env.IAP_VERIFY_URL;
  const appId = process.env.IAP_APP_ID;
  const token = process.env.IAP_VERIFY_TOKEN;
  try {
    const resp = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
      },
      body: JSON.stringify({ purchaseToken, productType, appId }),
      signal: AbortSignal.timeout(TIMEOUT_MS)
    });
    if (resp.status < 200 || resp.status >= 300) {
      return { verified: false, reason: `VERIFIER_HTTP_${resp.status}` };
    }
    const body = await resp.json();
    if (body && body.verified === true) {
      return { verified: true };
    }
    return { verified: false, reason: 'VERIFIER_REJECTED' };
  } catch (err) {
    return { verified: false, reason: 'VERIFIER_UNAVAILABLE' };
  }
}
