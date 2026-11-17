/**
 * 切片0 地基探针（G0-N）：手表独立联网 → Account Kit 登录 → BFF 验签 → 一条决策往返。
 *
 * 这是一块「探针屏」，不是业务 UI；G0-N 全绿前不铺卡片/决策业务界面。
 * 任何失败都明说「未连接/HTTP xxx」，不假装成功。
 */

import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { pushService } from '@kit.PushKit';
import { WatchAuth, WatchIdentity } from '../net/WatchAuth';
import { WatchBffClient, WatchBffResponse } from '../net/WatchBffClient';
import { Logger } from '../common/Logger';

const TAG: string = 'Watch.ProbeNet';
const PREFS_NAME: string = 'watch_net_probe';
const KEY_DEVICE_ID: string = 'watchDeviceId';

interface SessionRequest {
  watchDeviceId: string;
  idToken: string;
}

interface SessionResponse {
  deviceToken: string;
  accountId: number;
}

interface WhoAmIResponse {
  accountId: number;
  deviceId: string;
  pushConfigured: boolean;
}

interface PushTokenBody {
  pushToken: string;
}

interface ProbeDecision {
  v: number;
  type: string;
  cardId: string;
  optionKey: string;
  ts: number;
}

interface DecisionBody {
  decision: ProbeDecision;
}

@Entry
@Component
struct WatchHome {
  @State private status: string = '切片0 · 未连接';
  @State private logText: string = '等待操作';
  @State private busy: boolean = false;
  @State private loggedIn: boolean = false;
  private token: string = '';
  private accountId: number = 0;
  private deviceId: string = '';

  aboutToAppear(): void {
    const context: common.UIAbilityContext = this.hostContext();
    try {
      const store: preferences.Preferences =
        preferences.getPreferencesSync(context, { name: PREFS_NAME });
      const saved: preferences.ValueType = store.getSync(KEY_DEVICE_ID, '');
      if (typeof saved === 'string' && (saved as string).length > 0) {
        this.deviceId = saved as string;
      } else {
        this.deviceId = util.generateRandomUUID(true);
        store.putSync(KEY_DEVICE_ID, this.deviceId);
        store.flushSync();
      }
      this.appendLog(`设备号 ${this.deviceId.slice(0, 8)}…`);
    } catch (err) {
      Logger.warn(TAG, `设备号读取失败: ${(err as Error).message}`);
      this.deviceId = util.generateRandomUUID(true);
    }
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private appendLog(line: string): void {
    const now: Date = new Date();
    const hh: string = now.getHours().toString().padStart(2, '0');
    const mm: string = now.getMinutes().toString().padStart(2, '0');
    const ss: string = now.getSeconds().toString().padStart(2, '0');
    const next: string = `${hh}:${mm}:${ss} ${line}\n${this.logText}`;
    this.logText = next.split('\n').slice(0, 6).join('\n');
  }

  private async loginAndConnect(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.status = '正在登录华为账号…';
    try {
      const identity: WatchIdentity = await WatchAuth.login(this.hostContext(), true);
      if (identity.idToken.length === 0) {
        throw new Error('Account Kit 未返回 idToken');
      }
      this.appendLog(`登录成功 union=${identity.unionId.length > 0 ? '有' : '无'}`);
      const body: SessionRequest = {
        watchDeviceId: this.deviceId,
        idToken: identity.idToken
      };
      const resp: WatchBffResponse =
        await WatchBffClient.post('/watch/session', '', JSON.stringify(body));
      if (resp.status !== 200) {
        throw new Error(`session HTTP ${resp.status} ${resp.body.slice(0, 60)}`);
      }
      const data: SessionResponse = JSON.parse(resp.body) as SessionResponse;
      this.token = data.deviceToken;
      this.accountId = data.accountId;
      this.loggedIn = true;
      this.status = `已连接 · uid=${data.accountId}`;
      this.appendLog(`BFF 会话成功 uid=${data.accountId}`);
      await this.checkWhoAmI();
      await this.registerPush();
    } catch (err) {
      this.status = '未连接';
      this.appendLog(`失败: ${(err as Error).message}`);
      Logger.warn(TAG, `登录链路失败: ${(err as Error).message}`);
    } finally {
      this.busy = false;
    }
  }

  private async checkWhoAmI(): Promise<void> {
    const resp: WatchBffResponse = await WatchBffClient.get('/watch/whoami', this.token);
    if (resp.status !== 200) {
      this.appendLog(`whoami HTTP ${resp.status}`);
      return;
    }
    const me: WhoAmIResponse = JSON.parse(resp.body) as WhoAmIResponse;
    const same: boolean = me.accountId === this.accountId;
    this.appendLog(`uid 对表 ${same ? '一致' : '不一致'} (${me.accountId})`);
  }

  private async registerPush(): Promise<void> {
    try {
      const pushToken: string = await pushService.getToken();
      if (pushToken.length === 0) {
        this.appendLog('Push token 为空');
        return;
      }
      const body: PushTokenBody = { pushToken: pushToken };
      const resp: WatchBffResponse =
        await WatchBffClient.post('/watch/push-token', this.token, JSON.stringify(body));
      this.appendLog(`Push 注册 HTTP ${resp.status}`);
    } catch (err) {
      // Push Kit 未在 AGC 开通时这里会失败；G0-N-e 待用户侧配置，不伪造成功
      this.appendLog(`Push 不可用: ${(err as Error).message.slice(0, 50)}`);
    }
  }

  private async sendDecision(): Promise<void> {
    if (this.busy) {
      return;
    }
    if (this.token.length === 0) {
      this.status = '请先登录连接';
      return;
    }
    this.busy = true;
    try {
      const decision: ProbeDecision = {
        v: 1,
        type: 'decision',
        cardId: `probe-net-${this.deviceId.slice(0, 6)}`,
        optionKey: 'checkin',
        ts: Date.now()
      };
      const body: DecisionBody = { decision: decision };
      const resp: WatchBffResponse =
        await WatchBffClient.post('/watch/decision', this.token, JSON.stringify(body));
      this.status = resp.status === 200 ? '决策已提交' : `提交失败 HTTP ${resp.status}`;
      this.appendLog(`decision HTTP ${resp.status} ${resp.body.slice(0, 50)}`);
    } catch (err) {
      this.status = '未连接';
      this.appendLog(`决策失败: ${(err as Error).message.slice(0, 50)}`);
    } finally {
      this.busy = false;
    }
  }

  private async pullCurrentCard(): Promise<void> {
    if (this.busy) {
      return;
    }
    if (this.token.length === 0) {
      this.status = '请先登录连接';
      return;
    }
    this.busy = true;
    try {
      const resp: WatchBffResponse = await WatchBffClient.get('/watch/card/current', this.token);
      this.status = resp.status === 200 ? '已拉到当前卡' : `无当前卡 HTTP ${resp.status}`;
      this.appendLog(`card HTTP ${resp.status} ${resp.body.slice(0, 40)}`);
    } catch (err) {
      this.status = '未连接';
      this.appendLog(`拉卡失败: ${(err as Error).message.slice(0, 50)}`);
    } finally {
      this.busy = false;
    }
  }

  build() {
    Column() {
      Text('有径 · 手表切片0')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFFFF')
        .margin({ bottom: 4 })

      Text(this.status)
        .fontSize(10)
        .fontColor('#B3FFFFFF')
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .margin({ bottom: 8 })

      Button({ type: ButtonType.Capsule, stateEffect: true }) {
        Text(this.busy ? '处理中…' : (this.loggedIn ? '重新登录' : '登录并连接 BFF'))
          .fontSize(12)
          .fontColor('#FFFFFFFF')
      }
      .width('82%')
      .height(32)
      .backgroundColor('#FF0A59F7')
      .enabled(!this.busy)
      .margin({ bottom: 6 })
      .onClick((): void => {
        this.loginAndConnect();
      })

      Button({ type: ButtonType.Capsule, stateEffect: true }) {
        Text('发送测试决策')
          .fontSize(12)
          .fontColor('#FFFFFFFF')
      }
      .width('82%')
      .height(30)
      .backgroundColor('#24FFFFFF')
      .enabled(!this.busy && this.loggedIn)
      .margin({ bottom: 6 })
      .onClick((): void => {
        this.sendDecision();
      })

      Button({ type: ButtonType.Capsule, stateEffect: true }) {
        Text('拉当前卡')
          .fontSize(12)
          .fontColor('#FFFFFFFF')
      }
      .width('82%')
      .height(30)
      .backgroundColor('#24FFFFFF')
      .enabled(!this.busy && this.loggedIn)
      .margin({ bottom: 8 })
      .onClick((): void => {
        this.pullCurrentCard();
      })

      Text(this.logText)
        .fontSize(8)
        .fontColor('#80FFFFFF')
        .textAlign(TextAlign.Start)
        .maxLines(6)
        .width('86%')
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 20, bottom: 18 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#FF000000')
  }
}
