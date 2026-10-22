/** Ability lifecycle: initialise Store and Server, window insets, color mode, optional server autostart. */
import { SsUpdate } from '../common/SsUpdate';
import { AbilityConstant, ConfigurationConstant, UIAbility, Want, Configuration } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { Store } from '../common/Store';
import { Server } from '../common/Server';
import { Log } from '../common/Log';
import { t } from '../common/I18n';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const store = Store.get();
    store.systemDark = this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    store.init(this.context);
    Server.get().init();
    Log.i('Ability', 'onCreate, launch reason ' + launchParam.launchReason);
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    const store = Store.get();
    store.systemDark = newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    store.applySystemBar();
    store.onSystemLanguage();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err: BusinessError) => {
      if (err.code) {
        Log.e('Ability', 'loadContent failed: ' + err.code);
        return;
      }
      try {
        const win = windowStage.getMainWindowSync();
        const store = Store.get();
        store.uiCtx = win.getUIContext();
        store.setupImmersive(win);
        store.applySystemBar();
        setTimeout(() => {
          store.warnCore();
          if (store.coreProblem.length === 0) {
            setTimeout(() => {
              SsUpdate.get().startupCheck();
            }, 8000);
          }
          if (store.consented && store.autoStart && !Server.get().running && store.coreProblem !== 'missing') {
            Server.get().start().then((ok: boolean) => {
              if (ok) {
                Log.i('Ability', 'server autostarted on ' + store.port);
              }
            });
          }
        }, 300);
      } catch (e) {
        Log.e('Ability', 'window init failed', e as Object);
      }
    });
  }

  onForeground(): void {
    Store.get().foreground = true;
    Server.get().onForeground();
  }

  onBackground(): void {
    Store.get().foreground = false;
    if (Server.get().running && !Server.get().bgActive) {
      Log.i('Ability', t('后台运行未开启'));
    }
  }

  onDestroy(): void {
    Server.get().shutdown();
  }
}
