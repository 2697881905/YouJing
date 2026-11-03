import { Router } from 'express';
import { idempotencyMiddleware } from '../middleware/idempotency.js';
import {
  getEntitlement, reserveQuota, commitQuota, releaseQuota, determineQuotaSource
} from '../services/quota.js';
import { proxyLlmRequest } from '../services/llm.js';
import { buildMessages, buildResponseFormat, expectedDayCount, promptMode } from '../prompt/index.js';
import { validateTrip } from '../prompt/trip-validator.js';
import { parseFirstJsonObject } from '../lib/json-extract.js';
import { HttpError } from '../lib/http-error.js';

const router = Router();

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

/**
 * 生成请求的核心参数边界。放在扣额度/打上游之前：坏请求既不该烧一次模型调用，
 * 也不该因为 undefined 日期把提示词拼成"计划天数：1 天"再产出 garbage。
 * 返回 '' 表示通过，否则是用给客户端看的错误说明。
 */
/**
 * 解析模型输出：先严格 JSON.parse；失败再尝试提取第一个完整对象（尾部说明/围栏）。
 * 仍失败返回 error，由路由决定是否发起一次修正调用。
 */
function parseTripContent(content) {
  try {
    return { trip: JSON.parse(content), error: '' };
  } catch (err) {
    const salvaged = parseFirstJsonObject(content);
    if (salvaged !== null) {
      console.log('[trip] json salvaged：模型在 JSON 之后附带了额外内容，已取第一个完整对象');
      return { trip: salvaged, error: '' };
    }
    return { trip: null, error: err.message };
  }
}

function validateGenerateRequest(body) {
  if (typeof body.destination !== 'string' || body.destination.trim().length === 0) {
    return 'destination 必须是非空字符串';
  }
  if (typeof body.startDate !== 'string' || ISO_DATE.test(body.startDate) === false) {
    return 'startDate 必须是 YYYY-MM-DD';
  }
  if (typeof body.endDate !== 'string' || ISO_DATE.test(body.endDate) === false) {
    return 'endDate 必须是 YYYY-MM-DD';
  }
  if (body.endDate < body.startDate) {
    return 'endDate 不能早于 startDate';
  }
  if (!Number.isInteger(body.people) || body.people < 1 || body.people > 30) {
    return 'people 必须是 1–30 的整数';
  }
  if (!Number.isInteger(body.budget) || body.budget < 0) {
    return 'budget 必须是非负整数';
  }
  return '';
}

router.post('/generate', idempotencyMiddleware, async (req, res, next) => {
  const db = req.db;
  const accountId = req.accountId;
  const idempotencyKey = req.idempotencyKey;
  const requestHash = req.requestHash;
  const body = req.body || {};
  const guardError = validateGenerateRequest(body);
  if (guardError !== '') {
    return res.status(400).json({ error: 'INVALID_REQUEST', message: guardError });
  }

  const quotaSource = determineQuotaSource(db, accountId, body.passId);
  if (!quotaSource) {
    return res.status(402).json({ error: 'QUOTA_EXHAUSTED', message: '额度已用尽' });
  }

  try {
    reserveQuota(db, accountId, idempotencyKey, quotaSource);
    // 失败行允许同键同体重跑；成功后响应体写回同一行，供幂等重放。
    // WHERE status='failed' 让并发请求无法各自拿到“认领成功”：同一 key 只有
    // 一个请求能把行变成 pending，另一个 changes=0，直接 409，避免双扣费/双写。
    const claim = db.prepare(
      `INSERT INTO trip_request
       (account_id, idempotency_key, request_hash, params_json, status, started_at)
       VALUES (?, ?, ?, ?, 'pending', datetime('now'))
       ON CONFLICT(idempotency_key) DO UPDATE SET
         status = 'pending',
         request_hash = excluded.request_hash,
         params_json = excluded.params_json,
         started_at = excluded.started_at,
         finished_at = NULL,
         error_code = NULL,
         response_json = NULL
       WHERE trip_request.status = 'failed'`
    ).run(accountId, idempotencyKey, requestHash, JSON.stringify(body));
    if (claim.changes === 0) {
      return res.status(409).json({
        error: 'IDEMPOTENCY_IN_PROGRESS',
        message: '同一 Idempotency-Key 已被另一请求占用，请稍后重试'
      });
    }
  } catch (err) {
    releaseQuota(db, idempotencyKey);
    return next(err);
  }

  try {
    // 免费档判据由**实际扣费来源**决定，不信客户端自报：端侧只看「有没有订阅」，
    // 通行证买家（付费、无订阅）会被算成免费档 ⇒ 8192 token 上限 + 精简提示词，
    // 长行程可能被截断后又重试。gift 才是免费档，subscription/pass 都是付费档。
    const freeTier = quotaSource === 'gift';
    const messages = buildMessages(body, { freeTier });
    const responseFormat = buildResponseFormat();
    console.log(`[trip] account=${accountId} prompt=${promptMode(body)} source=${quotaSource} ` +
      `freeTier=${freeTier} response_format=${responseFormat.type}`);
    const callOptions = {
      maxTokens: freeTier ? 8192 : 16384,
      thinkingDisabled: true,
      responseFormat
    };
    let llmResult = await proxyLlmRequest(messages, callOptions);
    let parsed = parseTripContent(llmResult.content);
    if (parsed.trip === null) {
      // 长行程实测（2026-11-03，7 天 MapKit）：模型偶发输出中途坏掉的 JSON
      //（Expected double-quoted property name at position 3336）。原样重试多半还会坏，
      // 这里带一条修正指令再问一次；仍只扣一次额度。
      // 修正调用把 token 预算抬到 16384：免费档 8192 如果是被 length 截断，原预算重问会再截一次。
      console.log(`[trip] json invalid（finish=${llmResult.usage.finishReason || '?'}），发起修正调用: ${parsed.error}`);
      const repairMessages = messages.concat([
        { role: 'assistant', content: String(llmResult.content).slice(0, 12000) },
        {
          role: 'user',
          content: `上面的输出不是合法的 JSON 对象（解析错误：${parsed.error}）。` +
            '请只输出修正后的完整 JSON：字符串内不要出现英文双引号或反斜杠，不要输出任何解释或代码围栏。'
        }
      ]);
      const repairOptions = Object.assign({}, callOptions, {
        maxTokens: Math.max(callOptions.maxTokens, 16384)
      });
      const repaired = await proxyLlmRequest(repairMessages, repairOptions);
      llmResult = {
        content: repaired.content,
        usage: {
          promptTokens: (llmResult.usage.promptTokens || 0) + (repaired.usage.promptTokens || 0),
          completionTokens: (llmResult.usage.completionTokens || 0) + (repaired.usage.completionTokens || 0),
          model: repaired.usage.model
        }
      };
      parsed = parseTripContent(llmResult.content);
    }
    if (parsed.trip === null) {
      throw new HttpError(502, 'LLM_INVALID_JSON',
        `模型输出不是合法 JSON（修正后仍失败）: ${String(llmResult.content).slice(0, 160)}`);
    }
    const trip = parsed.trip;

    const check = validateTrip(trip, {
      days: expectedDayCount(body),
      startDate: body.startDate
    });
    if (!check.valid) {
      throw new HttpError(502, 'LLM_INVALID_TRIP', check.errors.slice(0, 8).join('; '));
    }

    // 结算、状态与响应体写入同一事务：要么都成功，要么都不落。
    // 权益快照必须在 status='succeeded' 之后读：giftRemaining 依赖 committed 账本，
    // usedToday 依赖当天的 succeeded 行；否则返回给客户端的是扣减前的旧值。
    const finish = db.transaction(() => {
      commitQuota(db, idempotencyKey);
      const updated = db.prepare(
        `UPDATE trip_request SET status = 'succeeded', prompt_tokens = ?, completion_tokens = ?,
         model = ?, finished_at = datetime('now')
         WHERE idempotency_key = ? AND account_id = ?`
      ).run(
        llmResult.usage.promptTokens || 0,
        llmResult.usage.completionTokens || 0,
        llmResult.usage.model || '',
        idempotencyKey,
        accountId
      );
      if (updated.changes !== 1) {
        throw new Error('trip_request 幂等行更新失败，拒绝返回未持久化的响应');
      }

      const entitlement = getEntitlement(db, accountId);
      const responseBody = {
        trip,
        quota: {
          source: quotaSource,
          remainingToday: entitlement.usedToday,
          giftRemaining: entitlement.giftRemaining,
          passes: entitlement.passes,
          // 订阅快照必须回传（D9）：端侧此前只能把旧 subscription 原样结转，
          // 到期/退款后要等缓存自然失效，UI 会继续说"订阅有效"。
          subscription: entitlement.subscription,
          dailyCap: entitlement.dailyCap
        }
      };
      const responseJson = JSON.stringify(responseBody);
      const saved = db.prepare(
        `UPDATE trip_request SET response_json = ?
         WHERE idempotency_key = ? AND account_id = ?`
      ).run(responseJson, idempotencyKey, accountId);
      if (saved.changes !== 1) {
        throw new Error('trip_request 响应体写入失败，拒绝返回未持久化的响应');
      }
      return responseBody;
    });
    const responseBody = finish();

    res.json(responseBody);
  } catch (llmErr) {
    releaseQuota(db, idempotencyKey);
    db.prepare(
      `UPDATE trip_request SET status = 'failed', error_code = ?, finished_at = datetime('now')
       WHERE idempotency_key = ? AND account_id = ?`
    ).run(
      typeof llmErr.status === 'number' ? llmErr.status : 500,
      idempotencyKey,
      accountId
    );
    next(llmErr);
  }
});

export default router;
