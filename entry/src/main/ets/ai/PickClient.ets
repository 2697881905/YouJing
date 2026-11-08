/**
 * P1 AI 精选客户端：候选池 + 用户标签/天数/节奏 → 排序 + 每站一句理由。
 * 任何失败（未配置 / 网络 / 非 2xx / 结构不合法）一律返回 null，
 * 由页面保留现有确定性规则——AI 精选是增强，不是通路依赖。
 */

import { http } from '@kit.NetworkKit';
import { ApiConfig } from '../common/config/ApiConfig';
import { PickConfig } from '../common/config/PickConfig';
import { DeviceTokenStore } from '../data/DeviceTokenStore';
import { Logger } from '../common/logger/Logger';
import { PickCandidate, PickResult } from '../model/Pick';

const TAG: string = 'Ai.PickClient';
const ENDPOINT: string = '/v1/pick/spots';
const READ_TIMEOUT_MS: number = 20000;

export class PickClient {
  static async pickSpots(city: string, days: number, pace: string, interests: string,
    candidates: PickCandidate[]): Promise<PickResult | null> {
    // 优先 AGC 云函数（无自购服务器）；PICK_URL 为空时回退 BFF 联调通路
    const cloud: boolean = PickConfig.URL.length > 0;
    const url: string = cloud ? PickConfig.URL :
      (ApiConfig.BFF_BASE_URL.length > 0 ? `${ApiConfig.BFF_BASE_URL}${ENDPOINT}` : '');
    if (url.length === 0 || candidates.length === 0) {
      return null;
    }
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
}
