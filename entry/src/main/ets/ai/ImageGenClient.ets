/**
 * 回顾海报 AI 底图客户端。
 *
 * 契约（Docs/行后情绪方案.md §海报 / Docs/design-v2/DESIGN.md §AI poster base）：
 * - 只向 BFF 发送「城市 + 风格枚举」两个生成参数，不发行程、打卡、账本或图片；
 * - 服务端返回 base64 图片，端侧解码成 PixelMap，**只在内存里作海报底图**，
 *   最终产物仍由本机离屏快照写 cacheDir → 系统分享，不上传、不落库、不进 UGC；
 * - 任何失败（未配置 / 无票据 / 非 2xx / 结构不合法 / 解码失败 / 超时）一律返回 null，
 *   页面保留模板海报。生图是增强，不是通路依赖；不重试，避免重复计费。
 *
 * 放在 ai/ 层是架构要求：页面不得直接发起模型请求（Docs/ARCHITECTURE.md §2）。
 */

import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { ApiConfig } from '../common/config/ApiConfig';
import { DeviceTokenStore } from '../data/DeviceTokenStore';
import { Logger } from '../common/logger/Logger';

const TAG: string = 'Ai.ImageGenClient';
/** base64 上限 6MB（约 4.5MB 二进制），超了直接判失败，避免把超大响应解进内存 */
const MAX_BASE64_LENGTH: number = 6 * 1024 * 1024;

export interface ImageGenRequest {
  city: string;
  style: string;
}

export interface ImageGenResponse {
  image: string;
  mime: string;
}

export class ImageGenClient {
  /** 生成一张海报底图；失败返回 null，调用方保留模板海报。 */
  static async generate(city: string, style: string): Promise<image.PixelMap | null> {
    if (ApiConfig.BFF_BASE_URL.length === 0) {
      Logger.warn(TAG, 'BFF 未配置，跳过生图，保留模板海报');
      return null;
    }
    const token: string = DeviceTokenStore.getToken();
    if (token.length === 0) {
      Logger.warn(TAG, '无设备票据，跳过生图，保留模板海报');
      return null;
    }

    const payload: ImageGenRequest = { city: city, style: style };
    const reqHandle = http.createHttp();
    try {
      const headers: Record<string, string> = {};
      headers['Content-Type'] = 'application/json';
      headers['Authorization'] = `Bearer ${token}`;
      const resp: http.HttpResponse = await reqHandle.request(
        `${ApiConfig.BFF_BASE_URL}${ApiConfig.IMAGE_GEN_ENDPOINT}`, {
          method: http.RequestMethod.POST,
          header: headers,
          extraData: JSON.stringify(payload),
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: ApiConfig.CONNECT_TIMEOUT_MS,
          readTimeout: ApiConfig.IMAGE_GEN_READ_TIMEOUT_MS
        });
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        Logger.warn(TAG, `生图 HTTP ${resp.responseCode}，保留模板海报`);
        return null;
      }
      const text: string = typeof resp.result === 'string' ? resp.result as string : '';
      if (text.length === 0) {
        Logger.warn(TAG, '生图响应为空，保留模板海报');
        return null;
      }
      return await ImageGenClient.decode(text);
    } catch (err) {
      Logger.warn(TAG, `生图失败，保留模板海报: ${(err as Error).message}`);
      return null;
    } finally {
      reqHandle.destroy();
    }
  }

  /** base64 → PixelMap。抽成独立方法便于单测同口径守卫，不放进 @Builder。 */
  private static async decode(text: string): Promise<image.PixelMap | null> {
    const parsed: ImageGenResponse = JSON.parse(text) as ImageGenResponse;
    const b64: string = typeof parsed.image === 'string' ? parsed.image : '';
    if (b64.length === 0 || b64.length > MAX_BASE64_LENGTH) {
      Logger.warn(TAG, '生图响应缺 image 或体积超限，保留模板海报');
      return null;
    }
    const helper: util.Base64Helper = new util.Base64Helper();
    const bytes: Uint8Array = helper.decodeSync(b64);
    if (bytes.length === 0) {
      Logger.warn(TAG, '生图响应解码为空，保留模板海报');
      return null;
    }
    const source: image.ImageSource = image.createImageSource(bytes.buffer as ArrayBuffer);
    const pixelMap: image.PixelMap = await source.createPixelMap();
    await source.release();
    Logger.info(TAG, `生图底图就绪 bytes=${bytes.length}`);
    return pixelMap;
  }
}
