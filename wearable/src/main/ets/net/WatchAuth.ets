/**
 * 手表 Account Kit 登录（G0-N-b）。
 * 与手机同一应用、同一华为账号 → 同一个 unionId → BFF 同一个 account.id。
 */

import { authentication } from '@kit.AccountKit';
import { common } from '@kit.AbilityKit';

export interface WatchIdentity {
  idToken: string;
  unionId: string;
}

export class WatchAuth {
  /**
   * forceLogin=true 时允许拉起华为账号登录界面（探针首次登录用）；
   * 生产态可改 false 做静默续期。
   */
  static async login(context: common.UIAbilityContext, forceLogin: boolean): Promise<WatchIdentity> {
    const provider: authentication.HuaweiIDProvider = new authentication.HuaweiIDProvider();
    const request: authentication.LoginWithHuaweiIDRequest = provider.createLoginWithHuaweiIDRequest();
    request.forceLogin = forceLogin;
    const controller: authentication.AuthenticationController =
      new authentication.AuthenticationController(context);
    const response: authentication.LoginWithHuaweiIDResponse =
      await controller.executeRequest(request) as authentication.LoginWithHuaweiIDResponse;
    const data = response.data;
    if (data === undefined) {
      throw new Error('Account Kit 未返回登录数据');
    }
    const identity: WatchIdentity = {
      idToken: data.idToken === undefined ? '' : data.idToken,
      unionId: data.unionID === undefined ? '' : data.unionID
    };
    return identity;
  }
}
