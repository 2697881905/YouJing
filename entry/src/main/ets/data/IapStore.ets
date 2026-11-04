/**
 * IAP 购买与校验（商业化方案 §4.4 / §2 定价结构）—— 对表华为官方（2026-09）。
 *
 * 契约（官方权益发放指南）：
 * - 购买数据本身不含签名；**华为签发的是 JWS**：queryPurchases 返回的 PurchaseData
 *   { type, jwsPurchaseOrder?, jwsSubscriptionStatus? }，官方建议「客户端将 purchaseData
 *   发送至应用服务器，在应用服务器执行解码验签」；
 * - 所以购买/恢复后先把 createPurchase 的 purchaseToken 当钥匙，去 queryPurchases
 *   （UNFINISHED）找到对应 JWS，再把 **JWS 原文**交给 BFF /v1/iap/verify；
 * - BFF 用 Huawei CBG Root CA G2 证书链本地验签后返回最新权益，写入 EntitlementStore；
 * - BFF 校验成功后才 finishPurchase 确认发货（官方：确保发货成功后再确认）；
 * - 客户端自报的 purchaseToken 不再作为凭据——92 位裸 token 换不到任何权益。
 */

import { iap } from '@kit.IAPKit';
import { util } from '@kit.ArkTS';
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

/** createPurchase 返回的 purchaseData：InAppPurchaseData 形态（含 92 位购买令牌，无签名） */
interface OwnedPurchaseData {
  purchaseToken: string;
  purchaseOrderId: string;
}

/** queryPurchases 返回的 PurchaseData：官方 JWS 容器形态 */
interface PurchaseData {
  type?: number;
  jwsPurchaseOrder?: string;
  jwsSubscriptionStatus?: string;
}

interface VerifyResponse {
  verified: boolean;
  entitlement: Entitlement;
  passId: string | null;
}

/** jwsPurchaseOrder 解码后的负载（只取发货/校验所需字段，官方 PurchaseOrderPayload 子集） */
interface PurchaseOrderPayload {
  purchaseToken: string;
  purchaseOrderId?: string;
  productId?: string;
  developerPayload?: string;
}

/** jwsSubscriptionStatus 解码后的负载（官方 SubGroupStatusPayload 子集） */
interface SubGroupStatusPayload {
  lastSubscriptionStatus?: SubscriptionStatus;
}

interface SubscriptionStatus {
  purchaseToken?: string;
  status?: string;
  lastPurchaseOrder?: PurchaseOrderPayload;
}

/** base64url → std base64（JWS 各段是 base64url 编码） */
function b64urlToStd(seg: string): string {
  let std = seg.replace(/-/g, '+').replace(/_/g, '/');
  while (std.length % 4 !== 0) {
    std += '=';
  }
  return std;
}

/** 解 JWS 的 payload 段（不验签——验签是 BFF 的职责，端侧只为取字段） */
function decodeJwsPayload<T>(jws: string): T | null {
  try {
    const segs: string[] = jws.split('.');
    if (segs.length !== 3 || segs[1].length === 0) {
      return null;
    }
    const bytes: Uint8Array = new util.Base64Helper().decodeSync(b64urlToStd(segs[1]));
    const text: string = util.TextDecoder.create('utf-8').decodeToString(bytes);
    return JSON.parse(text) as T;
  } catch (err) {
    Logger.warn(TAG, `JWS payload 解码失败: ${(err as Error).message}`);
    return null;
  }
}

export class IapStore {
  private static purchasing: boolean = false;

  /**
   * 从 queryPurchases 里找指定购买令牌对应的 JWS。
   * 购买路径用 UNFINISHED（已购未发货），恢复路径由调用方直接拿到列表、不走本方法。
   */
  private static async findOrderJws(context: common.UIAbilityContext,
    productType: iap.ProductType, purchaseToken: string): Promise<string | null> {
    const param: iap.QueryPurchasesParameter = {
      productType: productType,
      queryType: iap.PurchaseQueryType.UNFINISHED
    };
    const result: iap.QueryPurchaseResult = await iap.queryPurchases(context, param);
    const list: string[] = result.purchaseDataList;
    if (list === undefined || list.length === 0) {
      Logger.warn(TAG, 'queryPurchases(UNFINISHED) 为空，拿不到 JWS');
      return null;
    }
    for (const dataStr of list) {
      const container: PurchaseData = JSON.parse(dataStr) as PurchaseData;
      const jws: string | undefined = container.jwsPurchaseOrder;
      if (jws === undefined || jws.length === 0) {
        continue;
      }
      const payload = decodeJwsPayload<PurchaseOrderPayload>(jws);
      if (payload !== null && payload.purchaseToken === purchaseToken) {
        return jws;
      }
    }
    Logger.warn(TAG, 'UNFINISHED 列表里没有匹配的购买令牌');
    return null;
  }

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
      const owned: OwnedPurchaseData = JSON.parse(result.purchaseData) as OwnedPurchaseData;
      Logger.info(TAG, `通行证购买成功 token=${owned.purchaseToken.length}字符`);

      const jws = await IapStore.findOrderJws(context, iap.ProductType.NONCONSUMABLE, owned.purchaseToken);
      if (jws === null) {
        return {
          success: false,
          message: '校验数据未就绪，请稍后在「恢复购买」中重试',
          passId: null
        };
      }
      const verifyResult: IapResult = await IapStore.verifyWithBff(jws, null, 'pass', localTripId);
      await IapStore.finishPurchase(context, iap.ProductType.NONCONSUMABLE,
        owned.purchaseToken, owned.purchaseOrderId);
      return verifyResult;
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      if (be.code === 1001860000) {
        return { success: false, message: '用户取消购买', passId: null };
      }
      if (be.code === 1001860002) {
        // 授权被拒时的官方诊断位：直接问沙盒环境开关（官方 FAQ 指定的自查接口）
        try {
          const sandbox: boolean = await iap.isSandboxActivated(context);
          Logger.warn(TAG, `沙盒诊断: isSandboxActivated=${sandbox}（false=沙盒未生效/账号未授权/签名指纹不符）`);
        } catch (diagErr) {
          const de: BusinessError = diagErr as BusinessError;
          Logger.warn(TAG, `沙盒诊断接口本身失败: code=${de.code} msg=${de.message}`);
        }
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
      const owned: OwnedPurchaseData = JSON.parse(result.purchaseData) as OwnedPurchaseData;
      Logger.info(TAG, `订阅购买成功 productId=${productId} token=${owned.purchaseToken.length}字符`);

      // 订阅优先上交订阅状态 JWS（官方订阅发货以 SubGroupStatusPayload 为准），
      // 拿不到状态 JWS 时退回订单 JWS（BFF 两种都认）。
      let jwsSub: string | null = null;
      try {
        const param: iap.QueryPurchasesParameter = {
          productType: iap.ProductType.AUTORENEWABLE,
          queryType: iap.PurchaseQueryType.UNFINISHED
        };
        const q: iap.QueryPurchaseResult = await iap.queryPurchases(context, param);
        const list: string[] = q.purchaseDataList;
        for (const dataStr of (list ?? [])) {
          const container: PurchaseData = JSON.parse(dataStr) as PurchaseData;
          if (container.jwsSubscriptionStatus !== undefined && container.jwsSubscriptionStatus.length > 0) {
            const payload = decodeJwsPayload<SubGroupStatusPayload>(container.jwsSubscriptionStatus);
            const token: string | undefined = payload?.lastSubscriptionStatus?.purchaseToken;
            if (token === owned.purchaseToken) {
              jwsSub = container.jwsSubscriptionStatus;
              break;
            }
          }
        }
      } catch (err) {
        Logger.warn(TAG, `订阅状态 JWS 查询失败，退回订单 JWS: ${(err as Error).message}`);
      }
      const jwsOrder: string | null = await IapStore.findOrderJws(
        context, iap.ProductType.AUTORENEWABLE, owned.purchaseToken);
      if (jwsSub === null && jwsOrder === null) {
        return {
          success: false,
          message: '校验数据未就绪，请稍后在「恢复购买」中重试',
          passId: null
        };
      }
      const verifyResult: IapResult = await IapStore.verifyWithBff(jwsOrder, jwsSub, 'subscription', null);
      await IapStore.finishPurchase(context, iap.ProductType.AUTORENEWABLE,
        owned.purchaseToken, owned.purchaseOrderId);
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
          const container: PurchaseData = JSON.parse(dataStr) as PurchaseData;
          const jws: string | undefined = container.jwsPurchaseOrder;
          if (jws === undefined || jws.length === 0) {
            continue;
          }
          // localTripId 在下单时存进了 developerPayload，从 JWS 负载里取回
          const payload = decodeJwsPayload<PurchaseOrderPayload>(jws);
          const localTripId: string = payload?.developerPayload ?? '';
          const r: IapResult = await IapStore.verifyWithBff(
            jws, null, 'pass', localTripId.length > 0 ? localTripId : null);
          if (r.success) {
            restoredAny = true;
            if (r.passId !== null) {
              lastPassId = r.passId;
            }
            if (payload !== null) {
              await IapStore.finishPurchase(context, iap.ProductType.NONCONSUMABLE,
                payload.purchaseToken, payload.purchaseOrderId ?? '');
            }
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
          const container: PurchaseData = JSON.parse(dataStr) as PurchaseData;
          const jwsSub: string | undefined = container.jwsSubscriptionStatus;
          const jwsOrder: string | undefined = container.jwsPurchaseOrder;
          if ((jwsSub === undefined || jwsSub.length === 0) &&
            (jwsOrder === undefined || jwsOrder.length === 0)) {
            continue;
          }
          const r: IapResult = await IapStore.verifyWithBff(
            jwsOrder ?? null, jwsSub ?? null, 'subscription', null);
          if (r.success) {
            restoredAny = true;
            // 发货确认要 purchaseToken/purchaseOrderId：订阅取 lastPurchaseOrder，订单取自身
            const fromSub = jwsSub !== undefined
              ? decodeJwsPayload<SubGroupStatusPayload>(jwsSub)?.lastSubscriptionStatus : null;
            const token: string | undefined = fromSub?.purchaseToken
              ?? decodeJwsPayload<PurchaseOrderPayload>(jwsOrder ?? '')?.purchaseToken;
            const orderId: string | undefined = fromSub?.lastPurchaseOrder?.purchaseOrderId
              ?? decodeJwsPayload<PurchaseOrderPayload>(jwsOrder ?? '')?.purchaseOrderId;
            if (token !== undefined && token.length > 0) {
              await IapStore.finishPurchase(context, iap.ProductType.AUTORENEWABLE,
                token, orderId ?? '');
            }
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

  private static async verifyWithBff(jwsPurchaseOrder: string | null,
    jwsSubscriptionStatus: string | null, productType: string,
    localTripId: string | null): Promise<IapResult> {
    if (ApiConfig.BFF_BASE_URL.length === 0) {
      Logger.info(TAG, 'BFF 未配置，跳过 IAP 校验（开发期）');
      return { success: true, message: '购买成功（未校验）', passId: localTripId };
    }

    try {
      const body: Record<string, string> = {};
      if (jwsPurchaseOrder !== null && jwsPurchaseOrder.length > 0) {
        body['jwsPurchaseOrder'] = jwsPurchaseOrder;
      }
      if (jwsSubscriptionStatus !== null && jwsSubscriptionStatus.length > 0) {
        body['jwsSubscriptionStatus'] = jwsSubscriptionStatus;
      }
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
    productType: iap.ProductType, purchaseToken: string, purchaseOrderId: string): Promise<void> {
    try {
      const finishParam: iap.FinishPurchaseParameter = {
        productType: productType,
        purchaseToken: purchaseToken,
        purchaseOrderId: purchaseOrderId
      };
      await iap.finishPurchase(context, finishParam);
      Logger.info(TAG, '发货确认完成');
    } catch (err) {
      Logger.warn(TAG, `发货确认失败: ${(err as Error).message}`);
    }
  }
}
