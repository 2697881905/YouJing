#!/usr/bin/env node
/**
 * 生图链路真调用探针（一次性付费调用，默认不跑）。
 *
 * 与 probe_llm_rules.mjs 同一套成本纪律：不带 --yes 只打印将要花的钱与请求规模，
 * 不发起任何上游调用。带 --yes 才走 BFF 的 proxyImageRequest，并断言响应可解码、
 * 体积在 4MB 上限内、prompt 仍是固定模板。
 *
 * 用法：
 *   node tools/probe_imagegen.mjs
 *   node tools/probe_imagegen.mjs --city 杨凌 --style geometry --yes
 */
import dotenv from '../bff/node_modules/dotenv/lib/main.js';
import { proxyImageRequest, validateImageRequest, buildImagePrompt } from '../bff/src/services/imagegen.js';

const args = process.argv.slice(2);
const cityArg = args.indexOf('--city');
const styleArg = args.indexOf('--style');
const city = cityArg >= 0 ? args[cityArg + 1] : '杨凌';
const style = styleArg >= 0 ? args[styleArg + 1] : 'geometry';
const confirmed = args.includes('--yes');

const guard = validateImageRequest({ city, style });
if (guard !== '') {
  console.error(`参数不合法：${guard}`);
  process.exit(2);
}

dotenv.config({ path: new URL('../bff/.env', import.meta.url).pathname });
const configured = process.env.IMAGEGEN_BASE_URL && process.env.IMAGEGEN_API_KEY && process.env.IMAGEGEN_MODEL;

console.log(`城市=${city} 风格=${style} 上游超时=${process.env.IMAGEGEN_TIMEOUT_MS || 30000}ms`);
console.log(`上游=${process.env.IMAGEGEN_BASE_URL || '未配置'} 模型=${process.env.IMAGEGEN_MODEL || '未配置'}`);
console.log(`prompt 长度=${buildImagePrompt(city, style).length} 字符`);
if (!configured) {
  console.error('IMAGEGEN_* 未配置（bff/.env），跳过调用');
  process.exit(2);
}
if (!confirmed) {
  console.log('这是付费调用：确认要跑请加 --yes。本次未发起任何请求。');
  process.exit(0);
}

const started = Date.now();
const result = await proxyImageRequest(city, style);
const bytes = Buffer.from(result.image, 'base64');
if (bytes.length !== result.bytes || bytes.length === 0 || bytes.length > 4 * 1024 * 1024) {
  console.error(`响应体积异常 bytes=${bytes.length} reported=${result.bytes}`);
  process.exit(1);
}
console.log(`PASS base64 可解码 bytes=${bytes.length} elapsed=${Date.now() - started}ms`);
