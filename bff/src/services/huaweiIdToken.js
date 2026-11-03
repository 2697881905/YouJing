/**
 * 华为 Account Kit idToken 服务端验签（D10 的正解）。
 *
 * 官方口径（2026-11-03 核对）：
 * - 发现文档 https://oauth-login.cloud.huawei.com/.well-known/openid-configuration
 *   给出 issuer=https://accounts.huawei.com、jwks_uri=https://oauth-login.cloud.huawei.com/oauth2/v3/certs、
 *   签名算法 RS256/PS256；
 * - 本地验签（商用推荐）：用 kid 找 JWKS 公钥验签，再校验 iss、aud=Client ID、exp；
 * - **sub 就是 unionId**（官方示例：验证通过后用 payload.sub 作为用户唯一标识）；
 * - 华为另有 /oauth2/v3/tokeninfo 在线接口，但官方明示只用于调试，商用必须本地验签。
 *
 * 配置（部署时填）：
 *   HUAWEI_CLIENT_ID   AGC 应用的 Client ID（aud 必须等于它）
 *   HUAWEI_JWKS_URL    可选，默认官方 JWKS
 *   HUAWEI_ISSUER      可选，默认 https://accounts.huawei.com
 *
 * fail-closed：未配置 Client ID、JWKS 取不到、kid 找不到、签名/aud/iss/exp 任一不过，一律返回 ok:false。
 */
import { constants, createPublicKey, createVerify } from 'node:crypto';

const DEFAULT_ISSUER = 'https://accounts.huawei.com';
const DEFAULT_JWKS_URL = 'https://oauth-login.cloud.huawei.com/oauth2/v3/certs';
const JWKS_TTL_MS = 10 * 60 * 1000;
const JWKS_TIMEOUT_MS = 5000;

let jwksCache = { url: '', keys: [], at: 0 };

export function huaweiIdTokenConfigured() {
  return (process.env.HUAWEI_CLIENT_ID || '').length > 0;
}

function decodeJsonPart(part) {
  return JSON.parse(Buffer.from(part, 'base64url').toString('utf8'));
}

function findKey(keys, kid) {
  return keys.find((key) => key.kid === kid && key.kty === 'RSA');
}

async function loadJwks(force = false) {
  const url = process.env.HUAWEI_JWKS_URL || DEFAULT_JWKS_URL;
  if (!force && jwksCache.url === url && Date.now() - jwksCache.at < JWKS_TTL_MS && jwksCache.keys.length > 0) {
    return jwksCache.keys;
  }
  const resp = await fetch(url, { signal: AbortSignal.timeout(JWKS_TIMEOUT_MS) });
  if (!resp.ok) {
    throw new Error(`JWKS HTTP ${resp.status}`);
  }
  const body = await resp.json();
  const keys = Array.isArray(body.keys) ? body.keys : [];
  if (keys.length === 0) {
    throw new Error('JWKS 响应没有 keys');
  }
  jwksCache = { url, keys, at: Date.now() };
  return keys;
}

/**
 * @returns {Promise<{ok: boolean, unionId?: string, reason?: string}>}
 */
export async function verifyHuaweiIdToken(idToken) {
  const clientId = process.env.HUAWEI_CLIENT_ID || '';
  if (clientId.length === 0) {
    return { ok: false, reason: 'NOT_CONFIGURED' };
  }
  if (typeof idToken !== 'string' || idToken.length === 0) {
    return { ok: false, reason: 'MISSING_TOKEN' };
  }
  const parts = idToken.split('.');
  if (parts.length !== 3) {
    return { ok: false, reason: 'MALFORMED' };
  }

  let header;
  let payload;
  try {
    header = decodeJsonPart(parts[0]);
    payload = decodeJsonPart(parts[1]);
  } catch (err) {
    return { ok: false, reason: 'MALFORMED' };
  }

  // 只接受 JWKS 支持的两种非对称算法；拒绝 none/HS*（防止算法混淆）。
  if (header.alg !== 'RS256' && header.alg !== 'PS256') {
    return { ok: false, reason: 'BAD_ALG' };
  }
  if (typeof header.kid !== 'string' || header.kid.length === 0) {
    return { ok: false, reason: 'NO_KID' };
  }

  let keys;
  try {
    keys = await loadJwks();
  } catch (err) {
    return { ok: false, reason: 'JWKS_UNAVAILABLE' };
  }
  let jwk = findKey(keys, header.kid);
  if (jwk === undefined) {
    // 华为轮换公钥时，缓存里会短暂找不到新 kid。强制刷新一次再判，
    // 否则所有新签发的 idToken 会在这 10 分钟缓存窗口里被 401。
    try {
      keys = await loadJwks(true);
    } catch (err) {
      return { ok: false, reason: 'JWKS_UNAVAILABLE' };
    }
    jwk = findKey(keys, header.kid);
    if (jwk === undefined) {
      return { ok: false, reason: 'KID_NOT_FOUND' };
    }
  }

  let key;
  try {
    key = createPublicKey({ key: jwk, format: 'jwk' });
  } catch (err) {
    return { ok: false, reason: 'BAD_JWK' };
  }

  const signingInput = Buffer.from(`${parts[0]}.${parts[1]}`);
  const signature = Buffer.from(parts[2], 'base64url');
  let signatureOk = false;
  try {
    const verifier = createVerify('RSA-SHA256');
    verifier.update(signingInput);
    if (header.alg === 'PS256') {
      signatureOk = verifier.verify({
        key,
        padding: constants.RSA_PKCS1_PSS_PADDING,
        saltLength: constants.RSA_PSS_SALTLEN_DIGEST
      }, signature);
    } else {
      signatureOk = verifier.verify(key, signature);
    }
  } catch (err) {
    signatureOk = false;
  }
  if (!signatureOk) {
    return { ok: false, reason: 'BAD_SIGNATURE' };
  }

  const now = Math.floor(Date.now() / 1000);
  if (typeof payload.exp !== 'number' || payload.exp <= now) {
    return { ok: false, reason: 'EXPIRED' };
  }
  if (payload.iss !== (process.env.HUAWEI_ISSUER || DEFAULT_ISSUER)) {
    return { ok: false, reason: 'BAD_ISSUER' };
  }
  const audiences = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
  if (audiences.indexOf(clientId) < 0) {
    return { ok: false, reason: 'BAD_AUDIENCE' };
  }
  if (typeof payload.sub !== 'string' || payload.sub.length === 0) {
    return { ok: false, reason: 'NO_SUB' };
  }
  return { ok: true, unionId: payload.sub };
}

/** 仅供测试：清空 JWKS 缓存 */
export function resetJwksCache() {
  jwksCache = { url: '', keys: [], at: 0 };
}
