/**
 * IAP 购买与校验（商业化方案 §4.4 / §2 定价结构）。
 *
 * 契约：
 * - purchasePass() 购买行程通行证（非消耗型商品），purchaseSubscription() 购买订阅（自动续期）；
 * - 购买成功后调 BFF /v1/iap/verify 做服务端校验，BFF 返回最新权益写入 EntitlementStore；
 * - BFF 未配置时跳过校验（开发期），仅日志记录 purchaseToken；
 * - restorePurchases() 查询已购商品并逐条向 BFF 校验，用于换设备/重装后恢复权益；
 * - finishPurchase() 在 BFF 校验成功后调用，确认发货完成。
 */

import { iap } from '@kit.IAPKit';
import { http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ApiConfig } from '../common/config/ApiConfig';
import { EntitlementStore, Entitlement } from './EntitlementStore';
import { DeviceTokenStore } from './DeviceTokenStore';
import { Logger } from '../common/logger/Logger';

const TAG: string = 'Data.IapStore';

export const PRODUCT_ID_PASS: string = 'youjing_pass';
export const PRODUCT_ID_SUB_MONTHLY: string = 'youjing_sub_monthly';
export const PRODUCT_ID_SUB_YEARLY: string = 'youjing_sub_yearly';

const IAP_VERIFY_ENDPOINT: string = '/v1/iap/verify';

export interface IapResult {
  success: boolean;
  message: string;
  passId: string | null;
}

interface VerifyResponse {
  verified: boolean;
  entitlement: Entitlement;
  passId: string | null;
}

interface PurchaseData {
  purchaseToken: string;
  purchaseOrderId: string;
  developerPayload?: string;
}

export class IapStore {
  private static purchasing: boolean = false;

  static async purchasePass(context: common.UIAbilityContext, localTripId: string): Promise<IapResult> {
    if (IapStore.purchasing) {
      return { success: false, message: '正在处理上一笔购买', passId: null };
    }
    IapStore.purchasing = true;
    try {
      const parameter: iap.PurchaseParameter = {
        productType: iap.ProductType.NONCONSUMABLE,
        productId: PRODUCT_ID_PASS,
        developerPayload: localTripId
      };
      const result: iap.CreatePurchaseResult =
        await iap.createPurchase(context, parameter);
      const purchaseData: PurchaseData = JSON.parse(result.purchaseData) as PurchaseData;
      const purchaseToken: string = purchaseData.purchaseToken;
      Logger.info(TAG, `通行证购买成功 token=${purchaseToken.length}字符`);

      const verifyResult: IapResult = await IapStore.verifyWithBff(
        context, purchaseToken, 'pass', localTripId);
      await IapStore.finishPurchase(context, purchaseData, iap.ProductType.NONCONSUMABLE);
      return verifyResult;
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      if (be.code === 1001860000) {
        return { success: false, message: '用户取消购买', passId: null };
      }
      Logger.warn(TAG, `通行证购买失败: code=${be.code} msg=${be.message}`);
      return { success: false, message: `购买失败: ${be.message}`, passId: null };
    } finally {
      IapStore.purchasing = false;
    }
  }

  static async purchaseSubscription(context: common.UIAbilityContext,
    productId: string): Promise<IapResult> {
    if (IapStore.purchasing) {
      return { success: false, message: '正在处理上一笔购买', passId: null };
    }
    IapStore.purchasing = true;
    try {
      const parameter: iap.PurchaseParameter = {
        productType: iap.ProductType.AUTORENEWABLE,
        productId: productId,
        developerPayload: ''
      };
      const result: iap.CreatePurchaseResult =
        await iap.createPurchase(context, parameter);
      const purchaseData: PurchaseData = JSON.parse(result.purchaseData) as PurchaseData;
      const purchaseToken: string = purchaseData.purchaseToken;
      Logger.info(TAG, `订阅购买成功 productId=${productId} token=${purchaseToken.length}字符`);

      const verifyResult: IapResult = await IapStore.verifyWithBff(
        context, purchaseToken, 'subscription', null);
      await IapStore.finishPurchase(context, purchaseData, iap.ProductType.AUTORENEWABLE);
      return verifyResult;
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      if (be.code === 1001860000) {
        return { success: false, message: '用户取消购买', passId: null };
      }
      Logger.warn(TAG, `订阅购买失败: code=${be.code} msg=${be.message}`);
      return { success: false, message: `购买失败: ${be.message}`, passId: null };
    } finally {
      IapStore.purchasing = false;
    }
  }

  static async restorePurchases(context: common.UIAbilityContext): Promise<IapResult> {
    let restoredAny: boolean = false;
    let lastPassId: string | null = null;

    try {
      const passParam: iap.QueryPurchasesParameter = {
        productType: iap.ProductType.NONCONSUMABLE,
        queryType: iap.PurchaseQueryType.CURRENT_ENTITLEMENT
      };
      const passResult: iap.QueryPurchaseResult =
        await iap.queryPurchases(context, passParam);
      const passListRaw: string[] = passResult.purchaseDataList;
      if (passListRaw !== undefined && passListRaw.length > 0) {
        for (const dataStr of passListRaw) {
          const data: PurchaseData = JSON.parse(dataStr) as PurchaseData;
          const localTripId: string = data.developerPayload !== undefined ? data.developerPayload : '';
          const r: IapResult = await IapStore.verifyWithBff(
            context, data.purchaseToken, 'pass', localTripId);
          if (r.success) {
            restoredAny = true;
            if (r.passId !== null) {
              lastPassId = r.passId;
            }
            await IapStore.finishPurchase(context, data, iap.ProductType.NONCONSUMABLE);
          }
        }
      }
    } catch (err) {
      Logger.warn(TAG, `恢复通行证查询失败: ${(err as Error).message}`);
    }

    try {
      const subParam: iap.QueryPurchasesParameter = {
        productType: iap.ProductType.AUTORENEWABLE,
        queryType: iap.PurchaseQueryType.CURRENT_ENTITLEMENT
      };
      const subResult: iap.QueryPurchaseResult =
        await iap.queryPurchases(context, subParam);
      const subListRaw: string[] = subResult.purchaseDataList;
      if (subListRaw !== undefined && subListRaw.length > 0) {
        for (const dataStr of subListRaw) {
          const data: PurchaseData = JSON.parse(dataStr) as PurchaseData;
          const r: IapResult = await IapStore.verifyWithBff(
            context, data.purchaseToken, 'subscription', null);
          if (r.success) {
            restoredAny = true;
            await IapStore.finishPurchase(context, data, iap.ProductType.AUTORENEWABLE);
          }
        }
      }
    } catch (err) {
      Logger.warn(TAG, `恢复订阅查询失败: ${(err as Error).message}`);
    }

    if (restoredAny) {
      return { success: true, message: '已恢复购买', passId: lastPassId };
    }
    return { success: false, message: '没有可恢复的购买', passId: null };
  }

  private static async verifyWithBff(context: common.UIAbilityContext,
    purchaseToken: string, productType: string,
    localTripId: string | null): Promise<IapResult> {
    if (ApiConfig.BFF_BASE_URL.length === 0) {
      Logger.info(TAG, 'BFF 未配置，跳过 IAP 校验（开发期）');
      return { success: true, message: '购买成功（未校验）', passId: localTripId };
    }

    try {
      const body: Record<string, string> = {};
      body['purchaseToken'] = purchaseToken;
      body['productType'] = productType;
      if (localTripId !== null && localTripId.length > 0) {
        body['localTripId'] = localTripId;
      }

      const reqHandle = http.createHttp();
      try {
        const headers: Record<string, string> = {};
        headers['Content-Type'] = 'application/json';
        const token: string = DeviceTokenStore.getToken();
        if (token.length > 0) {
          headers['Authorization'] = `Bearer ${token}`;
        }
        const resp: http.HttpResponse = await reqHandle.request(
          `${ApiConfig.BFF_BASE_URL}${IAP_VERIFY_ENDPOINT}`, {
          method: http.RequestMethod.POST,
          header: headers,
          extraData: JSON.stringify(body),
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: ApiConfig.CONNECT_TIMEOUT_MS,
          readTimeout: ApiConfig.READ_TIMEOUT_MS
        });

        if (resp.responseCode < 200 || resp.responseCode >= 300) {
          Logger.warn(TAG, `IAP 校验失败 HTTP ${resp.responseCode}: ${String(resp.result).slice(0, 160)}`);
          return { success: false, message: '校验失败，请稍后重试', passId: null };
        }

        const data: VerifyResponse = JSON.parse(String(resp.result)) as VerifyResponse;
        if (!data.verified) {
          Logger.warn(TAG, 'IAP 校验未通过');
          return { success: false, message: '校验未通过，请联系客服', passId: null };
        }

        await EntitlementStore.update(data.entitlement);
        Logger.info(TAG, `IAP 校验成功 passId=${data.passId}`);
        return { success: true, message: '购买成功', passId: data.passId };
      } finally {
        reqHandle.destroy();
      }
    } catch (err) {
      Logger.warn(TAG, `IAP 校验异常: ${(err as Error).message}`);
      return { success: false, message: '校验异常，请稍后重试', passId: null };
    }
  }

  private static async finishPurchase(context: common.UIAbilityContext,
    purchaseData: PurchaseData, productType: iap.ProductType): Promise<void> {
    try {
      const finishParam: iap.FinishPurchaseParameter = {
        productType: productType,
        purchaseToken: purchaseData.purchaseToken,
        purchaseOrderId: purchaseData.purchaseOrderId
      };
      await iap.finishPurchase(context, finishParam);
      Logger.info(TAG, '发货确认完成');
    } catch (err) {
      Logger.warn(TAG, `发货确认失败: ${(err as Error).message}`);
    }
  }
}