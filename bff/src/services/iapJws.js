/**
 * 华为 IAP Kit JWS 本地验签 —— 官方「对返回结果验签」契约（2026-09 版）。
 *
 * 为什么是本地验签而不是云侧 API：华为订单校验 REST API（order/lookup）按**交易号**查询、
 * 需要用 AGC 密钥管理私钥现签 JWT、且**不支持沙盒测试订单**；而 HarmonyOS NEXT 的
 * purchaseToken 相关数据本身就是 JWS——官方权益发放指南明确建议「客户端将 purchaseData
 * 发送至应用服务器，在应用服务器执行解码验签」。本地验签沙盒/生产都通，且零云侧依赖。
 *
 * JWS 结构（header.payload.signature，Base64URL）：
 * - header：{ alg: 'ES256'（固定）, typ: 'JWT'（固定）, x5c: [叶子, 中间, 根] }
 * - x5c 证书链用 Huawei CBG Root CA G2（bff/certs/RootCaG2Ecdsa.cer）做信任锚；
 *   中间证书必须由根签发、叶子必须由中间签发（签名 + 有效期）；
 * - 叶子证书必须含 OID 1.3.6.1.4.1.2011.2.415.1.1（防其他华为用途证书冒充）；
 * - 用叶子公钥对 signingInput 做 ES256 验签。JWS 的 ECDSA 签名是 r||s 原始拼接
 *   （64 字节），Node 用 dsaEncoding:'ieee-p1363' 直接吃。
 *
 * 作用域：/v1/iap/verify 的收据 JWS（jwsPurchaseOrder / jwsSubscriptionStatus）
 * 与 /v1/iap/notify 的服务端关键事件通知 JWS（jwsNotification，官方 v3 同一验签方式）。
 *
 * fail-closed：任何一步失败都返回 { ok:false, reason }，不抛异常、不放行。
 * 边界：未实现 CRL 吊销检查（Node 无内置 CRL；链签名 + 有效期 + OID + 根信任已挡住伪造，
 * 与官方 Java 示例允许的 SOFT_FAIL 口径一致；如需吊销检查另行接 PKI 服务）。
 */
import { readFileSync } from 'node:fs';
import { verify as cryptoVerify, X509Certificate } from 'node:crypto';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const DEFAULT_ROOT_CERT = join(HERE, '..', '..', 'certs', 'RootCaG2Ecdsa.cer');

/** 叶子证书必须携带的扩展 OID，DER 编码完整 TLV：06 0C 2B 06 01 04 01 8F 5B 02 83 1F 01 01 */
const LEAF_CERT_OID = Buffer.from([
  0x06, 0x0c, 0x2b, 0x06, 0x01, 0x04, 0x01, 0x8f, 0x5b, 0x02, 0x83, 0x1f, 0x01, 0x01
]);

const X5C_CHAIN_LENGTH = 3;

let rootCache = { path: '', cert: null };

function loadRootCert() {
  const path = process.env.IAP_ROOT_CERT_PATH || DEFAULT_ROOT_CERT;
  if (rootCache.path === path && rootCache.cert) return rootCache.cert;
  const cert = new X509Certificate(readFileSync(path));
  rootCache = { path, cert };
  return cert;
}

export function iapJwsConfigured() {
  try {
    loadRootCert();
    return true;
  } catch (err) {
    return false;
  }
}

function b64urlJson(segment) {
  return JSON.parse(Buffer.from(segment, 'base64url').toString('utf8'));
}

function certValidNow(cert, now) {
  const from = Date.parse(cert.validFrom);
  const to = Date.parse(cert.validTo);
  return !(now < from || now > to);
}

/**
 * 验签并解出 payload。返回 { ok:true, payload, header } 或 { ok:false, reason }。
 * reason 取值：MISSING_JWS / BAD_FORMAT / BAD_ALG / BAD_CHAIN / ROOT_MISMATCH /
 * CERT_EXPIRED / MISSING_OID / BAD_SIGNATURE / BAD_PAYLOAD
 */
export function verifyJws(jws) {
  if (typeof jws !== 'string' || jws.length === 0) {
    return { ok: false, reason: 'MISSING_JWS' };
  }
  const parts = jws.split('.');
  if (parts.length !== 3 || parts.some((p) => p.length === 0)) {
    return { ok: false, reason: 'BAD_FORMAT' };
  }
  let header;
  try {
    header = b64urlJson(parts[0]);
  } catch (err) {
    return { ok: false, reason: 'BAD_FORMAT' };
  }

  if (header.alg !== 'ES256' || header.typ !== 'JWT') {
    return { ok: false, reason: 'BAD_ALG' };
  }
  const x5c = header.x5c;
  if (!Array.isArray(x5c) || x5c.length !== X5C_CHAIN_LENGTH) {
    return { ok: false, reason: 'BAD_CHAIN' };
  }

  let leaf, inter;
  try {
    // x5c 顺序：叶子、中间、根（官方文档口径）
    leaf = new X509Certificate(Buffer.from(x5c[0], 'base64'));
    inter = new X509Certificate(Buffer.from(x5c[1], 'base64'));
    const chainRoot = new X509Certificate(Buffer.from(x5c[2], 'base64'));
    const trustedRoot = loadRootCert();
    if (!chainRoot.raw.equals(trustedRoot.raw)) {
      return { ok: false, reason: 'ROOT_MISMATCH' };
    }
  } catch (err) {
    return { ok: false, reason: 'BAD_CHAIN' };
  }

  const now = Date.now();
  for (const cert of [leaf, inter]) {
    if (!certValidNow(cert, now)) {
      return { ok: false, reason: 'CERT_EXPIRED' };
    }
  }
  if (!inter.verify(loadRootCert().publicKey) || !leaf.verify(inter.publicKey)) {
    return { ok: false, reason: 'BAD_CHAIN' };
  }
  if (leaf.raw.indexOf(LEAF_CERT_OID) < 0) {
    return { ok: false, reason: 'MISSING_OID' };
  }

  const signature = Buffer.from(parts[2], 'base64url');
  const signingInput = `${parts[0]}.${parts[1]}`;
  let ok;
  try {
    ok = cryptoVerify(
      'sha256',
      Buffer.from(signingInput, 'utf8'),
      { key: leaf.publicKey, dsaEncoding: 'ieee-p1363' },
      signature
    );
  } catch (err) {
    return { ok: false, reason: 'BAD_SIGNATURE' };
  }
  if (!ok) return { ok: false, reason: 'BAD_SIGNATURE' };

  let payload;
  try {
    payload = b64urlJson(parts[1]);
  } catch (err) {
    return { ok: false, reason: 'BAD_PAYLOAD' };
  }
  if (!payload || typeof payload !== 'object') {
    return { ok: false, reason: 'BAD_PAYLOAD' };
  }
  return { ok: true, payload };
}
