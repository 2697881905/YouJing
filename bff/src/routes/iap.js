import { Router } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { verifyPurchase } from '../services/iap.js';
import { getEntitlement } from '../services/quota.js';

const router = Router();

router.post('/verify', async (req, res, next) => {
  try {
    const db = req.db;
    const { purchaseToken, productType, localTripId } = req.body;

    if (!purchaseToken || !productType) {
      return res.status(400).json({ error: 'MISSING_PARAMS', message: '缺少 purchaseToken 或 productType' });
    }

    const iapResult = await verifyPurchase(purchaseToken, productType);
    if (!iapResult.verified) {
      return res.status(200).json({ verified: false, message: 'IAP 校验未通过' });
    }

    let accountId = req.accountId;
    if (!accountId) {
      const authHeader = req.headers.authorization;
      if (authHeader?.startsWith('Bearer ')) {
        const token = authHeader.substring(7);
        try {
          const jwt = (await import('jsonwebtoken')).default;
          const payload = jwt.verify(token, process.env.JWT_SECRET || 'youjing-bff-dev-secret');
          accountId = payload.accountId;
        } catch (e) {
          return res.status(401).json({ error: 'TOKEN_INVALID', message: '票据无效' });
        }
      }
      if (!accountId) {
        return res.status(401).json({ error: 'TOKEN_INVALID', message: '缺少有效票据' });
      }
    }

    if (productType === 'pass') {
      if (!localTripId) {
        return res.status(400).json({ error: 'MISSING_TRIP_ID', message: '通行证购买需提供 localTripId' });
      }

      const existingPass = db.prepare(
        'SELECT * FROM trip_pass WHERE account_id = ? AND local_trip_id = ? AND status = ?'
      ).get(accountId, localTripId, 'active');

      if (!existingPass) {
        db.prepare(
          `INSERT INTO trip_pass (account_id, local_trip_id, status)
           VALUES (?, ?, 'active')`
        ).run(accountId, localTripId);
      }

      db.prepare(
        `INSERT INTO \`order\` (account_id, product_type, product_id, amount_cents, purchase_token, status, paid_at)
         VALUES (?, 'pass', 'youjing_pass', 990, ?, 'paid', datetime('now'))`
      ).run(accountId, purchaseToken);
    } else if (productType === 'subscription') {
      const productId = req.body.productId || 'youjing_sub_monthly';
      const amountCents = productId === 'youjing_sub_yearly' ? 9800 : 1990;
      const periodMonths = productId === 'youjing_sub_yearly' ? 12 : 1;

      db.prepare(
        `INSERT INTO subscription (account_id, product_id, status, period_start, period_end, auto_renew, purchase_token)
         VALUES (?, ?, 'active', datetime('now'), datetime('now', '+${periodMonths} months'), 1, ?)`
      ).run(accountId, productId, purchaseToken);

      db.prepare(
        `INSERT INTO \`order\` (account_id, product_type, product_id, amount_cents, purchase_token, status, paid_at)
         VALUES (?, 'subscription', ?, ?, ?, 'paid', datetime('now'))`
      ).run(accountId, productId, amountCents, purchaseToken);
    }

    const entitlement = getEntitlement(db, accountId);
    const passId = productType === 'pass' ? localTripId : null;

    res.json({ verified: true, entitlement, passId });
  } catch (err) {
    next(err);
  }
});

router.post('/notify', (req, res, next) => {
  try {
    console.log('[iap] notify received', JSON.stringify(req.body).slice(0, 200));
    res.status(200).json({});
  } catch (err) {
    next(err);
  }
});

export default router;