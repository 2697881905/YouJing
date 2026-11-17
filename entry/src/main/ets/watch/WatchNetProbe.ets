/**
 * 手机侧切片0 探针：确认手机能作为同一账号从 BFF 拉到手表决策（G0-N-d 的手机端）。
 *
 * 只读：GET /watch/decisions → 打印 → ack；不执行任何业务动作。
 * BFF 未部署时明确记录「未就绪」，不伪造拉取成功。
 */

import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { ApiConfig } from '../common/config/ApiConfig';
import { DeviceActivator } from '../data/DeviceActivator';
import { DeviceTokenStore } from '../data/DeviceTokenStore';
import { Logger } from '../common/logger/Logger';

const TAG: string = 'Probe.WatchNet';

interface WatchDecisionLike {
  v: number;
  type: string;
  cardId: string;
  optionKey: string;
  ts: number;
}

interface DecisionItem {
  id: number;
  decision: WatchDecisionLike;
  createdAt: string;
}

interface DecisionsResponse {
  decisions: DecisionItem[];
}

interface HttpTextResponse {
  status: number;
  body: string;
}

interface AckBody {
  ids: number[];
}

export class WatchNetProbe {
  static async run(context: common.Context): Promise<void> {
    if (ApiConfig.BFF_BASE_URL.length === 0) {
      Logger.warn(TAG, 'BFF_BASE_URL 为空：G0-N-a 未就绪');
      return;
    }
    Logger.info(TAG, `BFF=${ApiConfig.BFF_BASE_URL}，开始设备激活`);
    const activated: boolean = await DeviceActivator.activate(context);
    if (!activated) {
      Logger.warn(TAG, '设备激活失败：BFF 不可达或身份票据缺失（G0-N-a/c）');
      return;
    }
    const token: string = DeviceTokenStore.getToken();
    if (token.length === 0) {
      Logger.warn(TAG, '无设备票据，无法拉取决策');
      return;
    }
    const resp: HttpTextResponse =
      await WatchNetProbe.request(http.RequestMethod.GET, `${ApiConfig.BFF_BASE_URL}/watch/decisions`, token, '');
    Logger.info(TAG, `GET /watch/decisions HTTP ${resp.status} body=${resp.body.slice(0, 300)}`);
    if (resp.status !== 200) {
      return;
    }
    const data: DecisionsResponse = JSON.parse(resp.body) as DecisionsResponse;
    if (data.decisions.length === 0) {
      Logger.info(TAG, 'BFF 暂无待执行手表决策');
      return;
    }
    const ids: number[] = [];
    for (const item of data.decisions) {
      ids.push(item.id);
      Logger.info(TAG, `待执行决策 id=${item.id} cardId=${item.decision.cardId} ` +
        `option=${item.decision.optionKey} ts=${item.decision.ts}`);
    }
    const body: AckBody = { ids: ids };
    const ack: HttpTextResponse = await WatchNetProbe.request(
      http.RequestMethod.POST, `${ApiConfig.BFF_BASE_URL}/watch/decision/ack`, token, JSON.stringify(body));
    Logger.info(TAG, `ack HTTP ${ack.status} ids=${ids.join(',')} body=${ack.body.slice(0, 120)}`);
  }

  private static async request(method: http.RequestMethod, url: string, token: string,
    payload: string): Promise<HttpTextResponse> {
    const req: http.HttpRequest = http.createHttp();
    try {
      const header: Record<string, string> = {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
      };
      const options: http.HttpRequestOptions = {
        method: method,
        header: header,
        connectTimeout: ApiConfig.CONNECT_TIMEOUT_MS,
        readTimeout: ApiConfig.READ_TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING
      };
      if (payload.length > 0) {
        options.extraData = payload;
      }
      const resp: http.HttpResponse = await req.request(url, options);
      const result: HttpTextResponse = {
        status: resp.responseCode as number,
        body: typeof resp.result === 'string' ? resp.result as string : ''
      };
      return result;
    } finally {
      req.destroy();
    }
  }
}
