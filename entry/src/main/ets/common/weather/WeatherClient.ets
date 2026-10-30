/**
 * Open-Meteo 天气客户端（切片 3 T1）。
 * 与 ReplanClient 同口径：任何失败都返回 null，由调用方静默降级（不出天气行）。
 * 只发四舍五入到 0.1° 的坐标：天气不需要精确位置，也不该把实时定位发给第三方。
 */

import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ApiConfig } from '../config/ApiConfig';
import { Logger } from '../logger/Logger';

const TAG: string = 'Weather.Client';
const CONNECT_TIMEOUT_MS: number = 3000;
const READ_TIMEOUT_MS: number = 4000;

export class WeatherClient {
  /** 返回原始 JSON 文本；失败返回 null */
  static async fetch(latitude: number, longitude: number): Promise<string | null> {
    if (ApiConfig.WEATHER_URL.length === 0) {
      Logger.warn(TAG, 'WEATHER_URL 未配置，跳过天气请求');
      return null;
    }
    const url: string = `${ApiConfig.WEATHER_URL}?latitude=${latitude.toFixed(1)}`
      + `&longitude=${longitude.toFixed(1)}`
      + '&hourly=precipitation_probability,weather_code,temperature_2m'
      + '&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max'
      + '&timezone=auto&forecast_days=2';
    const reqHandle = http.createHttp();
    try {
      const resp: http.HttpResponse = await reqHandle.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: CONNECT_TIMEOUT_MS,
        readTimeout: READ_TIMEOUT_MS
      });
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        Logger.warn(TAG, `天气 HTTP ${resp.responseCode}`);
        return null;
      }
      const text: string = typeof resp.result === 'string' ? resp.result as string : '';
      if (text.length === 0) {
        Logger.warn(TAG, '天气响应为空');
        return null;
      }
      return text;
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      const code: number = typeof be.code === 'number' ? be.code : 0;
      Logger.warn(TAG, `天气请求失败(${code}): ${(err as Error).message}`);
      return null;
    } finally {
      reqHandle.destroy();
    }
  }
}
