import { Router } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { issueToken } from '../middleware/auth.js';
import { getEntitlement } from '../services/quota.js';

const router = Router();

router.post('/activate', async (req, res, next) => {
  try {
    const { deviceId, unionId } = req.body;
    if (!deviceId) {
      return res.status(400).json({ error: 'MISSING_DEVICE_ID', message: '缺少 deviceId' });
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