/**
 * 手表全网络客户端 · BFF 路由（切片0/1/2 共用）。
 *
 * 职责边界（规格 §5.1 / §11）：
 * - BFF 只做传输与暂存：卡片、决策、push token，按 account_id（uid）分区；
 * - 不做业务裁决、不改行程、不读手机本地库；
 * - 手表与手机同华为账号 → 同一个 account.id；手表 idToken 只用于换取 BFF 票据。
 *
 * fail-closed：手表 idToken 验签未过/缺失/过期一律 401；不降级放行。
 */

import { Router } from 'express';
import { authMiddleware, issueToken } from '../middleware/auth.js';
import { verifyHuaweiIdToken } from '../services/huaweiIdToken.js';
import {
  pushCardToAccount, pushWithdrawToAccount, pushConfigured
} from '../services/watchPush.js';

const router = Router();

/** 与 watchcontract 的 WATCH_CARD_TTL 对齐：手机侧 30 分钟过期 */
const CARD_TTL_MS = 30 * 60 * 1000;
const MAX_LIST = 50;

function nonEmpty(value, max = 512) {
  return typeof value === 'string' && value.trim().length > 0 && value.length <= max;
}

function cardError(card) {
  if (!card || typeof card !== 'object' || Array.isArray(card)) {
    return 'card 必须是对象';
  }
  if (card.v !== 1) return '不支持的协议版本';
  if (card.type !== 'card') return 'type 必须是 card';
  if (!nonEmpty(card.cardId, 200)) return 'cardId 非法';
  if (card.kind !== 'companion' && card.kind !== 'checkin') return 'kind 非法';
  if (!nonEmpty(card.title, 200)) return 'title 非法';
  if (!Array.isArray(card.options) || card.options.length < 1 || card.options.length > 3) {
    return 'options 必须 1–3 项';
  }
  for (const option of card.options) {
    if (!option || typeof option !== 'object' || !nonEmpty(option.key, 100) ||
      !nonEmpty(option.label, 100)) {
      return 'option 非法';
    }
  }
  if (!nonEmpty(card.recommendedKey, 100)) return 'recommendedKey 非法';
  if (typeof card.ts !== 'number' || !Number.isFinite(card.ts) || card.ts <= 0) return 'ts 非法';
  return '';
}

function decisionError(decision) {
  if (!decision || typeof decision !== 'object' || Array.isArray(decision)) {
    return 'decision 必须是对象';
  }
  if (decision.v !== 1) return '不支持的协议版本';
  if (decision.type !== 'decision') return 'type 必须是 decision';
  if (!nonEmpty(decision.cardId, 200)) return 'cardId 非法';
  if (!nonEmpty(decision.optionKey, 100)) return 'optionKey 非法';
  if (typeof decision.ts !== 'number' || !Number.isFinite(decision.ts) || decision.ts <= 0) {
    return 'ts 非法';
  }
  return '';
}

/**
 * 手表登录换 BFF 票据：idToken（华为）→ unionId → account.id。
 * 与手机 /v1/device/activate 同一套 JWKS 验签；手表不覆盖 account.device_id。
 */
router.post('/session', async (req, res, next) => {
  try {
    const { watchDeviceId, idToken } = req.body || {};
    if (!nonEmpty(watchDeviceId, 128)) {
      return res.status(400).json({ error: 'MISSING_WATCH_DEVICE_ID', message: '缺少或非法的 watchDeviceId' });
    }
    if (!nonEmpty(idToken, 4096)) {
      return res.status(400).json({ error: 'MISSING_ID_TOKEN', message: '缺少 idToken' });
    }
    const verified = await verifyHuaweiIdToken(idToken);
    if (!verified.ok) {
      console.warn(`[watch] 手表 idToken 验签失败 reason=${verified.reason}`);
      return res.status(401).json({ error: 'ID_TOKEN_INVALID', message: '华为身份票据无效' });
    }
    const db = req.db;
    let account = db.prepare('SELECT * FROM account WHERE union_id = ?').get(verified.unionId);
    if (!account) {
      // 手表可能先于手机登录：先建账号，手机下次激活会复用同一行。
      db.prepare('INSERT OR IGNORE INTO account (union_id, device_id) VALUES (?, NULL)')
        .run(verified.unionId);
      account = db.prepare('SELECT * FROM account WHERE union_id = ?').get(verified.unionId);
    }
    db.prepare(
      `INSERT INTO watch_device (account_id, watch_device_id) VALUES (?, ?)
       ON CONFLICT(account_id, watch_device_id)
       DO UPDATE SET updated_at = datetime('now')`
    ).run(account.id, watchDeviceId);
    const token = issueToken(account.id, watchDeviceId);
    console.log(`[watch] session account=${account.id} watch=${watchDeviceId}`);
    res.json({ deviceToken: token, accountId: account.id });
  } catch (err) {
    next(err);
  }
});

// 以下全部要求 BFF 票据（手表或手机各自一份，均映射到同一 account.id）
router.use(authMiddleware);

/** 探针用：返回当前票据对应的账号，供两侧 uid 对表（G0-N-c） */
router.get('/whoami', (req, res) => {
  res.json({ accountId: req.accountId, deviceId: req.deviceId, pushConfigured: pushConfigured() });
});

/** 手表注册 Push token（auth=手表 BFF 票据） */
router.post('/push-token', (req, res) => {
  const { pushToken } = req.body || {};
  if (!nonEmpty(pushToken, 512)) {
    return res.status(400).json({ error: 'MISSING_PUSH_TOKEN', message: '缺少或非法的 pushToken' });
  }
  const db = req.db;
  const info = db.prepare(
    `UPDATE watch_device SET push_token = ?, updated_at = datetime('now')
     WHERE account_id = ? AND watch_device_id = ?`
  ).run(pushToken, req.accountId, req.deviceId);
  if (info.changes === 0) {
    db.prepare(
      'INSERT INTO watch_device (account_id, watch_device_id, push_token) VALUES (?, ?, ?)'
    ).run(req.accountId, req.deviceId, pushToken);
  }
  console.log(`[watch] push-token account=${req.accountId} device=${req.deviceId}`);
  res.json({ ok: true });
});

/** 手机投影卡片 → 暂存 + Push（auth=手机 BFF 票据） */
router.post('/card', async (req, res, next) => {
  try {
    const card = (req.body || {}).card;
    const err = cardError(card);
    if (err) {
      return res.status(400).json({ error: 'INVALID_CARD', message: err });
    }
    const db = req.db;
    const existing = db.prepare('SELECT account_id FROM watch_card WHERE card_id = ?').get(card.cardId);
    if (existing && existing.account_id !== req.accountId) {
      return res.status(409).json({ error: 'CARD_ID_CONFLICT', message: 'cardId 已被其他账号占用' });
    }
    const createdAt = new Date(card.ts).toISOString();
    const expiresAt = new Date(card.ts + CARD_TTL_MS).toISOString();
    db.prepare(
      `INSERT INTO watch_card (card_id, account_id, kind, payload_json, status, created_at, expires_at)
       VALUES (?, ?, ?, ?, 'live', ?, ?)
       ON CONFLICT(card_id) DO UPDATE SET
         account_id = excluded.account_id,
         kind = excluded.kind,
         payload_json = excluded.payload_json,
         status = 'live',
         created_at = excluded.created_at,
         expires_at = excluded.expires_at`
    ).run(card.cardId, req.accountId, card.kind, JSON.stringify(card), createdAt, expiresAt);
    const pushed = await pushCardToAccount(db, req.accountId, card);
    console.log(`[watch] card account=${req.accountId} cardId=${card.cardId} pushed=${pushed.sent} reason=${pushed.reason}`);
    res.json({ ok: true, pushed: pushed.sent, push: pushed.reason });
  } catch (err) {
    next(err);
  }
});

/** 手机撤卡（auth=手机 BFF 票据） */
router.post('/card/withdraw', async (req, res, next) => {
  try {
    const { cardId } = req.body || {};
    if (!nonEmpty(cardId, 200)) {
      return res.status(400).json({ error: 'MISSING_CARD_ID', message: '缺少或非法的 cardId' });
    }
    const info = req.db.prepare(
      "UPDATE watch_card SET status = 'withdrawn' WHERE card_id = ? AND account_id = ?"
    ).run(cardId, req.accountId);
    const pushed = info.changes > 0
      ? await pushWithdrawToAccount(req.db, req.accountId, cardId)
      : { sent: 0, reason: 'NO_CARD' };
    res.json({ ok: true, withdrawn: info.changes, pushed: pushed.sent, push: pushed.reason });
  } catch (err) {
    next(err);
  }
});

/** 手表拉当前卡（Push 只带 cardId 时用；也是轮询降级入口） */
router.get('/card/current', (req, res) => {
  const now = new Date().toISOString();
  const row = req.db.prepare(
    `SELECT payload_json FROM watch_card
     WHERE account_id = ? AND status = 'live' AND expires_at > ?
     ORDER BY created_at DESC LIMIT 1`
  ).get(req.accountId, now);
  if (!row) {
    return res.status(404).json({ error: 'NO_CARD', message: '当前没有待决卡片' });
  }
  res.json({ card: JSON.parse(row.payload_json) });
});

/** 手表回传决策（auth=手表 BFF 票据）；幂等键 = account+cardId+optionKey */
router.post('/decision', (req, res) => {
  const decision = (req.body || {}).decision;
  const err = decisionError(decision);
  if (err) {
    return res.status(400).json({ error: 'INVALID_DECISION', message: err });
  }
  const db = req.db;
  const inserted = db.prepare(
    `INSERT OR IGNORE INTO watch_decision
       (account_id, card_id, option_key, payload_json, status, created_at)
     VALUES (?, ?, ?, ?, 'pending', ?)`
  ).run(req.accountId, decision.cardId, decision.optionKey,
    JSON.stringify(decision), new Date(decision.ts).toISOString());
  const row = db.prepare(
    'SELECT id FROM watch_decision WHERE account_id = ? AND card_id = ? AND option_key = ?'
  ).get(req.accountId, decision.cardId, decision.optionKey);
  console.log(`[watch] decision account=${req.accountId} cardId=${decision.cardId} ` +
    `option=${decision.optionKey} duplicate=${inserted.changes === 0}`);
  res.json({ ok: true, decisionId: row.id, duplicate: inserted.changes === 0 });
});

/** 手机拉待执行决策（auth=手机 BFF 票据）；since=上次最大 id */
router.get('/decisions', (req, res) => {
  const since = Number.parseInt(req.query.since, 10);
  const cursor = Number.isInteger(since) && since > 0 ? since : 0;
  const rows = req.db.prepare(
    `SELECT id, payload_json, created_at FROM watch_decision
     WHERE account_id = ? AND status = 'pending' AND id > ?
     ORDER BY id ASC LIMIT ?`
  ).all(req.accountId, cursor, MAX_LIST);
  res.json({
    decisions: rows.map((row) => ({
      id: row.id,
      decision: JSON.parse(row.payload_json),
      createdAt: row.created_at
    }))
  });
});

/** 手机执行后 ack（auth=手机 BFF 票据） */
router.post('/decision/ack', (req, res) => {
  const raw = (req.body || {}).ids;
  const ids = Array.isArray(raw) ? raw : ((req.body || {}).id !== undefined ? [req.body.id] : []);
  const clean = ids.filter((id) => Number.isInteger(id) && id > 0);
  if (clean.length === 0 || clean.length > MAX_LIST) {
    return res.status(400).json({ error: 'INVALID_ACK_IDS', message: 'ids 必须是 1–50 个正整数' });
  }
  const placeholders = clean.map(() => '?').join(',');
  const info = req.db.prepare(
    `UPDATE watch_decision SET status = 'acked', acked_at = datetime('now')
     WHERE account_id = ? AND status = 'pending' AND id IN (${placeholders})`
  ).run(req.accountId, ...clean);
  res.json({ ok: true, acked: info.changes });
});

export default router;
