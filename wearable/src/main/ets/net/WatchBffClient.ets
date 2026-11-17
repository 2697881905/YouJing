/**
 * 手表 → BFF 的最小 HTTPS 客户端（切片0 探针用）。
 * 只做 JSON 往返；不重试、不缓存、不伪造成功。
 */

import { http } from '@kit.NetworkKit';
import { WATCH_BFF_BASE_URL, WATCH_CONNECT_TIMEOUT_MS, WATCH_READ_TIMEOUT_MS } from './WatchNetConfig';

export interface WatchBffResponse {
  status: number;
  body: string;
}

export class WatchBffClient {
  static async post(path: string, token: string, payload: string): Promise<WatchBffResponse> {
    return WatchBffClient.request(http.RequestMethod.POST, path, token, payload);
  }

  static async get(path: string, token: string): Promise<WatchBffResponse> {
    return WatchBffClient.request(http.RequestMethod.GET, path, token, '');
  }

  private static async request(method: http.RequestMethod, path: string, token: string,
    payload: string): Promise<WatchBffResponse> {
    const req: http.HttpRequest = http.createHttp();
    try {
      const header: Record<string, string> = { 'Content-Type': 'application/json' };
      if (token.length > 0) {
        header['Authorization'] = `Bearer ${token}`;
      }
      const options: http.HttpRequestOptions = {
        method: method,
        header: header,
        connectTimeout: WATCH_CONNECT_TIMEOUT_MS,
        readTimeout: WATCH_READ_TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING
      };
      if (payload.length > 0) {
        options.extraData = payload;
      }
      const resp: http.HttpResponse = await req.request(`${WATCH_BFF_BASE_URL}${path}`, options);
      const status: number = resp.responseCode as number;
      const body: string = typeof resp.result === 'string' ? resp.result as string : '';
      const result: WatchBffResponse = { status: status, body: body };
      return result;
    } finally {
      req.destroy();
    }
  }
}
