/**
 * 阶段 8 回归（可离线部分）：游客登录态与静默登录兜底。
 *
 * 覆盖：未 init 时静态初值即游客分区（uid 绝不会是空串）、ACCOUNT_KIT_ENABLED=false
 * 时 login() 不抛错且不改分区键。
 *
 * 不在此覆盖：DB v2 user_id 列、按 uid 收口的读写、游客数据归户、preferences 分片读写。
 * 真机实测（探针用例结论）：ohosTest 进程只挂 ApplicationContext，
 * relationalStore 报「Parameter error.Illegal context.」、preferences 报
 * 「The context is invalid.」，且 application.createModuleContext 对该 context
 * 直接报「must be a context of stageMode」——造不出合法模块 context。
 * 这批行为改由真机 App 内验收（见 Docs/INIT_REPORT.md 已知限制）：
 * 启动日志「迁移完成 1 → 2」+「恢复登录态 kind=guest uid=local-guest」+
 * 生成行程后屏12 仍能列出并打开该行程。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { AccountStore } from '../../../main/ets/data/AccountStore';
import { AccountConfig } from '../../../main/ets/common/config/AccountConfig';
import { AccountKind, AccountState } from '../../../main/ets/model/Account';

export default function accountTest(): void {
  describe('AccountState', () => {
    it('silent_login_falls_back_to_guest', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, async () => {
      const state: AccountState = AccountStore.state();
      expect(state.uid).assertEqual(AccountConfig.GUEST_UID);
      expect(state.kind).assertEqual(AccountKind.GUEST);
      expect(AccountStore.isGuest()).assertTrue();
      expect(AccountStore.uid().length > 0).assertTrue();

      // 开关关闭：不抛错、不改分区键（masked 也不泄漏完整标识）
      const ctx: common.UIAbilityContext =
        abilityDelegatorRegistry.getAbilityDelegator().getAppContext() as common.UIAbilityContext;
      const after: AccountState = await AccountStore.login(ctx);
      expect(after.uid).assertEqual(AccountConfig.GUEST_UID);
      expect(AccountStore.uid()).assertEqual(AccountConfig.GUEST_UID);
      expect(AccountStore.masked().length > 0).assertTrue();
    });
  });
}
