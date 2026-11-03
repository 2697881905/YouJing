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
