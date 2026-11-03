import { createHash } from 'node:crypto';

/**
 * 规范化 JSON：对象键排序、忽略 undefined 键；数组保持顺序。
 * 目的：同一份语义请求不因键顺序不同被判成两个请求。
 */
export function canonicalJson(value) {
  if (value === undefined) {
    return 'null';
  }
  if (value === null || typeof value === 'number' || typeof value === 'boolean') {
    return JSON.stringify(value);
  }
  if (typeof value === 'string') {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map((item) => canonicalJson(item)).join(',')}]`;
  }
  if (typeof value === 'object') {
    const keys = Object.keys(value)
      .filter((key) => value[key] !== undefined)
      .sort();
    return `{${keys.map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(',')}}`;
  }
  throw new Error(`canonicalJson: 不支持的类型 ${typeof value}`);
}

export function requestHash(body) {
  return createHash('sha256').update(canonicalJson(body)).digest('hex');
}

/** 账号/设备 + 客户端 Idempotency-Key 组成数据库主键，避免跨用户撞键 */
export function scopeKey(accountId, clientKey) {
  return createHash('sha256').update(`${String(accountId)}\n${String(clientKey)}`).digest('hex');
}

function replay(res, row) {
  if (typeof res.set === 'function') {
    res.set('Idempotency-Replayed', 'true');
  }
  let body;
  try {
    body = JSON.parse(row.response_json);
  } catch (err) {
    return res.status(500).json({
      error: 'IDEMPOTENCY_STATE_CORRUPT',
      message: '首次响应体无法解析，拒绝用错误数据重放'
    });
  }
  return res.status(200).json(body);
}

export function idempotencyMiddleware(req, res, next) {
  const rawKey = req.headers ? req.headers['idempotency-key'] : undefined;
  const clientKey = Array.isArray(rawKey) ? rawKey[0] : rawKey;
  if (!clientKey || String(clientKey).length === 0) {
    return res.status(400).json({
      error: 'MISSING_IDEMPOTENCY_KEY',
      message: '缺少 Idempotency-Key 头'
    });
  }

  const accountId = req.accountId ?? req.deviceId;
  if (accountId === undefined || accountId === null || String(accountId).length === 0) {
    return res.status(401).json({
      error: 'TOKEN_INVALID',
      message: '缺少账号/设备标识，无法确定幂等作用域'
    });
  }

  const key = scopeKey(accountId, clientKey);
  const hash = requestHash(req.body ?? {});
  req.idempotencyKey = key;
  req.clientIdempotencyKey = String(clientKey);
  req.requestHash = hash;

  const row = req.db.prepare(
    `SELECT idempotency_key, account_id, request_hash, status, response_json
     FROM trip_request WHERE idempotency_key = ? AND account_id = ?`
  ).get(key, accountId);

  if (!row) {
    return next();
  }

  // 同一把 key 换了请求体：绝不重放旧结果，也不覆盖旧行
  if (row.request_hash !== hash) {
    return res.status(422).json({
      error: 'IDEMPOTENCY_KEY_REUSED',
      message: '同一 Idempotency-Key 对应不同请求体；请换一个新 key'
    });
  }

  if (row.status === 'succeeded') {
    if (!row.response_json) {
      return res.status(500).json({
        error: 'IDEMPOTENCY_STATE_CORRUPT',
        message: '首次响应体缺失，拒绝返回请求参数冒充 trip'
      });
    }
    return replay(res, row);
  }

  if (row.status === 'pending') {
    return res.status(409).json({
      error: 'IDEMPOTENCY_IN_PROGRESS',
      message: '同一 Idempotency-Key 的请求正在处理中，请稍后重试'
    });
  }

  if (row.status === 'failed') {
    // 失败已释放配额；同体同键允许复用这一行重跑，不同体在上面已 422
    req.idempotencyExisting = row;
    return next();
  }

  return res.status(500).json({
    error: 'IDEMPOTENCY_STATE_CORRUPT',
    message: `未知的幂等状态 ${row.status}`
  });
}
