/**
 * 文件说明：Updater.ets —— 应用自身的版本更新检查。
 *
 * 职责：通过 StoreKit 的 updateManager 向华为应用市场（AppGallery）查询是否有新版本，
 *       有则弹出系统自带的更新对话框，没有则提示“已是最新版本”。
 * 主要类型：Updater（只含静态方法）。
 * 与其他模块的关系：
 *  - 使用 Store 提供的 UIAbilityContext（store.ctx）和 toast；
 *  - 使用 versionName() 读取当前版本号；
 *  - 使用 I18n.t() 做文案翻译、Log 记录失败原因。
 * 注意：这里检查的是“本 App”的更新。
 */
import { t } from './I18n';
import { updateManager } from '@kit.StoreKit';
import { versionName } from './AppInfo';
import { Store } from './Store';
import { Log } from './Log';

/**
 * Update check through AppGallery (StoreKit updateManager). The app is distributed on AppGallery,
 * so updates use the system's own update dialog. Only runs when the user taps "检查更新" in Settings → About.
 */
/**
 * 应用更新检查器。
 *
 * 只在用户于“软件设置 → 关于 → 检查更新”点击时触发，不做后台自动检查（上架要求及避免打扰用户）。
 */
export class Updater {
  // 防重入标志：用户连续点击时，只保留第一次检查，避免弹出多个系统更新对话框
  private static checking: boolean = false;

  /**
   * 检查应用市场是否有新版本。
   *
   * @param store 全局 Store，提供 UIAbilityContext 与 toast 能力
   * @returns Promise<void>；结果通过系统对话框或 toast 反馈给用户，不向调用方返回
   * 异常：内部捕获所有异常（网络失败、非应用市场安装等），只记录日志并提示用户，不会向外抛出。
   * 注意：ctx 为空（Ability 尚未初始化）或已有检查在进行中时直接返回。
   */
  static async check(store: Store): Promise<void> {
    const ctx = store.ctx;
    if (Updater.checking || ctx === null) {
      return;
    }
    Updater.checking = true;
    store.toast(t('正在检查更新…'));
    try {
      const r = await updateManager.checkAppUpdate(ctx);
      // 只有 LATER_VERSION_EXIST 才代表市场上有更高版本；其余返回码均视为“已是最新”
      if (r.updateAvailable === updateManager.UpdateAvailableCode.LATER_VERSION_EXIST) {
        await updateManager.showUpdateDialog(ctx);
      } else {
        store.toast(t('已是最新版本 ') + versionName());
      }
    } catch (e) {
      Log.w('Updater', 'check failed: ' + Log.describe(e as Object));
      // 常见原因：不是从华为应用市场安装（调试包、侧载），或应用尚未上架
      store.toast(t('检查更新失败，请稍后再试或前往应用市场查看'));
    } finally {
      // 无论成功失败都要复位，否则之后的点击会被永久忽略
      Updater.checking = false;
    }
  }
}
