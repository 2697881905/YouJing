import jwt from 'jsonwebtoken';

function jwtSecret() {
  return process.env.JWT_SECRET || 'youjing-bff-dev-secret';
}

export function authMiddleware(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'TOKEN_INVALID', message: '缺少 Authorization 头' });
  }
  const token = authHeader.substring(7);
  try {
    const payload = jwt.verify(token, jwtSecret());
    req.accountId = payload.accountId;
    req.deviceId = payload.deviceId;
    next();
  } catch (err) {
    return res.status(401).json({ error: 'TOKEN_INVALID', message: '票据失效或无效' });
  }
}

export function issueToken(accountId, deviceId) {
  return jwt.sign({ accountId, deviceId }, jwtSecret(), { expiresIn: '30d' });
}