/**
 * 设备激活流程（商业化方案 §4.2 / §5 错误码 6001）。
 *
 * 契约：
 * - activate() 调 BFF POST /v1/device/activate，传 deviceId（端上 UUID）+ unionId（如已登录）；
 * - BFF 返回 deviceToken + entitlement，token 存入 DeviceTokenStore，entitlement 存入 EntitlementStore；
 * - BFF_BASE_URL 未配置时跳过激活（开发期 Mock 模式不需要票据）；
 * - 激活失败不阻断主流程：用户仍可进入主界面，首次请求 BFF 时会拿到 401 再触发重新激活。
 */

import { http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { ApiConfig } from '../common/config/ApiConfig';
import { DeviceTokenStore } from './DeviceTokenStore';
import { EntitlementStore, Entitlement } from './EntitlementStore';
import { AccountStore } from './AccountStore';
import { Logger } from '../common/logger/Logger';

const TAG: string = 'Data.DeviceActivator';
const ACTIVATE_ENDPOINT: string = '/v1/device/activate';

interface ActivateResponse {
  deviceToken: string;
  entitlement: Entitlement;
}

export class DeviceActivator {
  private static activating: boolean = false;

  static async activate(context: common.Context): Promise<boolean> {
    if (DeviceTokenStore.isActivated()) {
      Logger.info(TAG, '设备已激活，跳过');
      return true;
    }
    if (DeviceActivator.activating) {
      Logger.info(TAG, '激活正在进行中，跳过重复调用');
      return false;
    }
    if (ApiConfig.BFF_BASE_URL.length === 0) {
      Logger.info(TAG, 'BFF 未配置，跳过设备激活（开发期 Mock 模式）');
      return false;
    }

    DeviceActivator.activating = true;
    try {
      const deviceId: string = await DeviceTokenStore.ensureDeviceId();
      const unionId: string = AccountStore.isGuest() ? '' : AccountStore.uid();

      const body: Record<string, string> = {};
      body['deviceId'] = deviceId;
      if (unionId.length > 0) {
        body['unionId'] = unionId;
      }

      const reqHandle = http.createHttp();
      try {
        const resp: http.HttpResponse = await reqHandle.request(
          `${ApiConfig.BFF_BASE_URL}${ACTIVATE_ENDPOINT}`, {
          method: http.RequestMethod.POST,
          header: { 'Content-Type': 'application/json' },
          extraData: JSON.stringify(body),
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: ApiConfig.CONNECT_TIMEOUT_MS,
          readTimeout: ApiConfig.READ_TIMEOUT_MS
        });

        if (resp.responseCode < 200 || resp.responseCode >= 300) {
          Logger.warn(TAG, `设备激活失败 HTTP ${resp.responseCode}: ${String(resp.result).slice(0, 160)}`);
          return false;
        }

        const data: ActivateResponse = JSON.parse(String(resp.result)) as ActivateResponse;
        if (data.deviceToken.length === 0) {
          Logger.warn(TAG, '激活响应缺 deviceToken');
          return false;
        }

        await DeviceTokenStore.saveToken(data.deviceToken);
        if (data.entitlement !== undefined && data.entitlement !== null) {
          await EntitlementStore.update(data.entitlement);
        }

        Logger.info(TAG, `设备激活成功 token=${DeviceTokenStore.getToken().length}字符`);
        return true;
      } finally {
        reqHandle.destroy();
      }
    } catch (err) {
      Logger.warn(TAG, `设备激活异常: ${(err as Error).message}`);
      return false;
    } finally {
      DeviceActivator.activating = false;
    }
  }

  /**
   * 票据失效后重新激活（BFF 回 401/6001 时调用）。
   * 先清旧 token 再走 activate()，确保 BFF 不拿旧票据做判断。
   */
  static async reactivate(context: common.Context): Promise<boolean> {
    Logger.info(TAG, '票据失效，重新激活');
    await DeviceTokenStore.clear();
    return DeviceActivator.activate(context);
  }
}