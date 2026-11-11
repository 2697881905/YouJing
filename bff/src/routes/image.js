import { Router } from 'express';
import { getEntitlement } from '../services/quota.js';
import { validateImageRequest, proxyImageRequest } from '../services/imagegen.js';

/**
 * POST /v1/image/generate —— 回顾海报 AI 底图。
 *
 * 与 /v1/trip/generate 的区别是刻意的：这里不挂幂等、不扣额度、不写 trip_request。
 * 生图是订阅者权益内的同步增强（2026-11-11 决策），失败即降级模板海报，
 * 成本防护由账号级 rateLimit + 服务端严格超时承担。产物不落库、不进对象存储。
 */

/** 订阅门禁的纯判定：getEntitlement 已按 active + period_end >= now 过滤。 */
export function subscriptionAllowsImage(entitlement) {
  return !!(entitlement && entitlement.subscription);
}

const router = Router();

router.post('/generate', async (req, res, next) => {
  try {
    const body = req.body || {};
    const guardError = validateImageRequest(body);
    if (guardError !== '') {
      return res.status(400).json({ error: 'INVALID_REQUEST', message: guardError });
    }

    // 服务端口径是硬门禁：端侧 canExportPoster 只看本机缓存，可能被过期订阅骗过。
    const entitlement = getEntitlement(req.db, req.accountId);
    if (!subscriptionAllowsImage(entitlement)) {
      return res.status(402).json({
        error: 'SUBSCRIPTION_REQUIRED',
        message: '生成配图仅对有效订阅开放'
      });
    }

    const result = await proxyImageRequest(body.city, body.style);
    return res.json(result);
  } catch (err) {
    return next(err);
  }
});

export default router;
