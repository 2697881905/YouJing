/**
 * 手机侧 Wear Engine 传输（唯一碰 @kit.WearEngine 的文件）。
 *
 * 真机约束以本机 SDK 声明为准：
 * - 入口是 `@kit.WearEngine`（不是社区帖里的 @kit.WearEngineKit）；
 * - P2P 消息 content 为 Uint8Array，byteLength ∈ [1, 4096)；
 * - 对端用 AppInfo{bundleName, fingerprint} 匹配（G0-c 待真机确认指纹取值）。
 *
 * 本类只做「连上/发/收」三件事，业务路由在 WatchBridge；连不上时安静降级。
 */

import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { wearEngine } from '@kit.WearEngine';
import {
  WATCH_MAX_MESSAGE_BYTES, WATCH_REMOTE_BUNDLE, WATCH_REMOTE_FINGERPRINT, WATCH_SEND_BUDGET_BYTES
} from 'watchcontract';
import { Logger } from '../common/logger/Logger';

const TAG: string = 'Watch.Transport';

export class WearEngineTransport {
  private p2p: wearEngine.P2pClient | null = null;
  private deviceId: string = '';
  private deviceLabel: string = '';
  private appParam: wearEngine.P2pAppParam | null = null;
  private receiver: ((message: wearEngine.P2pMessage) => void) | null = null;
  private dieListener: (() => void) | null = null;
  private connected: boolean = false;
  private connecting: boolean = false;

  isConnected(): boolean {
    return this.connected;
  }

  deviceName(): string {
    return this.deviceLabel;
  }

  /**
   * 发现已配对手表并订阅消息。返回 true = 通道就绪。
   * 失败不抛：手表是可选延伸，连不上只打一条日志。
   */
  async init(context: common.Context, onText: (text: string) => void): Promise<boolean> {
    if (this.connected) {
      return true;
    }
    if (this.connecting) {
      return false;
    }
    this.connecting = true;
    try {
      if (!canIUse('SystemCapability.Health.WearEngine')) {
        Logger.warn(TAG, '本机不支持 SystemCapability.Health.WearEngine（第三方准入或系统版本不足）');
        return false;
      }
      const device: wearEngine.Device | null = await this.pickDevice(context);
      if (device === null) {
        Logger.warn(TAG, '未发现已配对的 HarmonyOS 手表（G0-b）');
        return false;
      }
      const supported: boolean =
        await device.isWearEngineCapabilitySupported(wearEngine.WearEngineCapability.P2P_COMMUNICATION);
      if (!supported) {
        Logger.warn(TAG, `设备 ${device.name} 不支持 P2P 通信`);
        return false;
      }
      const p2p: wearEngine.P2pClient = wearEngine.getP2pClient(context);
      const appParam: wearEngine.P2pAppParam = {
        remoteApp: {
          bundleName: WATCH_REMOTE_BUNDLE,
          fingerprint: WATCH_REMOTE_FINGERPRINT
        }
      };
      const receiver: (message: wearEngine.P2pMessage) => void =
        (message: wearEngine.P2pMessage): void => {
          try {
            const text: string = util.TextDecoder.create('utf-8').decodeToString(message.content);
            onText(text);
          } catch (err) {
            Logger.warn(TAG, `消息解码失败: ${(err as Error).message}`);
          }
        };
      await p2p.registerMessageReceiver(device.randomId, appParam, receiver);

      this.p2p = p2p;
      this.deviceId = device.randomId;
      this.deviceLabel = device.name === undefined ? '' : device.name;
      this.appParam = appParam;
      this.receiver = receiver;
      this.connected = true;
      this.watchServiceDie();
      Logger.info(TAG, `通道就绪 device=${this.deviceLabel} model=${device.model} ` +
        `batch=${device.softwareVersion} fingerprintEmpty=${WATCH_REMOTE_FINGERPRINT.length === 0}`);
      return true;
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      // 1008500004 = App 未申请 Wear Engine 服务（G0-a 的关键证据）
      Logger.warn(TAG, `Wear Engine 初始化失败 code=${be.code} msg=${be.message}`);
      return false;
    } finally {
      this.connecting = false;
    }
  }

  /** 发一条 JSON 文本；失败即标记断连，由桥接层下次重连 */
  async send(text: string): Promise<boolean> {
    if (!this.connected || this.p2p === null || this.appParam === null) {
      return false;
    }
    try {
      const bytes: Uint8Array = util.TextEncoder.create('utf-8').encodeInto(text);
      if (bytes.length <= 0 || bytes.length >= WATCH_MAX_MESSAGE_BYTES) {
        Logger.warn(TAG, `消息字节数越界 bytes=${bytes.length}（SDK 上限 [1, ${WATCH_MAX_MESSAGE_BYTES})）`);
        return false;
      }
      if (bytes.length > WATCH_SEND_BUDGET_BYTES) {
        Logger.warn(TAG, `消息超出预算 bytes=${bytes.length} budget=${WATCH_SEND_BUDGET_BYTES}`);
        return false;
      }
      const result: wearEngine.P2pResult =
        await this.p2p.sendMessage(this.deviceId, this.appParam, { content: bytes });
      const ok: boolean = result.code === wearEngine.P2pResultCode.COMMUNICATION_SUCCESS;
      if (!ok) {
        Logger.warn(TAG, `发送未成功 code=${result.code} bytes=${bytes.length}`);
      } else {
        Logger.info(TAG, `发送成功 bytes=${bytes.length}`);
      }
      return ok;
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      Logger.warn(TAG, `发送异常 code=${be.code} msg=${be.message}`);
      this.connected = false;
      return false;
    }
  }

  /** 服务进程死亡：标记断连，等下一次 init */
  private watchServiceDie(): void {
    if (this.dieListener !== null) {
      return;
    }
    const listener: () => void = (): void => {
      Logger.warn(TAG, 'Wear Engine 服务进程结束，通道断开');
      this.connected = false;
    };
    this.dieListener = listener;
    try {
      wearEngine.on('serviceDie', listener);
    } catch (err) {
      Logger.warn(TAG, `serviceDie 订阅失败: ${(err as Error).message}`);
    }
  }

  private async pickDevice(context: common.Context): Promise<wearEngine.Device | null> {
    const client: wearEngine.DeviceClient = wearEngine.getDeviceClient(context);
    const devices: wearEngine.Device[] = await client.getConnectedDevices();
    Logger.info(TAG, `已发现设备数=${devices.length}`);
    let fallback: wearEngine.Device | null = null;
    for (const device of devices) {
      const label: string = device.name === undefined ? '' : device.name;
      Logger.info(TAG, `候选设备 randomId=${device.randomId} name=${label} model=${device.model} ` +
        `smartWatch=${device.isSmartWatch}`);
      if (device.isSmartWatch === true) {
        return device;
      }
      if (fallback === null) {
        fallback = device;
      }
    }
    return fallback;
  }
}
