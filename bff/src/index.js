import express from 'express';
import dotenv from 'dotenv';
import { initDb } from './db.js';
import { authMiddleware } from './middleware/auth.js';
import deviceRouter from './routes/device.js';
import entitlementRouter from './routes/entitlement.js';
import tripRouter from './routes/trip.js';
import iapRouter from './routes/iap.js';

dotenv.config();

const PORT = process.env.PORT || 3000;
const db = initDb();

const app = express();
app.use(express.json({ limit: '2mb' }));

app.use((req, _res, next) => {
  req.db = db;
  next();
});

app.get('/health', (_req, res) => {
  res.json({ status: 'ok' });
});

app.use('/v1/device', deviceRouter);
app.use('/v1/entitlement', authMiddleware, entitlementRouter);
app.use('/v1/trip', authMiddleware, tripRouter);
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