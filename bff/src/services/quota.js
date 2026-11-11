/**
 * 订阅档的防滥用上限：商业化方案 §2 写的是「20 次/**月**」，屏2 的付费页文案也写「每月 20 次」。
 * 这里原本按**天**数（`start of day` + DAILY_CAP=20），一个月最多可跑到 600 次，
 * 与方案的字面口径差约 30 倍成本敞口，也和自家付费页自相矛盾（§5ci 续 85 的 D6）。
 *
 * 响应字段名沿用 `usedToday` / `dailyCap`：端侧 `EntitlementStore.canGenerate()` 直接读这两个键，
 * 改名要连端侧一起动，而 BFF 还没部署、收益为零。**口径已改成按月**，名字留作历史兼容。
 */
import { isAdminAccount } from './admin.js';

const MONTHLY_CAP = 20;
const GIFT_QUOTA = 3;

export function getEntitlement(db, accountId) {
  // 必须同时看 status 与 period_end：只信 status 的话，过期订阅在通知送达前会继续送额度
  const sub = db.prepare(
    `SELECT * FROM subscription
     WHERE account_id = ? AND status = 'active' AND period_end >= datetime('now')
     ORDER BY period_end DESC LIMIT 1`
  ).get(accountId);

  const passes = db.prepare(
    `SELECT local_trip_id, status, expires_at FROM trip_pass WHERE account_id = ? AND status = 'active'`
  ).all(accountId);

  const giftLedger = db.prepare(
    `SELECT COALESCE(SUM(delta), 0) as total FROM quota_ledger
     WHERE account_id = ? AND source = 'gift' AND state = 'committed'`
  ).get(accountId);

  // 按月计（与方案 §2 和付费页文案一致）；字段名沿用 usedToday 见文件头说明
  const usedThisMonth = db.prepare(
    `SELECT COUNT(*) as cnt FROM trip_request
     WHERE account_id = ? AND status = 'succeeded'
     AND started_at >= date('now', 'start of month')`
  ).get(accountId);

  const giftRemaining = Math.max(0, GIFT_QUOTA + (giftLedger?.total || 0));

  return {
    subscription: sub ? { status: sub.status, periodEnd: sub.period_end } : null,
    passes: passes.map(p => ({ localTripId: p.local_trip_id, status: p.status, expiresAt: p.expires_at })),
    giftRemaining,
    usedToday: usedThisMonth?.cnt || 0,
    dailyCap: MONTHLY_CAP,
    // 管理员（ADMIN_ACCOUNT_IDS，仅本机测试）：端侧 canGenerate 直接放行，
    // 不靠伪造 giftRemaining 绕过门禁；额度用量照常统计，便于观察真实调用量。
    unlimited: isAdminAccount(accountId)
  };
}

export function reserveQuota(db, accountId, idempotencyKey, source) {
  const existing = db.prepare(
    'SELECT * FROM quota_ledger WHERE idempotency_key = ?'
  ).get(idempotencyKey);
  if (existing) {
    // 上一次失败已 released：同键同体重试时重新预占，避免 commit 无行可更新
    if (existing.state === 'released') {
      db.prepare(
        `UPDATE quota_ledger SET state = 'reserved', settled_at = NULL
         WHERE idempotency_key = ? AND state = 'released'`
      ).run(idempotencyKey);
    }
    return db.prepare(
      'SELECT * FROM quota_ledger WHERE idempotency_key = ?'
    ).get(idempotencyKey);
  }

  db.prepare(
    `INSERT INTO quota_ledger (account_id, delta, source, state, idempotency_key)
     VALUES (?, -1, ?, 'reserved', ?)`
  ).run(accountId, source, idempotencyKey);

  return db.prepare(
    'SELECT * FROM quota_ledger WHERE idempotency_key = ?'
  ).get(idempotencyKey);
}

export function commitQuota(db, idempotencyKey) {
  db.prepare(
    `UPDATE quota_ledger SET state = 'committed', settled_at = datetime('now')
     WHERE idempotency_key = ? AND state = 'reserved'`
  ).run(idempotencyKey);
}

export function releaseQuota(db, idempotencyKey) {
  db.prepare(
    `UPDATE quota_ledger SET state = 'released', settled_at = datetime('now')
     WHERE idempotency_key = ? AND state = 'reserved'`
  ).run(idempotencyKey);
}

export function determineQuotaSource(db, accountId, passId) {
  // 管理员优先于订阅/通行证/赠送：本机测试不该被额度窗口挡住。
  // 仍返回一个 source 让账本照常落一行（source='admin'），幂等行的写法不用分叉。
  if (isAdminAccount(accountId)) {
    return 'admin';
  }
  const entitlement = getEntitlement(db, accountId);
  if (entitlement.subscription && entitlement.usedToday < entitlement.dailyCap) {
    return 'subscription';
  }
  if (passId) {
    const pass = entitlement.passes.find(p => p.localTripId === passId);
    if (pass) {
      return 'pass';
    }
  }
  if (entitlement.giftRemaining > 0) {
    return 'gift';
  }
  return null;
}