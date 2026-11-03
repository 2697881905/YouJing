import { HttpError } from '../lib/http-error.js';

const DEFAULT_LLM_BASE_URL = 'https://api.deepseek.com/v1';
const DEFAULT_LLM_MODEL = 'deepseek-flash';

function llmConfig() {
  return {
    baseUrl: process.env.LLM_BASE_URL || DEFAULT_LLM_BASE_URL,
    apiKey: process.env.DEEPSEEK_API_KEY || '',
    model: process.env.LLM_MODEL || DEFAULT_LLM_MODEL
  };
}

/** 纯函数：请求体构造，便于测试 response_format 是否真的带上了 JSON Schema */
export function buildLlmRequestBody(messages, options = {}) {
  const body = {
    messages,
    model: options.model || llmConfig().model,
    max_tokens: options.maxTokens || 8192,
    response_format: options.responseFormat || { type: 'json_object' }
  };
  if (options.thinkingDisabled) {
    body.thinking = { type: 'disabled' };
  }
  return body;
}

export async function proxyLlmRequest(messages, options = {}) {
  const config = llmConfig();
  if (!config.apiKey) {
    throw new Error('LLM API key not configured');
  }

  const body = buildLlmRequestBody(messages, options);

  const resp = await fetch(`${config.baseUrl}/chat/completions`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${config.apiKey}`
    },
    body: JSON.stringify(body)
  });

  if (!resp.ok) {
    const text = await resp.text();
    console.log(`[llm] http=${resp.status} format=${body.response_format.type} ` +
      `error=${text.slice(0, 160)}`);
    // 上游限流要原样透出 429：端侧 `HttpLlmTransport` 对 429 → CLOUD_RATE_LIMITED(6003)
    // 有专门文案（「等一分钟再试；重试不会再扣一次额度」），此前被包成 502 后
    // 端上只能落 5xx 分支说「连不上行程服务」，用户会去查网络而不是等待。
    if (resp.status === 429) {
      throw new HttpError(429, 'LLM_RATE_LIMITED',
        `LLM upstream 429: ${text.slice(0, 200)}`);
    }
    throw new HttpError(502, 'LLM_UPSTREAM_ERROR',
      `LLM upstream ${resp.status}: ${text.slice(0, 200)}`);
  }

  const data = await resp.json();
  const content = data.choices?.[0]?.message?.content;
  if (!content) {
    throw new Error('LLM response missing choices[0].message.content');
  }
  console.log(`[llm] http=${resp.status} format=${body.response_format.type} ` +
    `model=${data.model || config.model} prompt_tokens=${data.usage?.prompt_tokens || 0} ` +
    `completion_tokens=${data.usage?.completion_tokens || 0}`);

  return {
    content,
    usage: {
      promptTokens: data.usage?.prompt_tokens || 0,
      completionTokens: data.usage?.completion_tokens || 0,
      model: data.model || config.model
    }
  };
}
