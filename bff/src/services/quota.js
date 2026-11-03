const DAILY_CAP = 20;
const GIFT_QUOTA = 3;

export function getEntitlement(db, accountId) {
  const sub = db.prepare(
    `SELECT * FROM subscription WHERE account_id = ? AND status = 'active' ORDER BY period_end DESC LIMIT 1`
  ).get(accountId);

  const passes = db.prepare(
    `SELECT local_trip_id, status, expires_at FROM trip_pass WHERE account_id = ? AND status = 'active'`
  ).all(accountId);

  const giftLedger = db.prepare(
    `SELECT COALESCE(SUM(delta), 0) as total FROM quota_ledger
     WHERE account_id = ? AND source = 'gift' AND state = 'committed'`
  ).get(accountId);

  const usedToday = db.prepare(
    `SELECT COUNT(*) as cnt FROM trip_request
     WHERE account_id = ? AND status = 'succeeded'
     AND started_at >= date('now', 'start of day')`
  ).get(accountId);

  const giftRemaining = Math.max(0, GIFT_QUOTA + (giftLedger?.total || 0));

  return {
    subscription: sub ? { status: sub.status, periodEnd: sub.period_end } : null,
    passes: passes.map(p => ({ localTripId: p.local_trip_id, status: p.status, expiresAt: p.expires_at })),
    giftRemaining,
    usedToday: usedToday?.cnt || 0,
    dailyCap: DAILY_CAP
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