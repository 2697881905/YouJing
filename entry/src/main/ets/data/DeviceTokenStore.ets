/**
 * 设备票据存储（商业化方案 §4.2 / §5 错误码 6001）。
 *
 * 契约：
 * - deviceId 是端上生成的 UUID，首次激活时创建并持久化，之后不变；
 * - deviceToken 是 BFF /v1/device/activate 返回的 Bearer 票据，每次请求带在 Authorization 头里；
 * - token 失效（BFF 回 401/6001）时由 DeviceActivator 重新激活，本 Store 只负责存取。
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Logger } from '../common/logger/Logger';

const TAG: string = 'Data.DeviceTokenStore';
const PREFS_NAME: string = 'youjing_device';
const KEY_DEVICE_ID: string = 'device_id';
const KEY_DEVICE_TOKEN: string = 'device_token';
const KEY_ACTIVATED_AT: string = 'activated_at';

export class DeviceTokenStore {
  private static prefs: preferences.Preferences | null = null;
  private static deviceId: string = '';
  private static deviceToken: string = '';
  private static activatedAt: number = 0;

  static async init(context: common.Context): Promise<void> {
    try {
      DeviceTokenStore.prefs = await preferences.getPreferences(context, PREFS_NAME);
      const rawId: preferences.ValueType = DeviceTokenStore.prefs.getSync(KEY_DEVICE_ID, '');
      const rawToken: preferences.ValueType = DeviceTokenStore.prefs.getSync(KEY_DEVICE_TOKEN, '');
      const rawAt: preferences.ValueType = DeviceTokenStore.prefs.getSync(KEY_ACTIVATED_AT, 0);
      DeviceTokenStore.deviceId = typeof rawId === 'string' ? rawId : '';
      DeviceTokenStore.deviceToken = typeof rawToken === 'string' ? rawToken : '';
      DeviceTokenStore.activatedAt = typeof rawAt === 'number' ? rawAt : 0;
      Logger.info(TAG, `设备标识恢复 id=${DeviceTokenStore.maskedId()} token=${DeviceTokenStore.hasToken() ? '有' : '无'}`);
    } catch (err) {
      Logger.warn(TAG, `设备标识读取失败: ${(err as Error).message}`);
    }
  }

  static getDeviceId(): string {
    return DeviceTokenStore.deviceId;
  }

  static getToken(): string {
    return DeviceTokenStore.deviceToken;
  }

  static hasToken(): boolean {
    return DeviceTokenStore.deviceToken.length > 0;
  }

  static isActivated(): boolean {
    return DeviceTokenStore.deviceToken.length > 0 && DeviceTokenStore.activatedAt > 0;
  }

  static async saveToken(token: string): Promise<void> {
    DeviceTokenStore.deviceToken = token;
    DeviceTokenStore.activatedAt = Date.now();
    const prefs: preferences.Preferences | null = DeviceTokenStore.prefs;
    if (prefs === null) {
      Logger.warn(TAG, '未 init 就写 token，只落了内存');
      return;
    }
    try {
      prefs.putSync(KEY_DEVICE_TOKEN, token);
      prefs.putSync(KEY_ACTIVATED_AT, DeviceTokenStore.activatedAt);
      await prefs.flush();
      Logger.info(TAG, `设备票据已持久化 token=${DeviceTokenStore.maskedToken()}`);
    } catch (err) {
      Logger.warn(TAG, `设备票据持久化失败: ${(err as Error).message}`);
    }
  }

  static async ensureDeviceId(): Promise<string> {
    if (DeviceTokenStore.deviceId.length > 0) {
      return DeviceTokenStore.deviceId;
    }
    DeviceTokenStore.deviceId = DeviceTokenStore.generateUuid();
    const prefs: preferences.Preferences | null = DeviceTokenStore.prefs;
    if (prefs !== null) {
      try {
        prefs.putSync(KEY_DEVICE_ID, DeviceTokenStore.deviceId);
        await prefs.flush();
        Logger.info(TAG, `设备标识首次生成 id=${DeviceTokenStore.maskedId()}`);
      } catch (err) {
        Logger.warn(TAG, `设备标识持久化失败: ${(err as Error).message}`);
      }
    }
    return DeviceTokenStore.deviceId;
  }

  static async clear(): Promise<void> {
    DeviceTokenStore.deviceToken = '';
    DeviceTokenStore.activatedAt = 0;
    const prefs: preferences.Preferences | null = DeviceTokenStore.prefs;
    if (prefs === null) {
      return;
    }
    try {
      prefs.deleteSync(KEY_DEVICE_TOKEN);
      prefs.deleteSync(KEY_ACTIVATED_AT);
      await prefs.flush();
      Logger.info(TAG, '设备票据已清除');
    } catch (err) {
      Logger.warn(TAG, `设备票据清除失败: ${(err as Error).message}`);
    }
  }

  private static generateUuid(): string {
    const hex: string = '0123456789abcdef';
    const parts: string[] = ['', '', '', '', ''];
    for (let i = 0; i < 8; i++) {
      parts[0] += hex[Math.floor(Math.random() * 16)];
    }
    for (let i = 0; i < 4; i++) {
      parts[1] += hex[Math.floor(Math.random() * 16)];
    }
    parts[2] = '4';
    for (let i = 0; i < 3; i++) {
      parts[2] += hex[Math.floor(Math.random() * 16)];
    }
    parts[3] = hex[8 + Math.floor(Math.random() * 4)];
    for (let i = 0; i < 3; i++) {
      parts[3] += hex[Math.floor(Math.random() * 16)];
    }
    for (let i = 0; i < 12; i++) {
      parts[4] += hex[Math.floor(Math.random() * 16)];
    }
    return `${parts[0]}-${parts[1]}-${parts[2]}-${parts[3]}-${parts[4]}`;
  }

  private static maskedId(): string {
    const id: string = DeviceTokenStore.deviceId;
    return id.length <= 8 ? id : `${id.substring(0, 8)}***`;
  }

  private static maskedToken(): string {
    const t: string = DeviceTokenStore.deviceToken;
    return t.length <= 8 ? `${t.length}字符` : `${t.substring(0, 8)}***(${t.length}字符)`;
  }
}