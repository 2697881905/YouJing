/**
 * 开发环境额度重置（一次性工具，勿用于生产）。
 *
 * 背景：本地开发用赠送额度（GIFT_QUOTA=3）验证生成链路，跑满后 /v1/trip 返回 402。
 * 赠送额度按 quota_ledger（source='gift'）已 committed 的行累计扣减；
 * 把这些行标为 'released' 即恢复 giftRemaining=3，不动 trip_request 历史。
 *
 * 用法：
 *   node scripts/reset-dev-quota.mjs            # 重置所有账号的赠送额度
 *   node scripts/reset-dev-quota.mjs --dry      # 只打印会改多少行
 */
import Database from 'better-sqlite3';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DB_PATH = process.env.DB_PATH || join(__dirname, '..', 'data', 'youjing.db');
const dry = process.argv.includes('--dry');

const db = new Database(DB_PATH, { readonly: false });

const rows = db.prepare(
  `SELECT id, account_id, idempotency_key FROM quota_ledger
   WHERE source = 'gift' AND state = 'committed'`
).all();

console.log(`DB=${DB_PATH}`);
console.log(`可重置的赠送额度行=${rows.length}`);
for (const r of rows) {
  console.log(`  ledger#${r.id} account=${r.account_id} key=${r.idempotency_key}`);
}

if (!dry) {
  const result = db.prepare(
    `UPDATE quota_ledger SET state = 'released', settled_at = datetime('now')
     WHERE source = 'gift' AND state = 'committed'`
  ).run();
  console.log(`已重置 ${result.changes} 行；giftRemaining 恢复为 3。`);
}

db.close();
