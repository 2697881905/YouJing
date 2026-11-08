/**
 * P1 AI 精选的请求/响应守卫（纯函数，可离线断言）。
 * 模型只能在候选池内排序，不得新增 id——这一层挡住任何"编一个景点"的输出。
 */

const MAX_CANDIDATES = 40;
const MAX_REASON = 80;
const MAX_NOTE = 200;

export function validatePickRequest(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    return 'body 必须是对象';
  }
  if (typeof body.city !== 'string' || body.city.trim().length === 0) {
    return 'city 必须是非空字符串';
  }
  if (!Number.isInteger(body.days) || body.days < 1 || body.days > 30) {
    return 'days 必须是 1–30 的整数';
  }
  if (typeof body.pace !== 'string') {
    return 'pace 必须是字符串';
  }
  if (typeof body.interests !== 'string') {
    return 'interests 必须是字符串';
  }
  if (!Array.isArray(body.candidates) || body.candidates.length === 0) {
    return 'candidates 不能为空';
  }
  if (body.candidates.length > MAX_CANDIDATES) {
    return `candidates 最多 ${MAX_CANDIDATES} 个`;
  }
  const ids = new Set();
  for (const c of body.candidates) {
    if (!c || typeof c !== 'object') {
      return 'candidate 必须是对象';
    }
    if (typeof c.id !== 'string' || c.id.length === 0) {
      return 'candidate.id 非法';
    }
    if (ids.has(c.id)) {
      return 'candidate.id 重复';
    }
    if (typeof c.name !== 'string' || c.name.length === 0) {
      return 'candidate.name 非法';
    }
    if (typeof c.tag !== 'string' || typeof c.brief !== 'string' ||
        typeof c.district !== 'string') {
      return 'candidate 文本字段非法';
    }
    if (!Number.isFinite(c.popularity) || !Number.isFinite(c.suggestedDuration)) {
      return 'candidate 数值字段非法';
    }
    if (typeof c.requiresBooking !== 'boolean') {
      return 'candidate.requiresBooking 非法';
    }
    ids.add(c.id);
  }
  return '';
}

export function candidateIdsOf(body) {
  return body.candidates.map((c) => c.id);
}

export function guardPick(raw, candidateIds) {
  if (!raw || typeof raw !== 'object') {
    throw new Error('decision 不是对象');
  }
  if (!Array.isArray(raw.ranked)) {
    throw new Error('ranked 缺失');
  }
  if (raw.ranked.length !== candidateIds.length) {
    throw new Error('ranked 必须覆盖全部候选');
  }
  const allowed = new Set(candidateIds);
  const seen = new Set();
  const ranked = [];
  for (const item of raw.ranked) {
    if (!item || typeof item.id !== 'string' || !allowed.has(item.id)) {
      throw new Error('ranked.id 不在候选内');
    }
    if (seen.has(item.id)) {
      throw new Error('ranked.id 重复');
    }
    const reason = typeof item.reason === 'string' ? item.reason.trim() : '';
    if (reason.length > MAX_REASON) {
      throw new Error('reason 超长');
    }
    seen.add(item.id);
    ranked.push({ id: item.id, reason: reason });
  }
  const note = typeof raw.note === 'string' ? raw.note.trim() : '';
  if (note.length > MAX_NOTE) {
    throw new Error('note 超长');
  }
  return { ranked: ranked, note: note };
}
