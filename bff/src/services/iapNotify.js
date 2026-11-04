/**
 * 华为 IAP 服务端关键事件通知（官方 v3 契约，2026-09 版）→ 权益变更。
 *
 * 对表结果：HarmonyOS NEXT 的通知体是 `{ jwsNotification }`——对 NotificationPayload
 * 签名的 JWS，验签方式与订单收据完全一致（x5c 证书链 + Huawei CBG Root CA G2 + ES256，
 * 见 iapJws.js）。**旧的 Authorization:RSA 签名头 / IAP_NOTIFY_PUBLIC_KEY 契约作废**。
 *
 * 改前 `/v1/iap/notify` 只 console.log 后回 200，到期、退款、续费全部黑洞（D7）。
 * 两条安全边界：
 * 1) **验签**：`jwsNotification` 验签失败一律 401，根证书未配置 503（fail-closed）——
 *    这个端点能撤销别人的付费权益，宁拒不收。
 * 2) **未知事件不改权益**：notificationType/subtype 认不出的只落库、回 200（避免无限重推）。
 *
 * 官方 payload 形态：
 * { notificationType, notificationSubtype?, notificationRequestId, notificationVersion:'v3',
 *   signedTime, notificationMetaData: { environment, applicationId, packageName, type,
 *   purchaseToken, purchaseOrderId?, currentProductId?, subGroupId?, ... } }
 * 幂等键 = notificationRequestId（官方唯一请求 ID）；purchaseToken 从 metaData 取。
 *
 * 边界（官方口径）：通知只是状态变化的提示，可能迟到/乱序/重发；
 * 认知顺序 = 先验签、再幂等、后按类别改权益，类别外的只记录不动作。
 */
import { verifyJws, iapJwsConfigured } from './iapJws.js';

const RENEW_MONTHS = (productId) => (productId === 'youjing_sub_yearly' ? 12 : 1);

/**
 * 通知归类。返回 { kind, subtype }。
 * kind ∈ renew / expire / refund / renew_status / renew_time / test / unknown
 */
export function classifyNotification(p) {
  const type = typeof p?.notificationType === 'string' ? p.notificationType.trim().toUpperCase() : '';
  const subtype = typeof p?.notificationSubtype === 'string' ? p.notificationSubtype.trim().toUpperCase() : '';
  switch (type) {
    case 'DID_NEW_TRANSACTION':
      // INITIAL_BUY / DID_RENEW / RESTORE / BILLING_RECOVERY / UPGRADE 都意味着订阅/订单生效或续期
      return { kind: 'renew', subtype };
    case 'EXPIRE':
      return { kind: 'expire', subtype };
    case 'REVOKE':
      return { kind: 'refund', subtype };
    case 'DID_CHANGE_RENEWAL_STATUS':
      return { kind: 'renew_status', subtype };
    case 'RENEWAL_TIME_MODIFIED':
      return { kind: 'renew_time', subtype };
    case 'TEST':
      return { kind: 'test', subtype };
    default:
      return { kind: 'unknown', subtype };
  }
}

/** 通知 JWS 验签。返回 { ok, payload } 或 { ok:false, reason }（NOT_CONFIGURED 视为部署态） */
export function verifyNotification(jws) {
  if (!iapJwsConfigured()) return { ok: false, reason: 'NOT_CONFIGURED' };
  const r = verifyJws(jws);
  if (!r.ok) return { ok: false, reason: r.reason };
  const p = r.payload;
  if (!p || typeof p.notificationRequestId !== 'string' || p.notificationRequestId.length === 0 ||
    !p.notificationMetaData || typeof p.notificationMetaData !== 'object') {
    return { ok: false, reason: 'BAD_PAYLOAD' };
  }
  return { ok: true, payload: p };
}

/**
 * 应用一条已验签的通知。返回 { applied, kind, subtype, reason }。
 * 幂等键先落库：同一 notificationRequestId 第二次进来直接 replayed，不再改权益。
 */
export function applyNotification(db, payload) {
  const eventId = payload.notificationRequestId;
  const { kind, subtype } = classifyNotification(payload);
  const meta = payload.notificationMetaData;
  const purchaseToken = typeof meta.purchaseToken === 'string' ? meta.purchaseToken : '';

  const seen = db.prepare('SELECT 1 FROM iap_notify_event WHERE event_id = ?').get(eventId);
  if (seen) return { applied: false, kind, subtype, reason: 'REPLAYED' };

  const record = (applied, note) => {
    db.prepare(
      `INSERT INTO iap_notify_event (event_id, kind, type, purchase_token, applied, note)
       VALUES (?, ?, ?, ?, ?, ?)`
    ).run(eventId, kind, subtype || kind, purchaseToken, applied ? 1 : 0, note || '');
  };

  if (kind === 'test' || kind === 'renew_time') {
    record(false, 'INFORMATIONAL');
    return { applied: false, kind, subtype, reason: 'INFORMATIONAL' };
  }
  if (kind === 'unknown') {
    record(false, 'UNKNOWN_TYPE');
    return { applied: false, kind, subtype, reason: 'UNKNOWN_TYPE' };
  }
  if (!purchaseToken) {
    record(false, 'MISSING_TOKEN');
    return { applied: false, kind, subtype, reason: 'MISSING_TOKEN' };
  }

  if (kind === 'expire') {
    const changed = db.prepare(
      `UPDATE subscription SET status = 'expired', auto_renew = 0, updated_at = datetime('now')
       WHERE purchase_token = ? AND status = 'active'`
    ).run(purchaseToken).changes;
    record(changed > 0, changed > 0 ? '' : 'NO_ACTIVE_SUBSCRIPTION');
    return { applied: changed > 0, kind, subtype, reason: changed > 0 ? '' : 'NO_ACTIVE_SUBSCRIPTION' };
  }

  if (kind === 'renew_status') {
    // AUTO_RENEW_ENABLED / AUTO_RENEW_DISABLED 只改续订开关，不动权益
    const enabled = subtype !== 'AUTO_RENEW_DISABLED';
    const changed = db.prepare(
      `UPDATE subscription SET auto_renew = ?, updated_at = datetime('now')
       WHERE purchase_token = ? AND status = 'active'`
    ).run(enabled ? 1 : 0, purchaseToken).changes;
    record(changed > 0, changed > 0 ? '' : 'NO_ACTIVE_SUBSCRIPTION');
    return { applied: changed > 0, kind, subtype, reason: changed > 0 ? '' : 'NO_ACTIVE_SUBSCRIPTION' };
  }

  if (kind === 'renew') {
    const row = db.prepare(
      'SELECT product_id, status FROM subscription WHERE purchase_token = ?'
    ).get(purchaseToken);
    if (!row) {
      record(false, 'NO_SUBSCRIPTION');
      return { applied: false, kind, subtype, reason: 'NO_SUBSCRIPTION' };
    }
    // 已退款/已撤销的订阅不能被迟到的续费通知复活（事件乱序/伪造都不该改回权益）
    if (row.status === 'refunded') {
      record(false, 'REFUNDED_IGNORED');
      return { applied: false, kind, subtype, reason: 'REFUNDED_IGNORED' };
    }
    const productId = typeof meta.currentProductId === 'string' && meta.currentProductId.length > 0
      ? meta.currentProductId
      : row.product_id;
    const months = RENEW_MONTHS(productId);
    // 从「原到期时间」与「现在」的较晚者起算：延迟送达/重推不会吞掉一个周期
    db.prepare(
      `UPDATE subscription
       SET status = 'active', auto_renew = 1,
           period_end = datetime(MAX(period_end, datetime('now')), '+${months} months'),
           updated_at = datetime('now')
       WHERE purchase_token = ?`
    ).run(purchaseToken);
    record(true);
    return { applied: true, kind, subtype, reason: '' };
  }

  // refund：订单置退款；订阅置 refunded；通行证按购买时绑上的 order_id 撤销
  const order = db.prepare('SELECT id, product_type FROM `order` WHERE purchase_token = ?').get(purchaseToken);
  if (!order) {
    record(false, 'NO_ORDER');
    return { applied: false, kind, subtype, reason: 'NO_ORDER' };
  }
  db.prepare(
    "UPDATE `order` SET status = 'refunded', refunded_at = datetime('now') WHERE id = ?"
  ).run(order.id);
  if (order.product_type === 'subscription') {
    db.prepare(
      `UPDATE subscription SET status = 'refunded', auto_renew = 0, updated_at = datetime('now')
       WHERE purchase_token = ?`
    ).run(purchaseToken);
  } else if (order.product_type === 'pass') {
    db.prepare("UPDATE trip_pass SET status = 'refunded' WHERE order_id = ?").run(order.id);
  }
  record(true);
  return { applied: true, kind, subtype, reason: '' };
}
