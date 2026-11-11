import { HttpError } from '../lib/http-error.js';

/**
 * 回顾海报 AI 底图代理（OpenAI 兼容 images/generations）。
 *
 * 边界（Docs/行后情绪方案.md §海报 / Docs/design-v2/DESIGN.md §AI poster base）：
 * - 端侧只发「城市 + 风格枚举」，prompt 由服务端按固定模板拼，客户端不能注入任意提示词；
 * - 上游 Key 只存服务端 env，绝不进发布包；
 * - 产物图片不落库、不进对象存储、不进 UGC，直接以 base64 回端侧内存；
 * - 同步一次、严格超时、不重试。任何失败由端侧降级回模板海报。
 */

const DEFAULT_TIMEOUT_MS = 30000;
// 只放字面空格，不放 \s：换行/制表符会被拼进服务端 prompt，等于给客户端开了注入口
const CITY_PATTERN = /^[\u4e00-\u9fa5A-Za-z0-9·\- ]{1,24}$/;
const STYLES = ['geometry', 'texture'];
const SIZE = '1024x1024';
/** 4MB 二进制上限；base64 约 5.6MB。超了直接判无效，避免把整张图读进内存 */
const MAX_IMAGE_BYTES = 4 * 1024 * 1024;
const MAX_BASE64_LENGTH = Math.ceil(MAX_IMAGE_BYTES * 4 / 3) + 2048;

function config() {
  return {
    baseUrl: process.env.IMAGEGEN_BASE_URL || '',
    apiKey: process.env.IMAGEGEN_API_KEY || '',
    model: process.env.IMAGEGEN_MODEL || ''
  };
}

function timeoutMs() {
  const raw = Number(process.env.IMAGEGEN_TIMEOUT_MS);
  return Number.isFinite(raw) && raw > 0 ? raw : DEFAULT_TIMEOUT_MS;
}

/** 请求参数守卫：只放行白名单字段语义，坏请求不该烧一次上游调用。 */
export function validateImageRequest(body) {
  if (!body || typeof body !== 'object') {
    return '请求体必须是对象';
  }
  if (typeof body.city !== 'string' || !CITY_PATTERN.test(body.city)) {
    return 'city 必须是 1–24 个中英文/数字/空格字符';
  }
  if (typeof body.style !== 'string' || !STYLES.includes(body.style)) {
    return 'style 必须是 geometry 或 texture';
  }
  const keys = Object.keys(body).filter((key) => key !== 'city' && key !== 'style');
  if (keys.length > 0) {
    return '请求只允许 city 与 style 两个字段';
  }
  return '';
}

/**
 * 固定模板：AI 底图是品牌契约的成文例外，只能出抽象几何/纹理，
 * 不得引入新色相、摄影感、文字或人物（DESIGN.md §AI poster base）。
 */
export function buildImagePrompt(city, style) {
  const motif = style === 'texture'
    ? '低对比的细线纹理与纸张颗粒'
    : '扁平色块与圆角几何拼接';
  return `抽象旅行回顾海报底图，主题城市：${city}。${motif}；只使用品牌既有的五类活动色` +
    '与中性灰阶，不引入任何新色相，留白充足，中心区域保持低对比以便叠加衬线标题与数据。' +
    '禁止出现文字、字母、数字、人物、动物、写实建筑、摄影质感、地图、水印、logo 与聊天式闪光元素。' +
    '输出为竖版卡片背景，不是完整海报。';
}

export function buildImageRequestBody(city, style, options = {}) {
  return {
    model: options.model || config().model,
    prompt: buildImagePrompt(city, style),
    n: 1,
    size: SIZE,
    response_format: 'b64_json'
  };
}

/** 上游响应 → base64 字符串；不接受任意结构，也不接受超大图。 */
export function parseImagePayload(data) {
  const first = data && Array.isArray(data.data) ? data.data[0] : null;
  if (!first) {
    throw new HttpError(502, 'IMAGEGEN_INVALID_RESPONSE', '上游未返回图片');
  }
  if (typeof first.b64_json === 'string' && first.b64_json.length > 0) {
    if (first.b64_json.length > MAX_BASE64_LENGTH) {
      throw new HttpError(502, 'IMAGEGEN_INVALID_RESPONSE', '上游图片体积超限');
    }
    const bytes = Buffer.from(first.b64_json, 'base64');
    if (bytes.length === 0 || bytes.length > MAX_IMAGE_BYTES) {
      throw new HttpError(502, 'IMAGEGEN_INVALID_RESPONSE', '上游图片为空或体积超限');
    }
    return { image: first.b64_json, bytes: bytes.length };
  }
  if (typeof first.url === 'string' && first.url.length > 0) {
    return { image: '', url: first.url };
  }
  throw new HttpError(502, 'IMAGEGEN_INVALID_RESPONSE', '上游既无 b64_json 也无 url');
}

async function fetchUrlAsBase64(url, timeout) {
  const resp = await fetch(url, { signal: AbortSignal.timeout(timeout) });
  if (!resp.ok) {
    throw new HttpError(502, 'IMAGEGEN_INVALID_RESPONSE', `上游图片地址 ${resp.status}`);
  }
  const buf = Buffer.from(await resp.arrayBuffer());
  if (buf.length === 0 || buf.length > MAX_IMAGE_BYTES) {
    throw new HttpError(502, 'IMAGEGEN_INVALID_RESPONSE', '上游图片为空或体积超限');
  }
  return { image: buf.toString('base64'), bytes: buf.length };
}

export async function proxyImageRequest(city, style) {
  const cfg = config();
  if (!cfg.baseUrl || !cfg.apiKey || !cfg.model) {
    throw new HttpError(503, 'IMAGEGEN_NOT_CONFIGURED',
      '生图服务未配置 IMAGEGEN_BASE_URL / IMAGEGEN_API_KEY / IMAGEGEN_MODEL');
  }
  const timeout = timeoutMs();
  const started = Date.now();
  const body = buildImageRequestBody(city, style);

  let resp;
  try {
    resp = await fetch(`${cfg.baseUrl}/images/generations`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${cfg.apiKey}`
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(timeout)
    });
  } catch (err) {
    if (err && (err.name === 'TimeoutError' || err.name === 'AbortError')) {
      throw new HttpError(504, 'IMAGEGEN_TIMEOUT', `生图上游超时 ${timeout}ms`);
    }
    throw err;
  }

  if (!resp.ok) {
    const text = await resp.text();
    console.log(`[imagegen] http=${resp.status} error=${text.slice(0, 160)}`);
    if (resp.status === 429) {
      throw new HttpError(429, 'IMAGEGEN_RATE_LIMITED', `生图上游 429: ${text.slice(0, 200)}`);
    }
    throw new HttpError(502, 'IMAGEGEN_UPSTREAM_ERROR', `生图上游 ${resp.status}: ${text.slice(0, 200)}`);
  }

  const parsed = parseImagePayload(await resp.json());
  const result = parsed.image
    ? parsed
    : await fetchUrlAsBase64(parsed.url, timeout);
  console.log(`[imagegen] model=${cfg.model} style=${style} bytes=${result.bytes} ` +
    `elapsed=${Date.now() - started}ms`);
  return {
    image: result.image,
    mime: 'image/png',
    model: cfg.model,
    bytes: result.bytes
  };
}
