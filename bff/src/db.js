import Database from 'better-sqlite3';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { mkdirSync } from 'fs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
// 上云/容器部署时根文件系统常常只读，数据库必须能挪到挂载卷上（`npm run preflight` 会盯这一条）。
const DB_PATH = process.env.DB_PATH || join(__dirname, '..', 'data', 'youjing.db');

const DDL = `
CREATE TABLE IF NOT EXISTS account (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  union_id TEXT UNIQUE NOT NULL,
  device_id TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_seen_at TEXT,
  risk_flags INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS subscription (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  account_id INTEGER NOT NULL,
  product_id TEXT NOT NULL,
  status TEXT NOT NULL,
  period_start TEXT NOT NULL,
  period_end TEXT NOT NULL,
  auto_renew INTEGER NOT NULL DEFAULT 1,
  purchase_token TEXT UNIQUE NOT NULL,
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_sub_account ON subscription(account_id);

CREATE TABLE IF NOT EXISTS trip_pass (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  account_id INTEGER NOT NULL,
  local_trip_id TEXT NOT NULL,
  status TEXT NOT NULL,
  expires_at TEXT,
  order_id INTEGER,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE UNIQUE INDEX IF NOT EXISTS uk_pass ON trip_pass(account_id, local_trip_id);
CREATE INDEX IF NOT EXISTS idx_pass_account ON trip_pass(account_id);

CREATE TABLE IF NOT EXISTS quota_ledger (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  account_id INTEGER NOT NULL,
  delta INTEGER NOT NULL,
  source TEXT NOT NULL,
  ref_type TEXT,
  ref_id INTEGER,
  state TEXT NOT NULL,
  idempotency_key TEXT UNIQUE NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  settled_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_ledger_account ON quota_ledger(account_id);

CREATE TABLE IF NOT EXISTS trip_request (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  account_id INTEGER NOT NULL,
  idempotency_key TEXT UNIQUE NOT NULL,
  request_hash TEXT NOT NULL DEFAULT '',
  params_json TEXT,
  response_json TEXT,
  status TEXT NOT NULL,
  prompt_tokens INTEGER,
  completion_tokens INTEGER,
  model TEXT,
  cost_micros INTEGER,
  started_at TEXT NOT NULL,
  finished_at TEXT,
  error_code INTEGER
);
CREATE INDEX IF NOT EXISTS idx_req_account ON trip_request(account_id);

CREATE TABLE IF NOT EXISTS \`order\` (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  account_id INTEGER NOT NULL,
  product_type TEXT NOT NULL,
  product_id TEXT NOT NULL,
  amount_cents INTEGER NOT NULL,
  currency TEXT NOT NULL DEFAULT 'CNY',
  huawei_order_id TEXT UNIQUE,
  purchase_token TEXT,
  status TEXT NOT NULL,
  paid_at TEXT,
  refunded_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_order_account ON \`order\`(account_id);
`;

function ensureColumn(db, table, column, definition) {
  const columns = db.prepare(`PRAGMA table_info(${table})`).all();
  if (!columns.some((item) => item.name === column)) {
    db.exec(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`);
  }
}

export function initDb(path = DB_PATH) {
  if (path !== ':memory:') {
    mkdirSync(dirname(path), { recursive: true });
  }
  const db = new Database(path);
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');
  db.exec(DDL);
  // 旧库升级：trip_request 需要 request_hash / response_json 才能正确幂等重放
  ensureColumn(db, 'trip_request', 'request_hash', "TEXT NOT NULL DEFAULT ''");
  ensureColumn(db, 'trip_request', 'response_json', 'TEXT');
  console.log('[db] SQLite initialized at', path);
  return db;
}

export function getDb() {
  const db = new Database(DB_PATH, { readonly: false });
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');
  return db;
}

if (process.argv[1] === __filename) {
  initDb();
  console.log('[db] Migration complete');
}