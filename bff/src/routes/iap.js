import { Router } from 'express';
import { verifyPurchase } from '../services/iap.js';
import { getEntitlement } from '../services/quota.js';
import { applyNotification, notifySignatureOk } from '../services/iapNotify.js';

const router = Router();

router.post('/verify', async (req, res, next) => {
  try {
    const db = req.db;
    const { purchaseToken, productType, localTripId } = req.body;

    if (typeof purchaseToken !== 'string' || purchaseToken.length === 0 ||
      purchaseToken.length > 2048) {
      return res.status(400).json({ error: 'INVALID_PURCHASE_TOKEN', message: '缺少或非法的 purchaseToken' });
    }
    if (typeof productType !== 'string' || productType.length === 0) {
      return res.status(400).json({ error: 'MISSING_PARAMS', message: '缺少 purchaseToken 或 productType' });
    }
    // 边界校验放在调用校验服务之前：非法商品类型/商品 id 不该先花一次外部校验。
    if (productType !== 'pass' && productType !== 'subscription') {
      return res.status(400).json({
        error: 'UNSUPPORTED_PRODUCT_TYPE',
        message: `不支持的 productType '${productType}'`
      });
    }
    const requestedProductId = req.body.productId || 'youjing_sub_monthly';
    if (productType === 'subscription' &&
      requestedProductId !== 'youjing_sub_monthly' && requestedProductId !== 'youjing_sub_yearly') {
      return res.status(400).json({
        error: 'UNKNOWN_PRODUCT_ID',
        message: `未知订阅商品 '${requestedProductId}'`
      });
    }

    const iapResult = await verifyPurchase(purchaseToken, productType);
    if (!iapResult.verified) {
      // 未配置校验服务是**部署态问题**（503），不是"这张收据无效"（200 verified:false）。
      // 两种都必须拒绝入库——fail-closed 的方向是拒真，不是收假。
      if (iapResult.reason === 'IAP_NOT_CONFIGURED') {
        return res.status(503).json({ verified: false, error: 'IAP_NOT_CONFIGURED', message: '收据校验服务未配置' });
      }
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

    // 收据只能绑定一个账号：同一张收据换账号再提交必须拒绝。
    // 改前通行证分支先插 `trip_pass` 再查 `order`，订单虽然不重复记账，
    // 但第二个人照样白拿一张 active 通行证（收据一旦泄露就能被多人复用）。
    const receiptOwner = db.prepare(
      'SELECT account_id, status FROM `order` WHERE purchase_token = ?'
    ).get(purchaseToken);
    if (receiptOwner && receiptOwner.account_id !== accountId) {
      return res.status(409).json({
        error: 'RECEIPT_ALREADY_USED',
        message: '该收据已绑定其他账号'
      });
    }
    // 已退款的收据不能再次兑换：否则端侧会显示"购买成功"但权益是空的
    if (receiptOwner && receiptOwner.status === 'refunded') {
      return res.status(200).json({ verified: false, message: '该收据已退款' });
    }

    if (productType === 'pass') {
      if (typeof localTripId !== 'string' || localTripId.trim().length === 0 ||
        localTripId.length > 128) {
        return res.status(400).json({ error: 'MISSING_TRIP_ID', message: '通行证购买需提供合法 localTripId' });
      }
      const existingPass = db.prepare(
        'SELECT * FROM trip_pass WHERE account_id = ? AND local_trip_id = ? AND status = ?'
      ).get(accountId, localTripId, 'active');

      if (!existingPass) {
        db.prepare(
          `INSERT OR IGNORE INTO trip_pass (account_id, local_trip_id, status)
           VALUES (?, ?, 'active')`
        ).run(accountId, localTripId);
      }

      // 同一张收据重复提交（客户端重试、网络抖动后的重放）必须幂等：
      // 收据是唯一凭据，第二次不该再记一笔订单，更不该把 UNIQUE 约束抛成 500（§5ci 续 85 的 D8）。
      const seenPass = db.prepare(
        'SELECT 1 FROM `order` WHERE purchase_token = ?'
      ).get(purchaseToken);
      if (!seenPass) {
        db.prepare(
          `INSERT OR IGNORE INTO \`order\` (account_id, product_type, product_id, amount_cents, purchase_token, status, paid_at)
           VALUES (?, 'pass', 'youjing_pass', 990, ?, 'paid', datetime('now'))`
        ).run(accountId, purchaseToken);
      }

      // 退款回调只拿得到收据号，要把订单绑回这张通行证才撤得掉（D7）。
      // 老订单没有这层绑定，退款只能记一笔 `NO_ORDER` 之外的 orphan 日志——已买的通行证不会被误撤。
      const orderRow = db.prepare('SELECT id FROM `order` WHERE purchase_token = ?').get(purchaseToken);
      if (orderRow) {
        db.prepare(
          'UPDATE trip_pass SET order_id = ? WHERE account_id = ? AND local_trip_id = ? AND order_id IS NULL'
        ).run(orderRow.id, accountId, localTripId);
      }
    } else if (productType === 'subscription') {
      const productId = requestedProductId;
      const amountCents = productId === 'youjing_sub_yearly' ? 9800 : 1990;
      const periodMonths = productId === 'youjing_sub_yearly' ? 12 : 1;

      // 同上：subscription.purchase_token 有 UNIQUE 约束，重放会直接 500。
      const seenSub = db.prepare(
        'SELECT 1 FROM subscription WHERE purchase_token = ?'
      ).get(purchaseToken);
      if (!seenSub) {
        db.prepare(
          `INSERT OR IGNORE INTO subscription (account_id, product_id, status, period_start, period_end, auto_renew, purchase_token)
           VALUES (?, ?, 'active', datetime('now'), datetime('now', '+${periodMonths} months'), 1, ?)`
        ).run(accountId, productId, purchaseToken);

        db.prepare(
          `INSERT OR IGNORE INTO \`order\` (account_id, product_type, product_id, amount_cents, purchase_token, status, paid_at)
           VALUES (?, 'subscription', ?, ?, ?, 'paid', datetime('now'))`
        ).run(accountId, productId, amountCents, purchaseToken);
      }
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
    const rawBody = req.rawBody || Buffer.from(JSON.stringify(req.body || {}));
    const signature = notifySignatureOk(
      rawBody, req.headers.authorization, process.env.IAP_NOTIFY_PUBLIC_KEY
    );
    if (!signature.ok) {
      // NOT_CONFIGURED 是部署态问题（503），其余是这条请求不被信任（401）
      const status = signature.reason === 'NOT_CONFIGURED' ? 503 : 401;
      console.warn('[iap] notify rejected', signature.reason);
      return res.status(status).json({ error: 'NOTIFY_' + signature.reason });
    }

    const result = applyNotification(req.db, req.body || {}, rawBody);
    console.log('[iap] notify', result.kind, result.reason || 'applied', 'applied=' + result.applied);
    res.status(200).json({ ok: true, applied: result.applied, kind: result.kind });
  } catch (err) {
    next(err);
  }
});

export default router;