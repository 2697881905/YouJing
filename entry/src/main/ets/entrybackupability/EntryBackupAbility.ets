import { BackupExtensionAbility, BundleVersion } from '@kit.CoreFileKit';
import { Logger } from '../common/logger/Logger';

export default class EntryBackupAbility extends BackupExtensionAbility {
  async onBackup() {
    Logger.info('EntryBackupAbility', 'onBackup ok');
    await Promise.resolve();
  }

  async onRestore(bundleVersion: BundleVersion) {
    Logger.info('EntryBackupAbility', `onRestore ok ${JSON.stringify(bundleVersion)}`);
    await Promise.resolve();
  }
}
