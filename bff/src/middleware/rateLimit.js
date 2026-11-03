/**
 * 按账号的固定窗口限流（部署前的成本防护）。
 *
 * 为什么放在生成路由上：一次生成会真金白银打上游模型；没有限流时，脚本循环点生成
 * 就能把额度/账单打满。默认 10 次/分钟，`RATE_LIMIT_PER_MINUTE` 与
 * `RATE_LIMIT_WINDOW_MS` 可调。超出回 429，端侧已有「请求太频繁 / 等一分钟再试」文案。
 *
 * 边界（写清楚，别当分布式限流）：状态在**进程内存**里，多实例部署时每个实例各算一份；
 * 要跨实例限流得换 Redis 等共享存储。IP 级限流仍属部署侧（反代/网关）职责。
 */
const DEFAULT_LIMIT = 10;
const DEFAULT_WINDOW_MS = 60000;

const buckets = new Map();

function limitPerWindow() {
  const raw = Number(process.env.RATE_LIMIT_PER_MINUTE);
  return Number.isFinite(raw) && raw > 0 ? raw : DEFAULT_LIMIT;
}

function windowMs() {
  const raw = Number(process.env.RATE_LIMIT_WINDOW_MS);
  return Number.isFinite(raw) && raw > 0 ? raw : DEFAULT_WINDOW_MS;
}

export function rateLimitMiddleware(req, res, next) {
  const key = String(req.accountId === undefined ? (req.ip || 'anon') : req.accountId);
  const now = Date.now();
  let bucket = buckets.get(key);
  if (bucket === undefined || now - bucket.start >= windowMs()) {
    bucket = { start: now, count: 0 };
    buckets.set(key, bucket);
  }
  bucket.count += 1;
  if (bucket.count > limitPerWindow()) {
    return res.status(429).json({
      error: 'RATE_LIMITED',
      message: '请求过于频繁，请稍后再试'
    });
  }
  return next();
}

/** 仅供测试：清空计数 */
export function resetRateLimit() {
  buckets.clear();
}
