/**
 * P5 到站实况窗（生产件，默认关闭）。
 *
 * 当前真机证据：参数校验通过后 startLiveViewByTrigger 返回
 * 1003500005「The right of liveView is not enabled」——需要 AGC 实况窗权益
 * 与重签含 com.huawei.service.liveView.entry 的 Profile。
 * 权益通过后把 LiveViewConfig.ENABLED 置 true，OnTripPage 到站事件即接此件。
 */

import { wantAgent, WantAgent } from '@kit.AbilityKit';
import { liveViewManager } from '@kit.LiveViewKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Activity, TripDay } from '../../model/Trip';
import { Logger } from '../logger/Logger';

const TAG: string = 'Live.TripLiveView';
const PICKUP_PIC: string = 'liveview_pickup.png';

export class TripLiveView {
  private static live: liveViewManager.LiveView | null = null;

  static async isEnabled(): Promise<boolean> {
    try {
      return await liveViewManager.isGeofenceTriggerEnabled();
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      Logger.warn(TAG, `查询围栏实况窗开关失败 code=${be.code} ${be.message}`);
      return false;
    }
  }

  /** 到站：注册「进入站点围栏 → 创建实况窗」；失败只记日志，不影响打卡 */
  static async startForStop(day: TripDay, stop: Activity): Promise<boolean> {
    await TripLiveView.stop();
    if (!(await TripLiveView.isEnabled())) {
      return false;
    }
    const clickAction: WantAgent | null = await TripLiveView.clickAction();
    if (clickAction === null) {
      return false;
    }
    const live: liveViewManager.LiveView = TripLiveView.buildLive(day, stop, clickAction);
    const trigger: liveViewManager.Trigger = TripLiveView.buildTrigger(stop);
    try {
      const result: liveViewManager.LiveViewResult =
        await liveViewManager.startLiveViewByTrigger(live, trigger);
      TripLiveView.live = live;
      Logger.info(TAG, `实况窗已注册 ${stop.title} result=${JSON.stringify(result)}`);
      return true;
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      Logger.warn(TAG, `实况窗注册失败 ${stop.title} code=${be.code} ${be.message}`);
      return false;
    }
  }

  static async stop(): Promise<void> {
    const live: liveViewManager.LiveView | null = TripLiveView.live;
    TripLiveView.live = null;
    if (live === null) {
      return;
    }
    try {
      await liveViewManager.stopLiveView(live);
      Logger.info(TAG, '实况窗已结束');
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      Logger.warn(TAG, `实况窗结束失败 code=${be.code} ${be.message}`);
    }
  }

  private static buildLive(day: TripDay, stop: Activity,
    clickAction: WantAgent): liveViewManager.LiveView {
    const layout: liveViewManager.PickupLayout = {
      layoutType: liveViewManager.LayoutType.LAYOUT_TYPE_PICKUP,
      title: '下一站',
      content: `${stop.title} · 可以打卡了`,
      descPic: PICKUP_PIC
    };
    const live: liveViewManager.LiveView = {
      id: TripLiveView.idOf(day, stop),
      event: 'CHECK_IN',
      liveViewData: {
        primary: {
          title: '有径 · 到站提醒',
          content: [{ text: `已到「${stop.title}」，可以打卡了` }],
          clickAction: clickAction,
          layoutData: layout
        }
      }
    };
    return live;
  }

  private static buildTrigger(stop: Activity): liveViewManager.Trigger {
    const trigger: liveViewManager.Trigger = {
      type: liveViewManager.TriggerType.TRIGGER_TYPE_GEOFENCE,
      condition: {
        coordinateSystemType: liveViewManager.CoordinateSystemType.COORDINATE_TYPE_GCJ02,
        longitude: stop.longitude,
        latitude: stop.latitude,
        radius: 200,
        monitorEvent: liveViewManager.MonitorEvent.MONITOR_TYPE_ENTRY,
        delayTime: 0
      },
      displayTime: 900
    };
    return trigger;
  }

  private static async clickAction(): Promise<WantAgent | null> {
    try {
      const info: wantAgent.WantAgentInfo = {
        wants: [{ bundleName: 'com.youjing.app', abilityName: 'EntryAbility' }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 1,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      return await wantAgent.getWantAgent(info);
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      Logger.warn(TAG, `实况窗 clickAction 创建失败 code=${be.code} ${be.message}`);
      return null;
    }
  }

  /** 同一行程同一天同一站稳定复用一个 int32 id，避免重复注册互相覆盖 */
  private static idOf(day: TripDay, stop: Activity): number {
    const key: string = `${day.date}:${stop.id}`;
    let hash: number = 0;
    for (let i = 0; i < key.length; i++) {
      hash = (hash * 31 + key.charCodeAt(i)) % 2147483647;
    }
    return hash;
  }
}
