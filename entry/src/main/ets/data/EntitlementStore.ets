/**
 * 权益缓存与导出校验（商业化方案 §4.2 / §8）。
 *
 * 契约：
 * - 权益数据由 BFF /v1/entitlement 返回，端上缓存到 preferences（TTL 5 分钟）；
 * - canExport() 是导出付费墙的判定入口：订阅有效或该行程有通行证即放行；
 * - 离线时用缓存判定，缓存过期或无缓存时默认拒绝导出（保守策略）；
 * - **例外**：`ApiConfig.DEV_SKIP_BFF` 为真时整套门禁放开（开发机本地开关，仓库版恒 false）。
 *   没这条例外，BFF 未部署（`BFF_BASE_URL` 空串 → 永不写入缓存）会让
 *   `canGenerate()` 恒 false，点「生成行程」直接跳付费页，主路径整条死掉。
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Logger } from '../common/logger/Logger';
import { ApiConfig } from '../common/config/ApiConfig';
import { AccountStore } from './AccountStore';
import { DeviceTokenStore } from './DeviceTokenStore';

const TAG: string = 'Data.EntitlementStore';
const PREFS_NAME: string = 'youjing_entitlement';
const KEY_ENTITLEMENT: string = 'entitlement_json';
const KEY_CACHED_AT: string = 'cached_at';
const CACHE_TTL_MS: number = 5 * 60 * 1000;

export interface PassInfo {
  localTripId: string;
  status: string;
  expiresAt: string | null;
}

export interface SubscriptionInfo {
  status: string;
  periodEnd: string;
}

export interface Entitlement {
  subscription: SubscriptionInfo | null;
  passes: PassInfo[];
  giftRemaining: number;
  usedToday: number;
  dailyCap: number;
}

/** BFF `quota` 快照里端侧会消费的字段（其余如 source 只用于日志）。 */
export interface QuotaSnapshot {
  subscription?: SubscriptionInfo | null;
  passes?: PassInfo[];
  giftRemaining?: number;
  remainingToday?: number;
  dailyCap?: number;
}

/**
 * 服务端配额快照 → 本地权益缓存。
 *
 * 三条不可退化的语义：
 * 1. 服务端**明确返回 `subscription: null`** 时必须清掉本地值——这是订阅到期/退款
 *    在端上唯一起作用的通路（D9：此前 `subscription: current.subscription` 原样结转，
 *    退款后 UI 仍显示订阅有效，直到缓存过期）。
 * 2. 字段缺省（旧版 BFF 不回传）才沿用旧值，不能用 undefined 把已有权益抹掉。
 * 3. `dailyCap` 也以服务端为准：上限口径改了（如 20 次/天 → 20 次/月）不该等端侧发版。
 */
export function mergeQuotaSnapshot(current: Entitlement, quota: QuotaSnapshot): Entitlement {
  const merged: Entitlement = {
    subscription: quota.subscription !== undefined ? quota.subscription : current.subscription,
    passes: quota.passes !== undefined ? quota.passes : current.passes,
    giftRemaining: quota.giftRemaining !== undefined ? quota.giftRemaining : current.giftRemaining,
    usedToday: quota.remainingToday !== undefined ? quota.remainingToday : current.usedToday,
    dailyCap: quota.dailyCap !== undefined ? quota.dailyCap : current.dailyCap
  };
  return merged;
}

function emptyEntitlement(): Entitlement {
  return {
    subscription: null,
    passes: [],
    giftRemaining: 0,
    usedToday: 0,
    dailyCap: 0
  };
}

export class EntitlementStore {
  private static cached: Entitlement = emptyEntitlement();
  private static cachedAt: number = 0;
  private static prefs: preferences.Preferences | null = null;

  static async init(context: common.Context): Promise<void> {
    try {
      EntitlementStore.prefs =
        await preferences.getPreferences(context, PREFS_NAME);
      const rawJson: preferences.ValueType =
        EntitlementStore.prefs.getSync(KEY_ENTITLEMENT, '');
      const rawAt: preferences.ValueType =
        EntitlementStore.prefs.getSync(KEY_CACHED_AT, 0);
      if (typeof rawJson === 'string' && rawJson.length > 0) {
        EntitlementStore.cached = JSON.parse(rawJson) as Entitlement;
        EntitlementStore.cachedAt = typeof rawAt === 'number' ? rawAt : 0;
      }
      Logger.info(TAG, `权益缓存恢复 valid=${EntitlementStore.isCacheValid()}`);
      if (ApiConfig.DEV_SKIP_BFF) {
        Logger.warn(TAG, 'DEV_SKIP_BFF=1：权益门禁已放开（仅开发机本地配置，仓库版恒 false）');
      }
    } catch (err) {
      Logger.warn(TAG, `权益缓存读取失败: ${(err as Error).message}`);
    }
  }

  static get(): Entitlement {
    return EntitlementStore.cached;
  }

  static isCacheValid(): boolean {
    return Date.now() - EntitlementStore.cachedAt < CACHE_TTL_MS;
  }

  static hasSubscription(): boolean {
    const sub: SubscriptionInfo | null = EntitlementStore.cached.subscription;
    return sub !== null && sub.status === 'active';
  }

  static hasPass(tripId: string): boolean {
    return EntitlementStore.cached.passes.some((p: PassInfo): boolean =>
      p.localTripId === tripId && p.status === 'active');
  }

  /** 开发态旁路：见文件头契约最后一条与 ApiConfig.DEV_SKIP_BFF 的注释。 */
  static devBypass(): boolean {
    return ApiConfig.DEV_SKIP_BFF;
  }

  static canExport(tripId: string): boolean {
    if (EntitlementStore.devBypass()) {
      return true;
    }
    if (!EntitlementStore.isCacheValid() || AccountStore.isGuest()) {
      return false;
    }
    return EntitlementStore.hasSubscription() || EntitlementStore.hasPass(tripId);
  }

  static hasGiftQuota(): boolean {
    return EntitlementStore.cached.giftRemaining > 0;
  }

  static canGenerate(): boolean {
    if (EntitlementStore.devBypass()) {
      return true;
    }
    if (!EntitlementStore.isCacheValid()) {
      // 缓存过期**不等于**没额度：票据还在就把判断交给服务端（真用尽会回 402，端侧照样跳付费页）。
      // 原实现直接 return false，再叠加 `DeviceActivator`「已激活就不再刷新权益」，
      // 会让持有效票据的用户在 5 分钟 TTL 之后**永久**停在付费页——2026-11-03 端到端联调
      // 连续 4 次生成全落付费页、BFF 一次都没被调用，就是这个组合造成的。
      return DeviceTokenStore.hasToken();
    }
    if (EntitlementStore.hasSubscription()) {
      return EntitlementStore.cached.usedToday < EntitlementStore.cached.dailyCap;
    }
    if (AccountStore.isGuest()) {
      return EntitlementStore.hasGiftQuota();
    }
    return EntitlementStore.hasGiftQuota();
  }

  static async update(entitlement: Entitlement): Promise<void> {
    EntitlementStore.cached = entitlement;
    EntitlementStore.cachedAt = Date.now();
    const prefs: preferences.Preferences | null = EntitlementStore.prefs;
    if (prefs === null) {
      return;
    }
    try {
      prefs.putSync(KEY_ENTITLEMENT, JSON.stringify(entitlement));
      prefs.putSync(KEY_CACHED_AT, EntitlementStore.cachedAt);
      await prefs.flush();
    } catch (err) {
      Logger.warn(TAG, `权益缓存写入失败: ${(err as Error).message}`);
    }
  }

  static async clear(): Promise<void> {
    EntitlementStore.cached = emptyEntitlement();
    EntitlementStore.cachedAt = 0;
    const prefs: preferences.Preferences | null = EntitlementStore.prefs;
    if (prefs === null) {
      return;
    }
    try {
      prefs.deleteSync(KEY_ENTITLEMENT);
      prefs.deleteSync(KEY_CACHED_AT);
      await prefs.flush();
    } catch (err) {
      Logger.warn(TAG, `权益缓存清除失败: ${(err as Error).message}`);
    }
  }
}