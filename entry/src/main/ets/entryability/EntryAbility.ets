import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { Logger } from '../common/logger/Logger';
import { APP_NAV } from '../common/constants/AppNav';
import { DataSeeder } from '../data/DataSeeder';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private pendingRoute: string = '';

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    // 外部拉起预填通道（hdc/深链，将来小艺 Skill onNewWant 同源复用）：
    // aa start --ps route GenerateFailed
    const params: Record<string, Object> | undefined = want.parameters;
    if (params !== undefined && typeof params['route'] === 'string') {
      this.pendingRoute = params['route'] as string;
    }
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    // 深色零阴影门控（契约 §4）：页面用 @StorageProp('isDarkMode') 决定是否挂 elevation
    AppStorage.setOrCreate('isDarkMode',
      newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
      this.registerSerifFont(windowStage);
      DataSeeder.seedIfEmpty(this.context).catch((err: Error) => {
        Logger.error('EntryAbility', `种子灌入失败: ${err.message}`);
      });
      if (this.pendingRoute.length > 0) {
        APP_NAV.pushPath({ name: this.pendingRoute });
      }
      this.pendingRoute = '';
    });

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }

  onError(error: Error): void {
    Logger.error('EntryAbility', `未捕获异常: ${error.message}`);
  }


  // 内置 Noto Serif SC（OFL，沿用有据打包件）。契约 serif 仅 display/title 两档且均 700，
  // 只注册 Bold 一档（有据经验：一个 familyName 只能绑一个字体文件）。
  private registerSerifFont(windowStage: window.WindowStage): void {
    try {
      windowStage.getMainWindowSync().getUIContext().getFont().registerFont({
        familyName: 'NotoSerifSC',
        familySrc: $rawfile('fonts/NotoSerifSC-Bold.otf')
      });
    } catch (err) {
      Logger.error('EntryAbility', `衬线字体注册失败: ${(err as Error).message}`);
    }
  }
}