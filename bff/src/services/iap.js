/**
 * 收据校验（D1/D3 的根因）。**已对表华为官方**（2026-09 版 IAP Kit 文档）。
 *
 * 改前：`return { verified: true }`——任何伪造的 purchaseToken 都能换到订阅与通行证（D1）。
 * 第一次收口：fail-closed 远端校验服务（IAP_VERIFY_URL 契约），但该服务本身不存在，
 * 且官方 order/lookup 按交易号查询、要 AGC 私钥现签 JWT、**不支持沙盒订单**。
 *
 * 现行方案（官方推荐架构）：HarmonyOS NEXT 的购买数据本身就是 JWS——客户端把
 * `jwsPurchaseOrder`（订单）/`jwsSubscriptionStatus`（订阅状态）上报，服务端用
 * Huawei CBG Root CA G2 证书链本地验签（见 iapJws.js），再对 payload 做业务校验：
 * - applicationId 必须等于 IAP_APP_ID（防他人应用的真收据跨应用复用）；
 * - productId/productType 必须与请求的商品一致（防低买高报——amount 由 requested 决定）；
 * - 订单未被撤销（purchaseOrderRevocationReasonCode 为空，官方口径：为空代表购买成功）；
 * - 订阅状态 status='1'（生效中）。
 *
 * fail-closed 不变：根证书未就位、验签失败、payload 形状不对，一律拒绝。
 * 环境闸门：默认只认 environment=Production 的收据。沙盒/开发单不花钱，
 * 生产放行等于免费发权益；真机沙盒验收时显式设 IAP_ALLOW_SANDBOX=1 才收非生产单。
 */

import { verifyJws, iapJwsConfigured } from './iapJws.js';

export function iapVerifierConfigured() {
  return iapJwsConfigured() && (process.env.IAP_APP_ID || '').length > 0;
}

/**
 * 收据环境闸门。缺字段按「非生产」处理（fail-closed）。
 * 官方枚举大小写未与真实收据对表过，故用大小写不敏感比较。
 */
export function environmentAllowed(env) {
  const value = typeof env === 'string' ? env.trim().toLowerCase() : '';
  if (value === 'production' || value === 'prod') return true;
  return process.env.IAP_ALLOW_SANDBOX === '1';
}

/** 订单 JWS（PurchaseOrderPayload）公共校验：返回 null 或拒绝原因 */
function checkOrderPayload(p, appId, expectedProductId, expectedProductType) {
  if (p.applicationId !== appId) return 'APP_MISMATCH';
  if (!environmentAllowed(p.environment)) return 'NON_PRODUCTION_ENVIRONMENT';
  if (expectedProductId && p.productId !== expectedProductId) return 'PRODUCT_MISMATCH';
  if (expectedProductType && String(p.productType) !== expectedProductType) {
    return 'PRODUCT_TYPE_MISMATCH';
  }
  // 官方：purchaseOrderRevocationReasonCode 非空代表订单已撤销/退款
  if (p.purchaseOrderRevocationReasonCode !== undefined &&
    p.purchaseOrderRevocationReasonCode !== null && p.purchaseOrderRevocationReasonCode !== '') {
    return 'RECEIPT_REVOKED';
  }
  if (typeof p.purchaseToken !== 'string' || p.purchaseToken.length === 0) {
    return 'MISSING_TOKEN';
  }
  return null;
}

/**
 * 验证收据。返回 { verified:boolean, reason?:string, receipt?:{...} }。
 * receipt.purchaseToken 是华为签发的权威购买令牌（入库幂等键），不采信客户端裸传值。
 */
export async function verifyPurchaseReceipt({ jwsPurchaseOrder, jwsSubscriptionStatus, productType, requestedProductId }) {
  if (!iapVerifierConfigured()) {
    return { verified: false, reason: 'IAP_NOT_CONFIGURED' };
  }
  const appId = process.env.IAP_APP_ID;

  if (productType === 'pass') {
    // 通行证 = 非消耗型商品（productType '1'），必须给订单 JWS
    const r = verifyJws(jwsPurchaseOrder);
    if (!r.ok) return { verified: false, reason: 'JWS_' + r.reason };
    const reject = checkOrderPayload(r.payload, appId, 'youjing_pass', '1');
    if (reject) return { verified: false, reason: reject };
    return {
      verified: true,
      receipt: {
        purchaseToken: r.payload.purchaseToken,
        purchaseOrderId: r.payload.purchaseOrderId,
        productId: r.payload.productId,
        environment: r.payload.environment
      }
    };
  }

  if (productType === 'subscription') {
    // 订阅：优先订阅状态 JWS（官方订阅发货以 SubGroupStatusPayload 为准），订单 JWS 可交叉
    if (typeof jwsSubscriptionStatus === 'string' && jwsSubscriptionStatus.length > 0) {
      const r = verifyJws(jwsSubscriptionStatus);
      if (!r.ok) return { verified: false, reason: 'JWS_' + r.reason };
      const s = r.payload;
      if (s.applicationId !== appId) return { verified: false, reason: 'APP_MISMATCH' };
      if (!environmentAllowed(s.environment)) {
        return { verified: false, reason: 'NON_PRODUCTION_ENVIRONMENT' };
      }
      const last = s.lastSubscriptionStatus;
      if (!last || typeof last !== 'object') return { verified: false, reason: 'MISSING_SUB_STATUS' };
      // status：1 生效中 / 2 已到期 / 3 尝试扣费 / 5 撤销 —— 只有效中才发权益
      if (String(last.status) !== '1') return { verified: false, reason: 'SUB_NOT_ACTIVE' };
      if (typeof last.purchaseToken !== 'string' || last.purchaseToken.length === 0) {
        return { verified: false, reason: 'MISSING_TOKEN' };
      }
      if (last.lastPurchaseOrder) {
        const reject = checkOrderPayload(
          last.lastPurchaseOrder, appId, requestedProductId, null);
        if (reject) return { verified: false, reason: reject };
      }
      return {
        verified: true,
        receipt: {
          purchaseToken: last.purchaseToken,
          purchaseOrderId: last.lastPurchaseOrder?.purchaseOrderId,
          productId: last.lastPurchaseOrder?.productId ?? requestedProductId,
          environment: s.environment
        }
      };
    }

    // 只给订单 JWS：自动续期订阅商品 productType='2'
    const r = verifyJws(jwsPurchaseOrder);
    if (!r.ok) return { verified: false, reason: 'JWS_' + r.reason };
    const reject = checkOrderPayload(r.payload, appId, requestedProductId, '2');
    if (reject) return { verified: false, reason: reject };
    return {
      verified: true,
      receipt: {
        purchaseToken: r.payload.purchaseToken,
        purchaseOrderId: r.payload.purchaseOrderId,
        productId: r.payload.productId,
        environment: r.payload.environment
      }
    };
  }

  return { verified: false, reason: 'UNSUPPORTED_PRODUCT_TYPE' };
}
