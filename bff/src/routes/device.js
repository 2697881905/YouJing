import { Router } from 'express';
import { issueToken } from '../middleware/auth.js';
import { getEntitlement } from '../services/quota.js';
import { verifyHuaweiIdToken } from '../services/huaweiIdToken.js';

const router = Router();

router.post('/activate', async (req, res, next) => {
  try {
    const { deviceId, idToken } = req.body;
    const selfReportedUnionId = req.body.unionId;
    // 边界校验：非字符串/空串/超长会在 better-sqlite3 里抛成 500，也会把账号表撑脏。
    if (typeof deviceId !== 'string' || deviceId.trim().length === 0 || deviceId.length > 128) {
      return res.status(400).json({ error: 'MISSING_DEVICE_ID', message: '缺少或非法的 deviceId' });
    }
    if (selfReportedUnionId !== undefined && selfReportedUnionId !== null && selfReportedUnionId !== '' &&
      (typeof selfReportedUnionId !== 'string' || selfReportedUnionId.length > 128)) {
      return res.status(400).json({ error: 'INVALID_UNION_ID', message: '非法的 unionId' });
    }

    // D10：身份只认**验签通过的 idToken.sub**。请求体里的 unionId 一律不信——
    // 知道他人 unionId 就能换到对方票据与权益，那是认证缺陷，不能靠"猜不到"。
    let unionId = '';
    if (idToken !== undefined && idToken !== null && idToken !== '') {
      if (typeof idToken !== 'string' || idToken.length > 4096) {
        return res.status(400).json({ error: 'INVALID_ID_TOKEN', message: '非法的 idToken' });
      }
      const verified = await verifyHuaweiIdToken(idToken);
      if (!verified.ok) {
        console.warn(`[device] idToken 验签失败 reason=${verified.reason}`);
        return res.status(401).json({ error: 'ID_TOKEN_INVALID', message: '华为身份票据无效' });
      }
      unionId = verified.unionId;
    } else if (typeof selfReportedUnionId === 'string' && selfReportedUnionId.length > 0) {
      console.warn('[device] 忽略客户端自报 unionId（未提供 idToken），按游客处理');
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
    console.log(`[device] activate account=${account.id} kind=${unionId.length > 0 ? 'huawei' : 'anon'}`);

    res.json({ deviceToken: token, entitlement });
  } catch (err) {
    next(err);
  }
});

export default router;