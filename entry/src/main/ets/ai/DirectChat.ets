/**
 * 端侧直连 OpenAI 兼容 chat/completions 的唯一 HTTP 收口。
 *
 * 生成（LlmClient.DirectLlmTransport）与 AI 精选（PickClient）共用：
 * 提示词仍由各自 SOT 构造，这里只负责鉴权头、超时、信封解析与用量日志。
 * Key 只在 DirectConfig 本机填写；DirectConfig.URL/KEY 任一为空即视为未配置。
 */

import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ApiConfig } from '../common/config/ApiConfig';
import { DirectConfig } from '../common/config/DirectConfig';
import { AppError } from '../common/error/AppError';
import { ErrorCode } from '../common/error/ErrorCode';
import { Logger } from '../common/logger/Logger';

const TAG: string = 'Ai.DirectChat';

export interface DirectChatMessage {
  role: string;
  content: string;
}

export interface DirectChatResult {
  /** 已剥掉 Markdown 围栏/前后解释的 JSON 字符串 */
  json: string;
  model: string;
  promptTokens: number;
  completionTokens: number;
}

interface DirectUsage {
  prompt_tokens?: number;
  completion_tokens?: number;
}

interface DirectChoice {
  message?: DirectChatMessage;
}

interface DirectLlmResponse {
  model?: string;
  usage?: DirectUsage;
  choices?: DirectChoice[];
}

interface DirectResponseFormat {
  type: string;
}

interface DirectLlmRequest {
  model: string;
  temperature: number;
  max_tokens: number;
  response_format: DirectResponseFormat;
  messages: DirectChatMessage[];
}

export class DirectChat {
  static isConfigured(): boolean {
    return DirectConfig.URL.length > 0 && DirectConfig.KEY.length > 0;
  }

  static async complete(messages: DirectChatMessage[], maxTokens: number,
    readTimeoutMs: number): Promise<DirectChatResult> {
    if (!DirectChat.isConfigured()) {
      throw new AppError(ErrorCode.LLM_UNAVAILABLE, '端侧直连未配置（DirectConfig.URL/KEY）');
    }
    const payload: DirectLlmRequest = {
      model: DirectConfig.MODEL,
      temperature: 0.2,
      max_tokens: maxTokens,
      response_format: { type: 'json_object' },
      messages: messages
    };
    const reqHandle = http.createHttp();
    try {
      const headers: Record<string, string> = {};
      headers['Content-Type'] = 'application/json';
      headers['Authorization'] = `Bearer ${DirectConfig.KEY}`;
      const resp: http.HttpResponse = await reqHandle.request(DirectConfig.URL, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify(payload),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: ApiConfig.CONNECT_TIMEOUT_MS,
        readTimeout: readTimeoutMs
      });
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        const code: number = resp.responseCode;
        const raw: string = String(resp.result).slice(0, 200);
        throw new AppError(ErrorCode.LLM_UNAVAILABLE, `直连 LLM HTTP ${code}: ${raw}`);
      }
      const data: DirectLlmResponse = JSON.parse(String(resp.result)) as DirectLlmResponse;
      const choices: DirectChoice[] = data.choices === undefined ? [] : data.choices;
      const first: DirectChoice | undefined = choices.length > 0 ? choices[0] : undefined;
      let content: string = '';
      if (first !== undefined && first.message !== undefined && first.message.content !== undefined) {
        content = first.message.content;
      }
      if (content.length === 0) {
        throw new AppError(ErrorCode.LLM_UNAVAILABLE, '直连 LLM 响应缺少 choices[0].message.content');
      }
      const model: string = data.model === undefined ? DirectConfig.MODEL : data.model;
      const usage: DirectUsage = data.usage === undefined ? {} : data.usage;
      const promptTokens: number = usage.prompt_tokens === undefined ? 0 : usage.prompt_tokens;
      const completionTokens: number = usage.completion_tokens === undefined ? 0 : usage.completion_tokens;
      Logger.info(TAG, `LLM 用量 model=${model} prompt_tokens=${promptTokens} ` +
        `completion_tokens=${completionTokens}`);
      const start: number = content.indexOf('{');
      const end: number = content.lastIndexOf('}');
      if (start < 0 || end <= start) {
        throw new AppError(ErrorCode.SCHEMA_VALIDATION_FAILED, '直连 LLM 输出没有 JSON 对象');
      }
      return {
        json: content.slice(start, end + 1),
        model: model,
        promptTokens: promptTokens,
        completionTokens: completionTokens
      };
    } catch (err) {
      if (err instanceof AppError) {
        throw err;
      }
      const be: BusinessError = err as BusinessError;
      const platformCode: number = typeof be.code === 'number' ? be.code : 0;
      if (platformCode === 2300025) {
        throw new AppError(ErrorCode.NETWORK_TIMEOUT,
          `直连 LLM 请求超时（readTimeout=${readTimeoutMs}ms）`);
      }
      throw new AppError(ErrorCode.NETWORK_REQUEST_FAILED, `直连 LLM 请求失败: ${(err as Error).message}`);
    } finally {
      reqHandle.destroy();
    }
  }
}
