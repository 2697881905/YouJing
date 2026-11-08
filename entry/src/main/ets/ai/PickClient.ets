/**
 * P1 AI 精选客户端：候选池 + 用户标签/天数/节奏 → 排序 + 每站一句理由。
 * 通路优先级：AGC 云函数 → BFF → 端侧直连（DirectConfig）→ 确定性规则。
 * 任何失败（未配置 / 网络 / 非 2xx / 结构不合法）一律返回 null，
 * 由页面保留现有确定性规则——AI 精选是增强，不是通路依赖。
 */

import { http } from '@kit.NetworkKit';
import { ApiConfig } from '../common/config/ApiConfig';
import { PickConfig } from '../common/config/PickConfig';
import { DeviceTokenStore } from '../data/DeviceTokenStore';
import { Logger } from '../common/logger/Logger';
import { PickCandidate, PickRankItem, PickResult } from '../model/Pick';
import { DirectChat, DirectChatResult } from './DirectChat';
import { PickCandidate as PromptPickCandidate, PickPromptInput, PromptBuilder } from './PromptBuilder';

const TAG: string = 'Ai.PickClient';
const ENDPOINT: string = '/v1/pick/spots';
const READ_TIMEOUT_MS: number = 20000;
const MAX_REASON: number = 80;
const MAX_NOTE: number = 200;
const DIRECT_MAX_TOKENS: number = 2048;

export class PickClient {
  static async pickSpots(city: string, days: number, pace: string, interests: string,
    candidates: PickCandidate[]): Promise<PickResult | null> {
    if (candidates.length === 0) {
      return null;
    }
    // 优先 AGC 云函数（无自购服务器）；再 BFF 联调；两者都没有才走端侧直连
    const cloud: boolean = PickConfig.URL.length > 0;
    const bffUrl: string = !cloud && ApiConfig.BFF_BASE_URL.length > 0
      ? `${ApiConfig.BFF_BASE_URL}${ENDPOINT}` : '';
    if (!cloud && bffUrl.length === 0) {
      return await PickClient.pickDirect(city, days, pace, interests, candidates);
    }
    const url: string = cloud ? PickConfig.URL : bffUrl;
    const reqHandle = http.createHttp();
    try {
      const headers: Record<string, string> = {};
      headers['Content-Type'] = 'application/json';
      if (cloud) {
        if (PickConfig.TOKEN.length > 0) {
          headers['x-youjing-token'] = PickConfig.TOKEN;
        }
      } else {
        const token: string = DeviceTokenStore.getToken();
        if (token.length > 0) {
          headers['Authorization'] = `Bearer ${token}`;
        }
      }
      const payload: string = JSON.stringify({
        city: city, days: days, pace: pace, interests: interests, candidates: candidates
      });
      const resp: http.HttpResponse = await reqHandle.request(url, {
          method: http.RequestMethod.POST,
          header: headers,
          extraData: payload,
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: ApiConfig.REPLAN_CONNECT_TIMEOUT_MS,
          readTimeout: READ_TIMEOUT_MS
        });
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        Logger.warn(TAG, `pick HTTP ${resp.responseCode}，保留确定性规则`);
        return null;
      }
      const text: string = typeof resp.result === 'string' ? resp.result as string : '';
      if (text.length === 0) {
        return null;
      }
      const parsed: PickResult = JSON.parse(text) as PickResult;
      if (!Array.isArray(parsed.ranked)) {
        Logger.warn(TAG, 'pick 响应缺 ranked，保留确定性规则');
        return null;
      }
      Logger.info(TAG, `AI 精选 ${candidates.length} 个候选 → ${parsed.ranked.length} 条排序`);
      return parsed;
    } catch (err) {
      Logger.warn(TAG, `pick 失败，保留确定性规则: ${(err as Error).message}`);
      return null;
    } finally {
      reqHandle.destroy();
    }
  }

  /**
   * 端侧直连精选：无 AGC 云函数、无 BFF 时用 DirectConfig。
   * 提示词仍走 PromptBuilder SOT；返回前按云函数同口径守卫，防编造 id/超长理由。
   */
  private static async pickDirect(city: string, days: number, pace: string, interests: string,
    candidates: PickCandidate[]): Promise<PickResult | null> {
    if (!DirectChat.isConfigured()) {
      return null;
    }
    try {
      const promptCandidates: PromptPickCandidate[] = [];
      for (const c of candidates) {
        promptCandidates.push({
          id: c.id, name: c.name, tag: c.tag, brief: c.brief, district: c.district,
          popularity: c.popularity, suggestedDuration: c.suggestedDuration,
          requiresBooking: c.requiresBooking
        });
      }
      const input: PickPromptInput = {
        city: city, days: days, pace: pace, interests: interests, candidates: promptCandidates
      };
      const result: DirectChatResult = await DirectChat.complete([
        { role: 'system', content: PromptBuilder.pickSystemPrompt() },
        { role: 'user', content: PromptBuilder.pickUserPrompt(input) }
      ], DIRECT_MAX_TOKENS, READ_TIMEOUT_MS);
      const parsed: PickResult = JSON.parse(result.json) as PickResult;
      const guarded: PickResult | null = PickClient.guardPick(parsed, candidates);
      if (guarded === null) {
        Logger.warn(TAG, '直连精选结构不合法，保留确定性规则');
        return null;
      }
      Logger.info(TAG, `AI 精选（直连）${candidates.length} 个候选 → ${guarded.ranked.length} 条排序`);
      return guarded;
    } catch (err) {
      Logger.warn(TAG, `直连精选失败，保留确定性规则: ${(err as Error).message}`);
      return null;
    }
  }

  /** 与 cloud/pickSpots 同口径：ranked 覆盖全部候选、id 不重复、reason/note 不超长 */
  private static guardPick(parsed: PickResult, candidates: PickCandidate[]): PickResult | null {
    if (!Array.isArray(parsed.ranked) || parsed.ranked.length !== candidates.length) {
      return null;
    }
    const allowed: Set<string> = new Set<string>();
    for (const c of candidates) {
      allowed.add(c.id);
    }
    const seen: Set<string> = new Set<string>();
    const ranked: PickRankItem[] = [];
    for (const item of parsed.ranked) {
      if (item === undefined || item === null || typeof item.id !== 'string' ||
        !allowed.has(item.id) || seen.has(item.id)) {
        return null;
      }
      const reason: string = typeof item.reason === 'string' ? item.reason : '';
      if (reason.length > MAX_REASON) {
        return null;
      }
      seen.add(item.id);
      ranked.push({ id: item.id, reason: reason });
    }
    const note: string = typeof parsed.note === 'string' ? parsed.note : '';
    if (note.length > MAX_NOTE) {
      return null;
    }
    return { ranked: ranked, note: note };
  }
}
