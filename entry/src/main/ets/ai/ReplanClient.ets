/**
 * 重排云函数客户端（方案 §3.4 / §3.5）。
 * 任何失败（未配置 / 网络 / 非 2xx / 守卫拒绝 / 超时）一律返回 null，
 * 由 OnTripPage 交给 SkipPlanner 走本地兜底；绝不让网络问题阻塞跳过。
 */

import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ApiConfig } from '../common/config/ApiConfig';
import { Logger } from '../common/logger/Logger';
import { AppError } from '../common/error/AppError';
import { ReplanAction, ReplanDecision, ReplanRequest, REPLAN_SCHEMA_VERSION } from '../model/Replan';
import { Activity, TripDay } from '../model/Trip';
import { SkipPlanner } from '../data/SkipPlanner';
import { ReplanParser } from './ReplanParser';
import { DirectChat, DirectChatMessage, DirectChatResult } from './DirectChat';
import { ReplanPromptBuilder } from './ReplanPromptBuilder';

const TAG: string = 'Ai.ReplanClient';
/** 端侧直连重排：决策体小，2048 tokens 足够；30s 读超时，超时即回本地兜底 */
const REPLAN_DIRECT_MAX_TOKENS: number = 2048;
const REPLAN_DIRECT_READ_TIMEOUT_MS: number = 30000;

export class ReplanClient {
  static async requestDecision(day: TripDay, skippedId: string,
    nowMin: number): Promise<ReplanDecision | null> {
    return await ReplanClient.send(SkipPlanner.buildRequest(day, skippedId, nowMin));
  }

  /** 加一站：把新站带临时时刻发给云函数，由它决定 keep 顺序与停留时长。 */
  static async requestAddDecision(day: TripDay, newStop: Activity,
    nowMin: number): Promise<ReplanDecision | null> {
    return await ReplanClient.send(SkipPlanner.buildAddRequest(day, newStop, nowMin));
  }

  /** P3 对话式：把自然语言意愿与候选池发给云函数，由它映射四种动作。 */
  static async requestIntentDecision(day: TripDay, intentText: string, candidates: Activity[],
    nowMin: number): Promise<ReplanDecision | null> {
    return await ReplanClient.send(SkipPlanner.buildIntentRequest(day, intentText, candidates, nowMin));
  }

  private static async send(request: ReplanRequest): Promise<ReplanDecision | null> {
    if (ApiConfig.REPLAN_URL.length === 0) {
      // 云函数未部署：端侧直连已配就走真 LLM，否则本地兜底
      if (DirectChat.isConfigured()) {
        return await ReplanClient.sendDirect(request);
      }
      Logger.warn(TAG, 'Replan 云函数未配置且端侧直连未配置，走本地兜底');
      return null;
    }
    const reqHandle = http.createHttp();
    try {
      const headers: Record<string, string> = {};
      headers['Content-Type'] = 'application/json';
      let tokenHeader: string = '';
      if (ApiConfig.REPLAN_TOKEN.length > 0) {
        headers['x-youjing-token'] = ApiConfig.REPLAN_TOKEN;
        tokenHeader = '已带';
      } else {
        Logger.warn(TAG, 'REPLAN_TOKEN 未配置，云函数将按 401 拒绝并走本地兜底');
        tokenHeader = '未带';
      }
      const resp: http.HttpResponse = await reqHandle.request(ApiConfig.REPLAN_URL, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify(request),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: ApiConfig.REPLAN_CONNECT_TIMEOUT_MS,
        readTimeout: ApiConfig.REPLAN_READ_TIMEOUT_MS
      });
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        Logger.warn(TAG, `replan HTTP ${resp.responseCode}（token ${tokenHeader}），走本地兜底`);
        return null;
      }
      const text: string = typeof resp.result === 'string' ? resp.result as string : '';
      if (text.length === 0) {
        Logger.warn(TAG, 'replan 响应为空，走本地兜底');
        return null;
      }
      const decision: ReplanDecision = ReplanParser.parseDecision(text);
      Logger.info(TAG, `replan 决策 keep=${decision.keep.length} blocks=${decision.freeBlocks.length}`);
      return decision;
    } catch (err) {
      if (err instanceof AppError) {
        Logger.warn(TAG, `replan 守卫拒绝: ${err.message}，走本地兜底`);
        return null;
      }
      const be: BusinessError = err as BusinessError;
      const platformCode: number = typeof be.code === 'number' ? be.code : 0;
      if (platformCode === 2300025) {
        Logger.warn(TAG, `replan 超时（readTimeout=${ApiConfig.REPLAN_READ_TIMEOUT_MS}ms），走本地兜底`);
      } else {
        Logger.warn(TAG, `replan 请求失败: ${(err as Error).message}，走本地兜底`);
      }
      return null;
    } finally {
      reqHandle.destroy();
    }
  }

  /** 端侧直连：提示词搬自云函数，输出仍交 ReplanParser 守卫；任何失败回 null 走本地兜底 */
  private static async sendDirect(request: ReplanRequest): Promise<ReplanDecision | null> {
    try {
      if (!ReplanPromptBuilder.needsLlm(request)) {
        const empty: ReplanDecision = { schemaVersion: REPLAN_SCHEMA_VERSION, keep: [], freeBlocks: [], note: '' };
        return empty;
      }
      const messages: DirectChatMessage[] = ReplanPromptBuilder.messages(request);
      const result: DirectChatResult =
        await DirectChat.complete(messages, REPLAN_DIRECT_MAX_TOKENS, REPLAN_DIRECT_READ_TIMEOUT_MS);
      // 意图决策的提示词不要求 schemaVersion/keep/freeBlocks（云函数由守卫补 keep:[]/freeBlocks:[]）；
      // 端侧直连同样补齐再交 ReplanParser，跳过/加站决策自带这些字段则原样通过
      const raw: Record<string, Object> = JSON.parse(result.json) as Record<string, Object>;
      const emptyArr: Object[] = [];
      if (raw['schemaVersion'] === undefined) {
        raw['schemaVersion'] = REPLAN_SCHEMA_VERSION;
      }
      if (raw['keep'] === undefined) {
        raw['keep'] = emptyArr;
      }
      if (raw['freeBlocks'] === undefined) {
        raw['freeBlocks'] = emptyArr;
      }
      const decision: ReplanDecision = ReplanParser.parseDecision(JSON.stringify(raw));
      // 意图决策完整性守卫（对齐云函数 guardIntentDecision）：skip 既无 targetId 又非收尾今日 → 不完整，回本地兜底
      if (decision.action === ReplanAction.SKIP &&
        (decision.targetId === undefined || decision.targetId.length === 0) &&
        decision.skipRemaining !== true) {
        Logger.warn(TAG, 'replan 直连意图决策不完整（skip 缺 targetId/skipRemaining），走本地兜底');
        return null;
      }
      Logger.info(TAG, `replan 直连决策 action=${decision.action ?? 'skip'} keep=${decision.keep.length} ` +
        `blocks=${decision.freeBlocks.length}`);
      return decision;
    } catch (err) {
      Logger.warn(TAG, `replan 直连失败: ${(err as Error).message}，走本地兜底`);
      return null;
    }
  }
}
