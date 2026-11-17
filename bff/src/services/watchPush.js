/**
 * Push Kit 服务端下发（穿戴推送，离线缓存由 Push Kit 负责）。
 *
 * 配置（AGC 开通 Push Kit 后由运维填到 bff/.env，容器需重建才生效）：
 *   PUSH_CLIENT_ID      AGC 应用 Client ID（与 APP ID 同值）
 *   PUSH_CLIENT_SECRET  AGC 应用 Client Secret
 *
 * fail-closed：未配置时明确返回 NOT_CONFIGURED，**不假装推送成功**。
 * 卡/决策的落库不受推送失败影响——BFF 只报告 pushed/sent。
 *
 * 注：接口形状按 HarmonyOS Push Kit REST（messages:send + data 消息）实现；
 * AGC 开通后需用真实凭证跑一次 G0-N-e 核对返回码与 endpoint（见探针报告）。
 */

const DEFAULT_OAUTH_URL = 'https://oauth-login.cloud.huawei.com/oauth2/v3/token';
const DEFAULT_PUSH_URL = 'https://push-api.cloud.huawei.com/v1';
const TIMEOUT_MS = 8000;
const PUSH_SUCCESS_CODE = '80000000';

let tokenCache = { clientId: '', token: '', at: 0 };

export function pushConfigured() {
  return (process.env.PUSH_CLIENT_ID || '').length > 0 &&
    (process.env.PUSH_CLIENT_SECRET || '').length > 0;
}

async function accessToken() {
  const clientId = process.env.PUSH_CLIENT_ID || '';
  const clientSecret = process.env.PUSH_CLIENT_SECRET || '';
  if (clientId.length === 0 || clientSecret.length === 0) {
    return { ok: false, reason: 'NOT_CONFIGURED', token: '' };
  }
  if (tokenCache.clientId === clientId && tokenCache.token.length > 0 &&
    Date.now() - tokenCache.at < 50 * 60 * 1000) {
    return { ok: true, reason: '', token: tokenCache.token };
  }
  const url = process.env.PUSH_OAUTH_URL || DEFAULT_OAUTH_URL;
  const body = new URLSearchParams({
    grant_type: 'client_credentials',
    client_id: clientId,
    client_secret: clientSecret
  });
  try {
    const resp = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body,
      signal: AbortSignal.timeout(TIMEOUT_MS)
    });
    const json = await resp.json().catch(() => ({}));
    if (!resp.ok || typeof json.access_token !== 'string' || json.access_token.length === 0) {
      console.warn(`[watch-push] 取 access token 失败 http=${resp.status}`);
      return { ok: false, reason: 'OAUTH_FAILED', token: '' };
    }
    tokenCache = { clientId, token: json.access_token, at: Date.now() };
    return { ok: true, reason: '', token: json.access_token };
  } catch (err) {
    console.warn(`[watch-push] 取 access token 异常: ${err.message}`);
    return { ok: false, reason: 'OAUTH_UNAVAILABLE', token: '' };
  }
}

/**
 * 向一组穿戴 push token 发 data 消息。
 * data 只放 cardId/type（小体积）；手表收到后回 BFF 拉全卡。
 */
export async function pushDataToTokens(tokens, data) {
  if (!Array.isArray(tokens) || tokens.length === 0) {
    return { ok: true, sent: 0, reason: 'NO_TOKEN' };
  }
  const auth = await accessToken();
  if (!auth.ok) {
    return { ok: false, sent: 0, reason: auth.reason };
  }
  const clientId = process.env.PUSH_CLIENT_ID || '';
  const url = `${process.env.PUSH_API_URL || DEFAULT_PUSH_URL}/${clientId}/messages:send`;
  try {
    const resp = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${auth.token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        validate_only: false,
        message: {
          data: JSON.stringify(data),
          token: tokens
        }
      }),
      signal: AbortSignal.timeout(TIMEOUT_MS)
    });
    const json = await resp.json().catch(() => ({}));
    if (!resp.ok || json.code !== PUSH_SUCCESS_CODE) {
      console.warn(`[watch-push] 下发失败 http=${resp.status} code=${json.code || '?'}`);
      return { ok: false, sent: 0, reason: 'PUSH_FAILED', http: resp.status, code: json.code || '' };
    }
    return { ok: true, sent: tokens.length, reason: '' };
  } catch (err) {
    console.warn(`[watch-push] 下发异常: ${err.message}`);
    return { ok: false, sent: 0, reason: 'PUSH_UNAVAILABLE' };
  }
}

function watchTokens(db, accountId) {
  return db.prepare(
    "SELECT push_token FROM watch_device WHERE account_id = ? AND push_token IS NOT NULL AND push_token <> ''"
  ).all(accountId).map((row) => row.push_token);
}

export async function pushCardToAccount(db, accountId, card) {
  const tokens = watchTokens(db, accountId);
  return pushDataToTokens(tokens, { type: 'watch-card', cardId: card.cardId, ts: Date.now() });
}

export async function pushWithdrawToAccount(db, accountId, cardId) {
  const tokens = watchTokens(db, accountId);
  return pushDataToTokens(tokens, { type: 'watch-withdraw', cardId, ts: Date.now() });
}

/** 仅供测试：清空 access token 缓存 */
export function resetPushTokenCache() {
  tokenCache = { clientId: '', token: '', at: 0 };
}
