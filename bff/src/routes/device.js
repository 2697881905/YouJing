import { Router } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { issueToken } from '../middleware/auth.js';
import { getEntitlement } from '../services/quota.js';

const router = Router();

router.post('/activate', async (req, res, next) => {
  try {
    const { deviceId, unionId } = req.body;
    // 边界校验：非字符串/空串/超长会在 better-sqlite3 里抛成 500，也会把账号表撑脏。
    if (typeof deviceId !== 'string' || deviceId.trim().length === 0 || deviceId.length > 128) {
      return res.status(400).json({ error: 'MISSING_DEVICE_ID', message: '缺少或非法的 deviceId' });
    }
    if (unionId !== undefined && unionId !== null && unionId !== '' &&
      (typeof unionId !== 'string' || unionId.length > 128)) {
      return res.status(400).json({ error: 'INVALID_UNION_ID', message: '非法的 unionId' });
    }

    const db = req.db;
    let account;

    if (unionId) {
      account = db.prepare('SELECT * FROM account WHERE union_id = ?').get(unionId);
      if (!account) {
        const result = db.prepare(
          'INSERT INTO account (union_id, device_id) VALUES (?, ?)'
        ).run(unionId, deviceId);
        account = db.prepare('SELECT * FROM account WHERE id = ?').get(result.lastInsertRowid);
      } else {
        db.prepare(
          'UPDATE account SET device_id = ?, last_seen_at = datetime(\'now\') WHERE id = ?'
        ).run(deviceId, account.id);
      }
    } else {
      account = db.prepare('SELECT * FROM account WHERE device_id = ?').get(deviceId);
      if (!account) {
        const anonUnionId = `anon-${deviceId}`;
        const result = db.prepare(
          'INSERT INTO account (union_id, device_id) VALUES (?, ?)'
        ).run(anonUnionId, deviceId);
        account = db.prepare('SELECT * FROM account WHERE id = ?').get(result.lastInsertRowid);
      } else {
        db.prepare(
          'UPDATE account SET last_seen_at = datetime(\'now\') WHERE id = ?'
        ).run(account.id);
      }
    }

    const token = issueToken(account.id, deviceId);
    const entitlement = getEntitlement(db, account.id);

    res.json({ deviceToken: token, entitlement });
  } catch (err) {
    next(err);
  }
});

export default router;