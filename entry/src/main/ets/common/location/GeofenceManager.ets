/**
 * 到站围栏管理（P5）。
 *
 * 现状：地理围栏服务需要 AGC 侧开通/审核（见 Docs/围栏与后台唤醒开通清单.md）。
 * 本类只负责「今天该围哪几站 + 注册/撤销 + 到站回调」，注册失败时静默降级：
 * 页面继续用 ArrivalWatcher 的前台定位，不影响手动打卡。
 *
 * 后台唤醒（App 被杀后仍能收到围栏事件）还需要 FenceExtensionAbility 与审核通过后的
 * Profile；这一层先不伪造，回调只在进程存活时消费。
 */

import { abilityAccessCtrl, common, Permissions, PermissionRequestResult } from '@kit.AbilityKit';
import { geoLocationManager } from '@kit.LocationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../logger/Logger';
import { TripDay } from '../../model/Trip';
import { FenceSpec, GeofencePlan } from '../../utils/GeofencePlan';

const TAG: string = 'Location.Geofence';
const LOITER_MS: number = 10000;

export type GeofenceEnter = (spec: FenceSpec) => void;

export class GeofenceManager {
  private ids: number[] = [];
  private specs: Map<number, FenceSpec> = new Map();
  /** ENTER 与 DWELL 会先后各回调一次，按 fenceId 去重，避免到站通知重复响 */
  private announced: Set<number> = new Set();
  private onEnter: GeofenceEnter | null = null;
  private active: boolean = false;
  private starting: boolean = false;
  /** stop 时自增；授权/注册途中页面已离开的 start 据此中止并清掉自己刚注册的围栏 */
  private cancelToken: number = 0;

  isActive(): boolean {
    return this.active;
  }

  isStarting(): boolean {
    return this.starting;
  }

  /** 注册今天尚未结束的站点围栏；返回成功注册的数量（0 = 服务未开通/无权限/无坐标） */
  async start(context: common.Context, day: TripDay, nowMin: number,
    onEnter: GeofenceEnter): Promise<number> {
    if (this.starting) {
      return this.ids.length;
    }
    this.starting = true;
    const token: number = ++this.cancelToken;
    // 这里只能走内部 stop：外部 stop 会重置 starting，导致两次快速 reload 重复注册围栏
    await this.stopInternal();
    if (token !== this.cancelToken) {
      return 0;
    }
    this.onEnter = onEnter;
    const granted: boolean = await GeofenceManager.ensurePermission(context);
    if (token !== this.cancelToken) {
      return 0;
    }
    if (!granted) {
      this.starting = false;
      return 0;
    }
    const specs: FenceSpec[] = GeofencePlan.of(day, nowMin);
    // 注册只发生在当天首次 reload；固定 4h 会让下午的站提前失效，按当日剩余时间给有效期
    const expirationSec: number = Math.max(3600, (1440 - nowMin) * 60 + 3600);
    for (const spec of specs) {
      if (token !== this.cancelToken) {
        break;
      }
      const fence: geoLocationManager.Geofence = {
        latitude: spec.latitude,
        longitude: spec.longitude,
        radius: spec.radiusM,
        expiration: expirationSec
      };
      const request: geoLocationManager.GnssGeofenceRequest = {
        geofence: fence,
        monitorTransitionEvents: [
          geoLocationManager.GeofenceTransitionEvent.GEOFENCE_TRANSITION_EVENT_ENTER,
          geoLocationManager.GeofenceTransitionEvent.GEOFENCE_TRANSITION_EVENT_DWELL
        ],
        loiterTimeMs: LOITER_MS,
        geofenceTransitionCallback: (err: BusinessError, transition: geoLocationManager.GeofenceTransition): void => {
          this.handleTransition(err, transition);
        }
      };
      try {
        const id: number = await geoLocationManager.addGnssGeofence(request);
        this.ids.push(id);
        this.specs.set(id, spec);
      } catch (err) {
        const be: BusinessError = err as BusinessError;
        Logger.warn(TAG, `围栏注册失败「${spec.title}」code=${be.code} ${be.message}`);
      }
    }
    if (token !== this.cancelToken) {
      // 新的 start/stop 已接管并清过场；这里不能再动 ids/starting，否则会误删新一批围栏
      return 0;
    }
    this.active = this.ids.length > 0;
    this.starting = false;
    Logger.info(TAG, `围栏计划 ${specs.length} 站 / 注册成功 ${this.ids.length} 站`);
    return this.ids.length;
  }

  async stop(): Promise<void> {
    this.cancelToken++;
    await this.stopInternal();
    this.starting = false;
  }

  /** 撤销并清空状态；不碰 starting，由调用方决定注册/停止的并发语义 */
  private async stopInternal(): Promise<void> {
    for (const id of this.ids) {
      try {
        await geoLocationManager.removeGnssGeofence(id);
      } catch (err) {
        Logger.warn(TAG, `撤销围栏 ${id} 失败: ${(err as Error).message}`);
      }
    }
    this.ids = [];
    this.specs.clear();
    this.announced.clear();
    this.onEnter = null;
    this.active = false;
  }

  private handleTransition(err: BusinessError, transition: geoLocationManager.GeofenceTransition): void {
    const code: number = err === null || err === undefined ? 0 : err.code;
    if (code !== 0) {
      Logger.warn(TAG, `围栏事件错误 code=${code}`);
      return;
    }
    const event: geoLocationManager.GeofenceTransitionEvent = transition.transitionEvent;
    if (event !== geoLocationManager.GeofenceTransitionEvent.GEOFENCE_TRANSITION_EVENT_ENTER &&
      event !== geoLocationManager.GeofenceTransitionEvent.GEOFENCE_TRANSITION_EVENT_DWELL) {
      return;
    }
    const spec: FenceSpec | undefined = this.specs.get(transition.geofenceId);
    if (spec === undefined) {
      return;
    }
    if (this.announced.has(transition.geofenceId)) {
      Logger.info(TAG, `到站围栏 ${spec.title} 已提示，忽略 event=${event}`);
      return;
    }
    this.announced.add(transition.geofenceId);
    Logger.info(TAG, `到站围栏 ${spec.title} event=${event}`);
    const cb: GeofenceEnter | null = this.onEnter;
    if (cb !== null) {
      cb(spec);
    }
  }

  private static async ensurePermission(context: common.Context): Promise<boolean> {
    try {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const perms: Permissions[] = ['ohos.permission.LOCATION', 'ohos.permission.APPROXIMATELY_LOCATION'];
      const result: PermissionRequestResult = await atManager.requestPermissionsFromUser(context, perms);
      for (const code of result.authResults) {
        if (code !== 0) {
          Logger.info(TAG, '定位权限未授予，围栏降级为前台到站检测');
          return false;
        }
      }
      return true;
    } catch (err) {
      Logger.warn(TAG, `围栏权限申请异常: ${(err as Error).message}`);
      return false;
    }
  }
}
