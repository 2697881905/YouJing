/**
 * P5 到站系统通知（不依赖实况窗权益）。
 *
 * 围栏 ENTER 事件 → 本地通知；退后台/锁屏时由系统通知中心展示。
 * 这不是代理提醒，不需要 AGC 能力；只受应用通知开关约束。
 */

import { notificationManager } from '@kit.NotificationKit';
import { wantAgent, WantAgent } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Activity, TripDay } from '../../model/Trip';
import { Logger } from '../logger/Logger';

const TAG: string = 'Live.ArrivalNotice';

export class ArrivalNotice {
  static async publishForStop(day: TripDay, stop: Activity): Promise<boolean> {
    try {
      const enabled: boolean = await notificationManager.isNotificationEnabled();
      if (!enabled) {
        Logger.warn(TAG, '通知开关关闭，到站通知未发');
        return false;
      }
      const id: number = ArrivalNotice.idOf(day, stop);
      // F3 真机结论：无槽位/remindFlags=0 的静默通知根本不会转发到手表。
      // 到站提醒同时承担「手表 App 未装/未开时的文字兜底」（US-9），故必须带提醒槽位。
      try {
        await notificationManager.addSlot(notificationManager.SlotType.SOCIAL_COMMUNICATION);
      } catch (err) {
        // 槽位已存在或系统拒绝：不影响本次发布，继续按请求里的 slotType 走
        Logger.warn(TAG, `社交通讯槽位创建失败: ${(err as Error).message}`);
      }
      const request: notificationManager.NotificationRequest = {
        id: id,
        notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: `已到「${stop.title}」`,
            text: `可以打卡了 · 有径 Day ${day.dayIndex}`,
            additionalText: '有径'
          }
        },
        tapDismissed: true
      };
      const agent: WantAgent | null = await ArrivalNotice.clickAction();
      if (agent !== null) {
        request.wantAgent = agent;
      }
      await notificationManager.publish(request);
      Logger.info(TAG, `到站通知已发布 id=${id} stop=${stop.title}`);
      return true;
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      Logger.warn(TAG, `到站通知发布失败 code=${be.code} ${be.message}`);
      return false;
    }
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
      Logger.warn(TAG, `clickAction 创建失败 code=${be.code} ${be.message}`);
      return null;
    }
  }

  /** 同一天同一站稳定 id：重复进入围栏只更新同一条通知，不堆叠。
   *  用 20 亿段与 TripReminder 的 0–1 亿段隔开，避免到站通知覆盖系统提醒。 */
  private static idOf(day: TripDay, stop: Activity): number {
    const key: string = `${day.date}:${stop.id}`;
    let hash: number = 0;
    for (let i = 0; i < key.length; i++) {
      hash = (hash * 31 + key.charCodeAt(i)) % 100000;
    }
    return 2000000000 + hash;
  }
}
