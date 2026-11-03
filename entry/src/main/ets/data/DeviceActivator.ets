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
const ENTITLEMENT_ENDPOINT: string = '/v1/entitlement';

interface ActivateResponse {
  deviceToken: string;
  entitlement: Entitlement;
}

export class DeviceActivator {
  private static activating: boolean = false;

  static async activate(context: common.Context): Promise<boolean> {
    if (DeviceTokenStore.isActivated()) {
      // 票据还在，也要把**权益**刷一遍：缓存 TTL 只有 5 分钟，而生成门禁看的是缓存有效期。
      // 原来这里直接 return true，「已激活」就再也不刷新 —— 冷启一次、过 5 分钟再点生成，
      // 用户会被挡到付费页且永远补不回来（2026-11-03 端到端联调实测就是这个）。
      return DeviceActivator.refreshEntitlement();
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
      // D10：身份只交**华为签发的 idToken**，不再把 unionId 放在请求体里自报。
      // 已登录却取不到 idToken 时**不降级为游客**（那会把数据切到另一个分区）——
      // 直接放弃本次激活，下次冷启/重试再试。
      let idToken: string = '';
      if (!AccountStore.isGuest()) {
        idToken = await AccountStore.refreshIdToken(context as common.UIAbilityContext);
        if (idToken.length === 0) {
          Logger.warn(TAG, '已登录但取不到 idToken，跳过激活（不降级为游客）');
          return false;
        }
      }

      const body: Record<string, string> = {};
      body['deviceId'] = deviceId;
      if (idToken.length > 0) {
        body['idToken'] = idToken;
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
   * 用现有票据把权益刷一遍（不重新签发票据）。
   * 401 说明票据真的失效：清掉票据，让下一次 activate() 走完整激活。
   */
  private static async refreshEntitlement(): Promise<boolean> {
    try {
      const reqHandle = http.createHttp();
      try {
        const resp: http.HttpResponse = await reqHandle.request(
          `${ApiConfig.BFF_BASE_URL}${ENTITLEMENT_ENDPOINT}`, {
          method: http.RequestMethod.GET,
          header: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${DeviceTokenStore.getToken()}`
          },
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: ApiConfig.CONNECT_TIMEOUT_MS,
          readTimeout: ApiConfig.READ_TIMEOUT_MS
        });
        if (resp.responseCode === 401) {
          Logger.warn(TAG, '权益刷新遇 401，清票据等下次重新激活');
          await DeviceTokenStore.clear();
          return false;
        }
        if (resp.responseCode < 200 || resp.responseCode >= 300) {
          Logger.warn(TAG, `权益刷新失败 HTTP ${resp.responseCode}`);
          return false;
        }
        const ent: Entitlement = JSON.parse(String(resp.result)) as Entitlement;
        await EntitlementStore.update(ent);
        Logger.info(TAG, `权益已刷新 gift=${ent.giftRemaining} used=${ent.usedToday}/${ent.dailyCap}`);
        return true;
      } finally {
        reqHandle.destroy();
      }
    } catch (err) {
      Logger.warn(TAG, `权益刷新异常: ${(err as Error).message}`);
      return false;
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