import { Router } from 'express';
import { getEntitlement } from '../services/quota.js';

const router = Router();

router.get('/', (req, res, next) => {
  try {
    const entitlement = getEntitlement(req.db, req.accountId);
    res.json(entitlement);
  } catch (err) {
    next(err);
  }
});

export default router;