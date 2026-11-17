/**
 * 手表入口 Ability（薄端）：只负责把 WatchHome 页面挂起来。
 */

import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { Logger } from '../common/Logger';

export default class WatchAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    Logger.info('Watch.Ability', 'WatchAbility onCreate');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/WatchHome', (err): void => {
      if (err.code) {
        Logger.error('Watch.Ability', `loadContent 失败 code=${err.code} msg=${err.message}`);
        return;
      }
      Logger.info('Watch.Ability', 'WatchHome 已加载');
    });
  }

  onForeground(): void {
    Logger.info('Watch.Ability', 'onForeground');
  }

  onBackground(): void {
    Logger.info('Watch.Ability', 'onBackground');
  }

  onDestroy(): void {
    Logger.info('Watch.Ability', 'onDestroy');
  }
}
