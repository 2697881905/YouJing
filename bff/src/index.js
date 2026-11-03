import express from 'express';
import dotenv from 'dotenv';
import { initDb } from './db.js';
import { authMiddleware } from './middleware/auth.js';
import { rateLimitMiddleware } from './middleware/rateLimit.js';
import deviceRouter from './routes/device.js';
import entitlementRouter from './routes/entitlement.js';
import tripRouter from './routes/trip.js';
import iapRouter from './routes/iap.js';

dotenv.config();

const PORT = process.env.PORT || 3000;
const db = initDb();

const app = express();
// /v1/iap/notify 要对**原始字节**验 RSA 签名，重序列化后的 body 与华为签的对不上
app.use(express.json({
  limit: '2mb',
  verify: (req, _res, buf) => { req.rawBody = buf; }
}));

app.use((req, _res, next) => {
  req.db = db;
  next();
});

app.get('/health', (_req, res) => {
  // 真查一次库：只回静态 ok 时，DB 损坏/只读也会被负载均衡当成健康实例。
  try {
    db.prepare('SELECT 1 AS ok').get();
    res.json({ status: 'ok', db: 'ok' });
  } catch (err) {
    console.error('[health] db check failed:', err.message);
    res.status(503).json({ status: 'degraded', db: 'error' });
  }
});

app.use('/v1/device', deviceRouter);
app.use('/v1/entitlement', authMiddleware, entitlementRouter);
app.use('/v1/trip', authMiddleware, rateLimitMiddleware, tripRouter);
app.use('/v1/iap', iapRouter);

app.use((err, _req, res, _next) => {
  console.error('[error]', err.message);
  const status = err.status || 500;
  const code = err.code || 'INTERNAL_ERROR';
  res.status(status).json({ error: code, message: err.message });
});

app.listen(PORT, () => {
  console.log(`[bff] listening on :${PORT}`);
});