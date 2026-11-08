import { Router } from 'express';
import { proxyLlmRequest } from '../services/llm.js';
import { PromptBuilder } from '../prompt/index.js';
import { candidateIdsOf, guardPick, validatePickRequest } from '../services/pickGuard.js';
import { parseFirstJsonObject } from '../lib/json-extract.js';
import { HttpError } from '../lib/http-error.js';

const router = Router();

/**
 * P1 AI 精选：候选池 + 用户标签/天数/节奏 → 排序 + 每站一句理由。
 * 与行程生成共用同一份 prompt SOT（PromptBuilder）与同一个 LLM 代理；
 * 不扣生成额度（单次候选池小、成本极低），但仍走登录鉴权与限流。
 */
router.post('/spots', async (req, res, next) => {
  const body = req.body || {};
  const invalid = validatePickRequest(body);
  if (invalid !== '') {
    return res.status(400).json({ error: 'INVALID_REQUEST', message: invalid });
  }
  const messages = [
    { role: 'system', content: PromptBuilder.pickSystemPrompt() },
    { role: 'user', content: PromptBuilder.pickUserPrompt(body) }
  ];
  try {
    const out = await proxyLlmRequest(messages, { maxTokens: 2048 });
    let raw = null;
    try {
      raw = JSON.parse(out.content);
    } catch (err) {
      raw = parseFirstJsonObject(out.content);
    }
    if (raw === null) {
      throw new HttpError(422, 'DECISION_REJECTED', '模型输出不是 JSON');
    }
    const decision = guardPick(raw, candidateIdsOf(body));
    console.log(`[pick] account=${req.accountId} candidates=${body.candidates.length} ` +
      `ranked=${decision.ranked.length}`);
    res.json(decision);
  } catch (err) {
    next(err);
  }
});

export default router;
