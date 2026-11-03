/**
 * 华为 IAP 服务端通知（订阅生命周期 / 退款）→ 权益变更。
 *
 * 改前 `/v1/iap/notify` 只 `console.log` 后回 200，等于**到期、退款、续费全部黑洞**：
 * 订阅过了 period_end 仍按 active 继续送额度（见 quota.js 的 getEntitlement 原查询），
 * 退款后通行证照样能导出。D7。
 *
 * 两条安全边界：
 * 1) **验签**：华为推来的通知带 `Authorization` 头（Base64 的 RSA-SHA256 签名，密钥是 AGC 控制台给的公钥）。
 *    `IAP_NOTIFY_PUBLIC_KEY` 未配置时一律 503 —— 这个端点能撤销别人的付费权益，
 *    宁可拒收也不能在没配公钥时默认信任。
 * 2) **未知事件不改权益**：枚举串按华为文档归类，认不出的只记事件、回 200（避免它无限重推）。
 *
 * 归一化词表是本文件自己的契约；真实回调的字段名与枚举值**要等第一封真通知对表**，
 * 对不上时只需改 `CLASSIFY` 一处（未验项已记进 Docs/analysis/商业化链路真实验收-2026-11-03.md）。
 */
import { createHash, createPublicKey, createVerify } from 'node:crypto';

const CLASSIFY = {
  expire: new Set(['EXPIRED', 'EXPIRE', 'SUBSCRIPTION_EXPIRED']),
  // 注意：CANCEL 不等于到期。用户只是关掉自动续费时订阅仍有效到期满，不能提前断供。
  renew: new Set(['RENEWED', 'RENEWAL', 'DID_RENEW', 'RENEWAL_RECOVERED']),
  refund: new Set(['REFUND', 'REFUNDED', 'REVOKE', 'REVOKED'])
};

export function classifyNotification(body) {
  const raw = body && (body.notificationType || body.notification_type || body.type || body.eventType);
  const type = typeof raw === 'string' ? raw.trim().toUpperCase() : '';
  for (const kind of ['expire', 'renew', 'refund']) {
    if (CLASSIFY[kind].has(type)) return { kind, type };
  }
  return { kind: 'unknown', type };
}

/** Authorization 头是 Base64(RSA-SHA256(原始 body))；返回 {ok, reason} */
export function notifySignatureOk(rawBody, authHeader, publicKeyPem) {
  if (!publicKeyPem) return { ok: false, reason: 'NOT_CONFIGURED' };
  if (!authHeader) return { ok: false, reason: 'MISSING_SIGNATURE' };
  const signature = Buffer.from(String(authHeader).trim(), 'base64');
  try {
    const verifier = createVerify('RSA-SHA256');
    verifier.update(rawBody);
    return verifier.verify(createPublicKey(publicKeyPem), signature)
      ? { ok: true }
      : { ok: false, reason: 'BAD_SIGNATURE' };
  } catch (err) {
    return { ok: false, reason: 'BAD_KEY' };
  }
}

function eventIdOf(body, rawBody) {
  const given = body && (body.eventId || body.event_id || body.notificationId);
  if (typeof given === 'string' && given.length > 0) return given;
  return 'sha256:' + createHash('sha256').update(rawBody).digest('hex');
}

function purchaseTokenOf(body) {
  const token = body && (body.purchaseToken || body.purchase_token || body.orderId);
  return typeof token === 'string' && token.length > 0 ? token : '';
}

/**
 * 应用一条已验签的通知。返回 { applied, kind, reason }。
 * 幂等键先落库：同一 eventId 第二次进来直接 replayed，不再改权益、不再续期。
 */
export function applyNotification(db, body, rawBody) {
  const eventId = eventIdOf(body, rawBody);
  const { kind, type } = classifyNotification(body);
  const purchaseToken = purchaseTokenOf(body);

  const seen = db.prepare('SELECT 1 FROM iap_notify_event WHERE event_id = ?').get(eventId);
  if (seen) return { applied: false, kind, reason: 'REPLAYED' };

  const record = (applied, note) => {
    db.prepare(
      `INSERT INTO iap_notify_event (event_id, kind, type, purchase_token, applied, note)
       VALUES (?, ?, ?, ?, ?, ?)`
    ).run(eventId, kind, type, purchaseToken, applied ? 1 : 0, note || '');
  };

  if (kind === 'unknown') {
    record(false, 'UNKNOWN_TYPE');
    return { applied: false, kind, reason: 'UNKNOWN_TYPE' };
  }
  if (!purchaseToken) {
    record(false, 'MISSING_TOKEN');
    return { applied: false, kind, reason: 'MISSING_TOKEN' };
  }

  if (kind === 'expire') {
    const changed = db.prepare(
      `UPDATE subscription SET status = 'expired', auto_renew = 0, updated_at = datetime('now')
       WHERE purchase_token = ? AND status = 'active'`
    ).run(purchaseToken).changes;
    record(changed > 0, changed > 0 ? '' : 'NO_ACTIVE_SUBSCRIPTION');
    return { applied: changed > 0, kind, reason: changed > 0 ? '' : 'NO_ACTIVE_SUBSCRIPTION' };
  }

  if (kind === 'renew') {
    const row = db.prepare('SELECT product_id FROM subscription WHERE purchase_token = ?').get(purchaseToken);
    if (!row) {
      record(false, 'NO_SUBSCRIPTION');
      return { applied: false, kind, reason: 'NO_SUBSCRIPTION' };
    }
    const months = row.product_id === 'youjing_sub_yearly' ? 12 : 1;
    // 从「原到期时间」与「现在」的较晚者起算：延迟送达/重推不会吞掉一个周期
    db.prepare(
      `UPDATE subscription
       SET status = 'active', auto_renew = 1,
           period_end = datetime(MAX(period_end, datetime('now')), '+${months} months'),
           updated_at = datetime('now')
       WHERE purchase_token = ?`
    ).run(purchaseToken);
    record(true);
    return { applied: true, kind, reason: '' };
  }

  // refund：订单置退款；订阅置 refunded；通行证按购买时绑上的 order_id 撤销
  const order = db.prepare('SELECT id, product_type FROM `order` WHERE purchase_token = ?').get(purchaseToken);
  if (!order) {
    record(false, 'NO_ORDER');
    return { applied: false, kind, reason: 'NO_ORDER' };
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
  return { applied: true, kind, reason: '' };
}
