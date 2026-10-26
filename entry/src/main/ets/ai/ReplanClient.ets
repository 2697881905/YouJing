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
import { ReplanDecision, ReplanRequest } from '../model/Replan';
import { TripDay } from '../model/Trip';
import { SkipPlanner } from '../data/SkipPlanner';
import { ReplanParser } from './ReplanParser';

const TAG: string = 'Ai.ReplanClient';

export class ReplanClient {
  static async requestDecision(day: TripDay, skippedId: string,
    nowMin: number): Promise<ReplanDecision | null> {
    if (ApiConfig.REPLAN_URL.length === 0) {
      Logger.warn(TAG, 'Replan 云函数未配置（ApiConfig.REPLAN_URL 为空），走本地兜底');
      return null;
    }
    const request: ReplanRequest = SkipPlanner.buildRequest(day, skippedId, nowMin);
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
}
