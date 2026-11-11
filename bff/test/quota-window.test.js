/**
 * 订阅档额度窗口的回归：商业化方案 §2 与付费页都写「20 次/月」，
 * 而这里曾按「20 次/天」数（`start of day`）——一个月最多 600 次，
 * 与方案字面口径差约 30 倍成本敞口，也和自家付费页自相矛盾（§5ci 续 85 的 D6）。
 *
 * 字段名 `usedToday`/`dailyCap` 是端侧契约（EntitlementStore.canGenerate 直接读），
 * 所以**只改口径不改名**；这条测试盯的就是口径。
 */
import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import { initDb } from '../src/db.js';
import { getEntitlement, determineQuotaSource } from '../src/services/quota.js';

const db = initDb(':memory:');
after(() => db.close());

let seq = 0;
function account(unionId) {
  const r = db.prepare('INSERT INTO account (union_id, device_id) VALUES (?, ?)')
    .run(unionId, `dev-${unionId}`);
  return Number(r.lastInsertRowid);
}

function succeeded(accountId, startedAtExpr) {
  seq += 1;
  db.prepare(
    `INSERT INTO trip_request (account_id, idempotency_key, request_hash, status, started_at)
     VALUES (?, ?, 'h', 'succeeded', ${startedAtExpr})`
  ).run(accountId, `k-${seq}`);
}

function subscribe(accountId) {
  seq += 1;
  db.prepare(
    `INSERT INTO subscription (account_id, product_id, status, period_start, period_end, auto_renew, purchase_token)
     VALUES (?, 'youjing_sub_monthly', 'active', datetime('now'), datetime('now', '+1 months'), 1, ?)`
  ).run(accountId, `tok-${seq}`);
}

test('本月成功次数才算已用，上月与失败行都不计', () => {
  const id = account('u-window');
  subscribe(id);
  succeeded(id, "datetime('now')");
  succeeded(id, "datetime('now')");
  succeeded(id, "datetime('now')");
  // 上月（本月 1 号再往前一天）三次：不该算进本月
  succeeded(id, "datetime('now', 'start of month', '-1 day')");
  succeeded(id, "datetime('now', 'start of month', '-1 day')");
  succeeded(id, "datetime('now', 'start of month', '-1 day')");
  // 本月但失败：不扣额度
  seq += 1;
  db.prepare(
    `INSERT INTO trip_request (account_id, idempotency_key, request_hash, status, started_at)
     VALUES (?, ?, 'h', 'failed', datetime('now'))`
  ).run(id, `k-${seq}`);

  const ent = getEntitlement(db, id);
  assert.equal(ent.usedToday, 3, '只数本月成功行');
  assert.equal(ent.dailyCap, 20);
  assert.equal(determineQuotaSource(db, id, null), 'subscription');
});

test('本月用满 20 次后订阅档不再放行', () => {
  const id = account('u-full');
  subscribe(id);
  for (let i = 0; i < 20; i += 1) {
    succeeded(id, "datetime('now')");
  }
  const ent = getEntitlement(db, id);
  assert.equal(ent.usedToday, 20);
  // 订阅额度用尽后应退到赠送额度（不是直接拒绝），所以这里断的是「不再是 subscription」
  assert.notEqual(determineQuotaSource(db, id, null), 'subscription');
  assert.equal(determineQuotaSource(db, id, null), 'gift');
});

/**
 * 管理员白名单（本机测试）：`ADMIN_ACCOUNT_IDS` 命中的账号不受额度窗口限制。
 * 白名单只在环境变量里，未设置即关闭——这条测试同时盯「命中放行」与「未命中照旧」。
 */
test('ADMIN_ACCOUNT_IDS 命中时无额度也放行，且不下发伪造的赠送额度', () => {
  const adminId = 9001;
  db.prepare('INSERT INTO account (id, union_id, device_id) VALUES (?, ?, ?)')
    .run(adminId, 'u-admin', 'dev-admin');
  // 无订阅、无通行证、赠送额度已耗尽，并已在本月用满 20 次
  db.prepare(
    `INSERT INTO quota_ledger (account_id, delta, source, state, idempotency_key)
     VALUES (?, -3, 'gift', 'committed', 'admin-gift-drained')`
  ).run(adminId);
  for (let i = 0; i < 25; i += 1) {
    succeeded(adminId, "datetime('now')");
  }

  const previous = process.env.ADMIN_ACCOUNT_IDS;
  process.env.ADMIN_ACCOUNT_IDS = '9001';
  try {
    const ent = getEntitlement(db, adminId);
    assert.equal(ent.unlimited, true);
    assert.equal(ent.giftRemaining, 0, '仍返回真实赠送额度，不靠伪造数字绕端侧门禁');
    assert.equal(determineQuotaSource(db, adminId, null), 'admin');

    // 白名单外的账号行为不变：仍走原有订阅/通行证/赠送判定
    const normalId = account('u-not-admin');
    assert.equal(getEntitlement(db, normalId).unlimited, false);
    assert.equal(determineQuotaSource(db, normalId, null), 'gift');
  } finally {
    if (previous === undefined) {
      delete process.env.ADMIN_ACCOUNT_IDS;
    } else {
      process.env.ADMIN_ACCOUNT_IDS = previous;
    }
  }
});
