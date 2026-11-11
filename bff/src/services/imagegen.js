import { HttpError } from '../lib/http-error.js';

/**
 * 百度千帆（ModelBuilder / 文生图）代理，服务接口 Stable-Diffusion-XL。
 * 官方文档：https://ai.baidu.com/ai-doc/WENXINWORKSHOP/Klkqubb9w
 *
 * 与 OpenAI 兼容 images/generations 的差异（这是本文件的存在理由）：
 * - 鉴权是「应用 API Key + Secret Key → access_token」，token 放 Query，不是 Bearer 头；
 * - 请求体是 prompt / negative_prompt / size / n / steps，模型名在 URL 路径末段；
 * - 成功响应的图片在 data[0].b64_image，错误则是 HTTP 200 + error_code/error_msg。
 *
 * 边界（Docs/行后情绪方案.md §海报 / Docs/design-v2/DESIGN.md §AI poster base）：
 * - 端侧只发「城市 + 风格枚举」，prompt 由服务端按固定模板拼，客户端不能注入任意提示词；
 * - 上游 Key 只存服务端 env，绝不进发布包；access_token 只在进程内存缓存；
 * - 产物图片不落库、不进对象存储、不进 UGC，直接以 base64 回端侧内存；
 * - 同步一次、严格超时、不重试。任何失败由端侧降级回模板海报。
 */

const DEFAULT_TIMEOUT_MS = 30000;
const TOKEN_TIMEOUT_MS = 5000;
const DEFAULT_BASE_URL = 'https://aip.baidubce.com';
const DEFAULT_MODEL = 'sd_xl';
/** 官方文档列为「适用海报传单」的竖版尺寸，贴合 320vp 回顾卡 */
const SIZE = '768x1024';
// 只放字面空格，不放 \s：换行/制表符会被拼进服务端 prompt，等于给客户端开了注入口
const CITY_PATTERN = /^[\u4e00-\u9fa5A-Za-z0-9·\- ]{1,24}$/;
const STYLES = ['geometry', 'texture'];
/** 4MB 二进制上限；base64 约 5.6MB。超了直接判无效，避免把整张图读进内存 */
const MAX_IMAGE_BYTES = 4 * 1024 * 1024;
const MAX_BASE64_LENGTH = Math.ceil(MAX_IMAGE_BYTES * 4 / 3) + 2048;

let tokenCache = { token: '', expireAt: 0 };

/** 仅供测试：清空进程内 access_token 缓存 */
export function resetTokenCache() {
  tokenCache = { token: '', expireAt: 0 };
}

function config() {
  return {
    baseUrl: process.env.IMAGEGEN_BASE_URL || DEFAULT_BASE_URL,
    apiKey: process.env.IMAGEGEN_API_KEY || '',
    secretKey: process.env.IMAGEGEN_SECRET_KEY || '',
    model: process.env.IMAGEGEN_MODEL || DEFAULT_MODEL
  };
}

function timeoutMs() {
  const raw = Number(process.env.IMAGEGEN_TIMEOUT_MS);
  return Number.isFinite(raw) && raw > 0 ? raw : DEFAULT_TIMEOUT_MS;
}

function upstreamError(err, what, budget) {
  if (err && (err.name === 'TimeoutError' || err.name === 'AbortError')) {
    throw new HttpError(504, 'IMAGEGEN_TIMEOUT', `${what}超时 ${budget}ms`);
  }
  throw err;
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

/** 反向提示词比正面禁令更有效，且长度必须 <1024 字符。 */
export function buildNegativePrompt() {
  return '文字, 字母, 数字, 人物, 动物, 写实建筑, 摄影, 照片, 地图, 水印, logo, ' +
    '闪光, 渐变光效, 对话气泡, 高饱和新色相, 复杂细节';
}

export function buildImageRequestBody(city, style) {
  return {
    prompt: buildImagePrompt(city, style),
    negative_prompt: buildNegativePrompt(),
    size: SIZE,
    n: 1,
    steps: 20
  };
}

export function buildAccessTokenUrl(cfg) {
  const base = cfg.baseUrl.replace(/\/$/, '');
  return `${base}/oauth/2.0/token?grant_type=client_credentials` +
    `&client_id=${encodeURIComponent(cfg.apiKey)}&client_secret=${encodeURIComponent(cfg.secretKey)}`;
}

export function buildImageUrl(cfg, token) {
  const base = cfg.baseUrl.replace(/\/$/, '');
  return `${base}/rpc/2.0/ai_custom/v1/wenxinworkshop/text2image/` +
    `${encodeURIComponent(cfg.model)}?access_token=${encodeURIComponent(token)}`;
}

/** access_token 有效期通常 30 天，进程内缓存并提前 5 分钟刷新，避免每次生成多一次往返。 */
export async function getAccessToken(cfg, budgetMs) {
  if (tokenCache.token.length > 0 && Date.now() < tokenCache.expireAt) {
    return tokenCache.token;
  }
  const url = buildAccessTokenUrl(cfg);
  let resp;
  try {
    resp = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
      body: '""',
      signal: AbortSignal.timeout(budgetMs)
    });
  } catch (err) {
    upstreamError(err, '换取 access_token', budgetMs);
  }
  const text = await resp.text();
  if (!resp.ok) {
    throw new HttpError(502, 'IMAGEGEN_AUTH_ERROR',
      `access_token 接口 ${resp.status}: ${text.slice(0, 200)}`);
  }
  let data;
  try {
    data = JSON.parse(text);
  } catch (err) {
    throw new HttpError(502, 'IMAGEGEN_AUTH_ERROR', 'access_token 响应不是合法 JSON');
  }
  if (!data.access_token || data.error) {
    throw new HttpError(502, 'IMAGEGEN_AUTH_ERROR',
      `access_token 获取失败: ${data.error_description || data.error || '缺 access_token'}`);
  }
  const rawTtl = Number(data.expires_in);
  const ttl = Number.isFinite(rawTtl) && rawTtl > 0 ? rawTtl : 86400;
  tokenCache = {
    token: data.access_token,
    expireAt: Date.now() + Math.max(60, ttl - 300) * 1000
  };
  return tokenCache.token;
}

/**
 * 百度推理服务错误码的排查提示。
 * https://ai.baidu.com/ai-doc/WENXINWORKSHOP/tlmyncueh
 * 6 最常见：应用没勾选该接口，或定制服务未发布——控制台侧动作，改代码没用。
 */
const ERROR_HINTS = {
  3: '接口地址或模型名不存在，核对 IMAGEGEN_MODEL',
  6: '应用无该接口权限：千帆控制台 → 应用接入 → 编辑应用 → 勾选对应接口 → 更新；定制服务须处于「已发布」',
  17: '付费接口未开通 / 账户欠费 / 当日限额用尽',
  110: 'access_token 失效，检查 API Key 与 Secret Key 是否来自同一应用'
};

/** 上游响应 → base64 字符串；兼容百度 b64_image 与 OpenAI 风格 b64_json / url。 */
export function parseImagePayload(data) {
  if (data && (data.error_code !== undefined || data.error_msg !== undefined)) {
    const hint = ERROR_HINTS[String(data.error_code)] || '';
    const text = `上游错误 ${data.error_code ?? ''}: ${data.error_msg || ''}` +
      (hint.length > 0 ? ` | ${hint}` : '');
    throw new HttpError(502, 'IMAGEGEN_UPSTREAM_ERROR', text.slice(0, 320));
  }
  const first = data && Array.isArray(data.data) ? data.data[0] : null;
  if (!first) {
    throw new HttpError(502, 'IMAGEGEN_INVALID_RESPONSE', '上游未返回图片');
  }
  const raw = typeof first.b64_image === 'string' && first.b64_image.length > 0
    ? first.b64_image
    : (typeof first.b64_json === 'string' ? first.b64_json : '');
  if (raw.length > 0) {
    if (raw.length > MAX_BASE64_LENGTH) {
      throw new HttpError(502, 'IMAGEGEN_INVALID_RESPONSE', '上游图片体积超限');
    }
    const bytes = Buffer.from(raw, 'base64');
    if (bytes.length === 0 || bytes.length > MAX_IMAGE_BYTES) {
      throw new HttpError(502, 'IMAGEGEN_INVALID_RESPONSE', '上游图片为空或体积超限');
    }
    return { image: raw, bytes: bytes.length };
  }
  if (typeof first.url === 'string' && first.url.length > 0) {
    return { image: '', url: first.url };
  }
  throw new HttpError(502, 'IMAGEGEN_INVALID_RESPONSE', '上游既无 b64_image 也无 url');
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
  if (!cfg.apiKey || !cfg.secretKey || !cfg.model) {
    throw new HttpError(503, 'IMAGEGEN_NOT_CONFIGURED',
      '生图服务未配置 IMAGEGEN_API_KEY / IMAGEGEN_SECRET_KEY / IMAGEGEN_MODEL');
  }
  const timeout = timeoutMs();
  const started = Date.now();
  const token = await getAccessToken(cfg, Math.min(TOKEN_TIMEOUT_MS, timeout));
  const remaining = Math.max(1000, timeout - (Date.now() - started));
  const body = buildImageRequestBody(city, style);

  let resp;
  try {
    resp = await fetch(buildImageUrl(cfg, token), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(remaining)
    });
  } catch (err) {
    upstreamError(err, '生图上游', remaining);
  }

  const text = await resp.text();
  if (!resp.ok) {
    console.log(`[imagegen] http=${resp.status} error=${text.slice(0, 160)}`);
    if (resp.status === 429) {
      throw new HttpError(429, 'IMAGEGEN_RATE_LIMITED', `生图上游 429: ${text.slice(0, 200)}`);
    }
    throw new HttpError(502, 'IMAGEGEN_UPSTREAM_ERROR', `生图上游 ${resp.status}: ${text.slice(0, 200)}`);
  }
  let data;
  try {
    data = JSON.parse(text);
  } catch (err) {
    throw new HttpError(502, 'IMAGEGEN_INVALID_RESPONSE', '生图上游响应不是合法 JSON');
  }
  const parsed = parseImagePayload(data);
  const result = parsed.image ? parsed : await fetchUrlAsBase64(parsed.url, remaining);
  console.log(`[imagegen] model=${cfg.model} style=${style} bytes=${result.bytes} ` +
    `elapsed=${Date.now() - started}ms`);
  return {
    image: result.image,
    mime: 'image/png',
    model: cfg.model,
    bytes: result.bytes
  };
}
