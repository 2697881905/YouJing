/**
 * 屏15 的前台到达监听（切片2 T1）。
 *
 * 只订阅「仅使用期间」的前台 `locationChange`：退后台/锁屏不保活、不申请长时任务，
 * 也不注册系统围栏（围栏监测服务还卡在 AGC 审核，见 Docs/围栏与后台唤醒开通清单.md）。
 * 页面 onAppear 起、onDisappear 停；权限被拒或系统定位总开关关闭时返回 false，
 * 调用方静默降级成原来的手动打卡，不再二次劝说。
 *
 * 退订先摘回调再 off：off 期间若还有一次在途回调，不能再打进已销毁的页面。
 */

import { abilityAccessCtrl, common, PermissionRequestResult } from '@kit.AbilityKit';
import { geoLocationManager } from '@kit.LocationKit';
import { Logger } from '../logger/Logger';

const TAG: string = 'Location.Arrival';

/** 一次前台定位结果；精度（accuracyM）只给界面显示，不参与到站判定 */
export interface LocationFix {
  latitude: number;
  longitude: number;
  accuracyM: number;
}

export class ArrivalWatcher {
  /**
   * 10s / 20m 一档：到站判定不需要秒级刷新，稀疏采样省电；
   * DAILY_LIFE_SERVICE 是系统给「日常场景」的低功耗档，不是导航档。
   */
  private static readonly REQUEST: geoLocationManager.LocationRequest = {
    priority: geoLocationManager.LocationRequestPriority.ACCURACY,
    scenario: geoLocationManager.LocationRequestScenario.DAILY_LIFE_SERVICE,
    timeInterval: 10000,
    distanceInterval: 20
  };

  private active: boolean = false;
  private callback: ((loc: geoLocationManager.Location) => void) | null = null;
  private listener: ((fix: LocationFix) => void) | null = null;
  /** 取消令牌：权限弹窗期间页面退订/又发起一次 start 时，旧的那次不得再订阅 */
  private token: number = 0;

  /** 申请定位权限；拒绝或异常返回 false */
  static async ensurePermission(context: common.Context): Promise<boolean> {
    try {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const result: PermissionRequestResult = await atManager.requestPermissionsFromUser(
        context, ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.LOCATION']);
      for (const code of result.authResults) {
        if (code !== 0) {
          Logger.info(TAG, '定位权限未授予，到站检测降级为手动打卡');
          return false;
        }
      }
      return true;
    } catch (err) {
      Logger.warn(TAG, `定位权限申请异常: ${(err as Error).message}`);
      return false;
    }
  }

  /** 开始监听；返回 false 表示没起来（无定位能力/权限/系统开关/订阅异常），调用方按降级处理 */
  async start(context: common.Context, onFix: (fix: LocationFix) => void): Promise<boolean> {
    if (this.active) {
      this.listener = onFix;
      return true;
    }
    // 编译期告警：geoLocationManager 并非所有设备都有（无定位能力的平板/车机）
    if (!canIUse('SystemCapability.Location.Location.Core')) {
      Logger.info(TAG, '本设备无定位能力，到站检测不启动');
      return false;
    }
    const token: number = ++this.token;
    try {
      if (!geoLocationManager.isLocationEnabled()) {
        Logger.info(TAG, '系统定位总开关关闭，到站检测不启动');
        return false;
      }
    } catch (err) {
      Logger.warn(TAG, `定位开关读取失败: ${(err as Error).message}`);
      return false;
    }
    if (!await ArrivalWatcher.ensurePermission(context)) {
      return false;
    }
    // 弹窗期间页面已经退了、或又发起了一次 start：这次作废
    if (token !== this.token) {
      return false;
    }
    const cb: (loc: geoLocationManager.Location) => void =
      (loc: geoLocationManager.Location): void => {
        const sink: ((fix: LocationFix) => void) | null = this.listener;
        if (sink === null) {
          return;
        }
        const fix: LocationFix = {
          latitude: loc.latitude, longitude: loc.longitude, accuracyM: loc.accuracy
        };
        sink(fix);
      };
    this.callback = cb;
    this.listener = onFix;
    try {
      geoLocationManager.on('locationChange', ArrivalWatcher.REQUEST, cb);
      this.active = true;
      return true;
    } catch (err) {
      this.callback = null;
      this.listener = null;
      Logger.warn(TAG, `定位订阅失败: ${(err as Error).message}`);
      return false;
    }
  }

  /** 停止监听；重复调用安全 */
  stop(): void {
    // 先作废在途的 start 并摘回调：权限弹窗/off 期间的在途回调都不再打到页面
    this.token += 1;
    this.listener = null;
    const cb: ((loc: geoLocationManager.Location) => void) | null = this.callback;
    this.callback = null;
    if (!this.active) {
      return;
    }
    this.active = false;
    if (cb === null) {
      return;
    }
    try {
      geoLocationManager.off('locationChange', cb);
    } catch (err) {
      Logger.warn(TAG, `定位退订异常: ${(err as Error).message}`);
    }
  }
}
