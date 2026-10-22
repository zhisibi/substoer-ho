/**
 * Store.ets: global app state (singleton): service settings (port / autostart / LAN access / background),
 * language, privacy consent and the startup disclaimer, window insets and breakpoints, toast / confirm helpers,
 * navigation. Sub-Store's own data lives in the embedded backend's store under filesDir/substore; the HTTP server
 * that runs it is Server.ets. Colors follow the system light / dark mode, like the Sub-Store web UI.
 */
import { LangState, resolveLang, t, tf } from './I18n';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { Prefs } from './Prefs';
import { CORE_VERSION, DEFAULT_PORT } from './AppInfo';
import { Palette, darkPalette, lightPalette } from './Theme';
import { Log } from './Log';
import { CoreApi } from './Core';

/** Bump when the disclaimer & privacy notice changes materially: everyone is asked to consent again. */
export const PRIVACY_VERSION: number = 5;
/** Bump when the disclaimer changes: it is shown again even to users who chose 不再提示. */
export const DISCLAIMER_VERSION: number = 2;

export type Breakpoint = 'sm' | 'md' | 'lg';

export type Task = () => Promise<void>;

@ObservedV2
export class Store {
  private static inst: Store | null = null;

  static get(): Store {
    if (Store.inst === null) {
      Store.inst = new Store();
    }
    return Store.inst;
  }

  ctx: common.UIAbilityContext | null = null;
  uiCtx: UIContext | null = null;
  win: window.Window | null = null;
  private prefs: Prefs | null = null;
  nav: NavPathStack = new NavPathStack();

  @Trace consented: boolean = false;
  /** startup disclaimer dialog is showing */
  @Trace disclaimerOpen: boolean = false;
  /** '' = core OK, 'missing' = libmimisubstore.so not in the HAP, else the wrong version found */
  @Trace coreProblem: string = '';
  @Trace langPref: string = 'system';
  @Trace port: number = DEFAULT_PORT;
  @Trace autoStart: boolean = true;
  /** listen on 0.0.0.0 (other devices may fetch /download and /share) */
  @Trace lanAccess: boolean = false;
  /** other devices may also open the web UI and call /api */
  @Trace lanUI: boolean = false;
  /** ask the system for a long-running task while the server runs */
  @Trace background: boolean = true;
  @Trace systemDark: boolean = false;
  @Trace bp: Breakpoint = 'sm';
  @Trace safeTop: number = 0;
  @Trace safeBottom: number = 0;
  /** bumped on language change so every view rebuilds */
  @Trace epoch: number = 0;
  foreground: boolean = true;

  init(ctx: common.UIAbilityContext): void {
    this.ctx = ctx;
    try {
      this.prefs = new Prefs(ctx);
    } catch (e) {
      Log.e('Store', 'preferences unavailable', e as Object);
      return;
    }
    const p = this.prefs;
    this.consented = p.num('consent', 0) >= PRIVACY_VERSION;
    this.langPref = p.str('lang', 'system');
    LangState.get().lang = resolveLang(this.langPref);
    this.port = p.num('port', DEFAULT_PORT);
    this.autoStart = p.bool('autoStart', true);
    this.lanAccess = p.bool('lanAccess', false);
    this.lanUI = p.bool('lanUI', false);
    this.background = p.bool('background', true);
    // shown on every launch unless the user ticked 不再提示 for this version (the consent page covers first launch)
    this.disclaimerOpen = this.consented && p.num('disclaimerMuted', 0) < DISCLAIMER_VERSION;
    const cv = CoreApi.version();
    this.coreProblem = cv.length === 0 ? 'missing' : (cv === CORE_VERSION ? '' : cv);
    Log.i('Store', 'init: core ' + cv);
  }

  /** First launch: the disclaimer & privacy notice is accepted. */
  acceptPrivacy(): void {
    this.consented = true;
    this.prefs?.put('consent', PRIVACY_VERSION);
  }

  /** Startup disclaimer acknowledged; `mute` = 不再提示 (until the disclaimer changes). */
  closeDisclaimer(mute: boolean): void {
    this.disclaimerOpen = false;
    if (mute) {
      this.prefs?.put('disclaimerMuted', DISCLAIMER_VERSION);
    }
  }

  /** Withdraw consent: forget it and quit; next launch asks again. */
  revokePrivacy(): void {
    this.prefs?.put('consent', 0);
    this.prefs?.put('disclaimerMuted', 0);
    this.consented = false;
    this.nav.clear();
    this.ctx?.terminateSelf();
  }

  async warnCore(): Promise<void> {
    if (this.coreProblem.length === 0) {
      return;
    }
    Log.e('Store', 'core problem: ' + this.coreProblem);
    const msg = this.coreProblem === 'missing' ?
      t('这个安装包没有包含内核 libmimisubstore.so，无法运行 Sub-Store 后端。如果是自己编译的，请先运行 core/build-core.sh（见 README）再重新编译。') :
      tf('内核版本不符：应用需要 {0}，安装包里是 {1}。请重新编译内核，否则部分功能可能异常。', CORE_VERSION, this.coreProblem);
    await this.confirm(t('内核异常'), msg, t('我知道了'), false);
  }

  setOpt(key: string, v: string | number | boolean): void {
    if (key === 'port') {
      this.port = v as number;
    } else if (key === 'autoStart') {
      this.autoStart = v as boolean;
    } else if (key === 'lanAccess') {
      this.lanAccess = v as boolean;
    } else if (key === 'lanUI') {
      this.lanUI = v as boolean;
    } else if (key === 'background') {
      this.background = v as boolean;
    }
    this.prefs?.put(key, v);
  }

  isDark(): boolean {
    return this.systemDark;
  }

  palette(): Palette {
    return this.isDark() ? darkPalette() : lightPalette();
  }

  /** 'system' | 'zh' | 'en'; views are re-created so cached texts follow */
  setLang(pref: string): void {
    this.langPref = pref;
    this.prefs?.put('lang', pref);
    const lang = resolveLang(pref);
    if (lang !== LangState.get().lang) {
      LangState.get().lang = lang;
      this.epoch++;
    }
  }

  onSystemLanguage(): void {
    if (this.langPref === 'system') {
      this.setLang('system');
    }
  }

  /**
   * 直接写入一个普通设置（供页面保存零散选项，如日志字体大小）。
   * @param key 键名
   * @param v 值
   */
  setPref(key: string, v: string | number | boolean): void {
    this.prefs?.put(key, v);
  }

  /** Reads a plain setting written with setPref. */
  prefStr(key: string, def: string): string {
    return this.prefs !== null ? this.prefs.str(key, def) : def;
  }

  prefBool(key: string, def: boolean): boolean {
    return this.prefs !== null ? this.prefs.bool(key, def) : def;
  }

  // =====================================================================
  // window
  // =====================================================================

  /**
   * 开启沉浸式全屏布局并监听避让区域变化。
   * @param win 主窗口
   * 注意：全屏后内容会延伸到状态栏和底部手势条下方，所以需要 safeTop/safeBottom 给页面留出内边距；
   *       旋转、折叠屏展开等都会触发 avoidAreaChange，此时重新计算。
   */
  setupImmersive(win: window.Window): void {
    this.win = win;
    try {
      win.setWindowLayoutFullScreen(true).catch(() => {
        Log.w('Store', 'setWindowLayoutFullScreen rejected');
      });
    } catch (e) {
      Log.w('Store', 'setWindowLayoutFullScreen failed');
    }
    this.updateAvoidArea(win);
    try {
      win.on('avoidAreaChange', (d: window.AvoidAreaOptions) => {
        if (d.type === window.AvoidAreaType.TYPE_SYSTEM || d.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
          this.updateAvoidArea(win);
        }
      });
    } catch (e) {
      Log.w('Store', 'avoidAreaChange listener failed');
    }
  }

  /**
   * 像素转 vp；UI 上下文不可用时按 3 倍密度估算。
   * @param px 像素值
   */
  private px2vp(px: number): number {
    const ui = this.uiCtx;
    if (ui !== null) {
      try {
        return ui.px2vp(px);
      } catch (e) {
        // fall through
      }
    }
    return px / 3;
  }

  /**
   * 读取系统状态栏与底部导航指示条的避让高度并更新 safeTop/safeBottom（值不变时不赋值，避免无谓刷新）。
   * @param win 主窗口
   */
  updateAvoidArea(win: window.Window): void {
    try {
      const sys = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const top = Math.round(this.px2vp(sys.topRect.height));
      if (top !== this.safeTop) {
        this.safeTop = top;
      }
      const nav = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const bottom = Math.round(this.px2vp(nav.bottomRect.height));
      if (bottom !== this.safeBottom) {
        this.safeBottom = bottom;
      }
    } catch (e) {
      Log.w('Store', 'getWindowAvoidArea failed');
    }
  }

  /** Status bar icons dark on light theme, light on dark theme */
  /**
   * 中文说明：设置系统栏为透明背景，并按当前主题设置图标/文字颜色（浅色主题用黑色，深色主题用白色）。
   */
  applySystemBar(): void {
    const w = this.win;
    if (w === null) {
      return;
    }
    const dark = this.isDark();
    try {
      w.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
        statusBarContentColor: dark ? '#FFFFFF' : '#000000',
        navigationBarContentColor: dark ? '#FFFFFF' : '#000000'
      }).catch(() => {
        Log.w('Store', 'setWindowSystemBarProperties rejected');
      });
    } catch (e) {
      Log.w('Store', 'setWindowSystemBarProperties failed');
    }
  }

  /** Window width → breakpoint (sm phone, md / lg tablet and 2in1). */
  setWidth(vpWidth: number): void {
    const bp: Breakpoint = vpWidth >= 840 ? 'lg' : vpWidth >= 600 ? 'md' : 'sm';
    if (bp !== this.bp) {
      this.bp = bp;
    }
  }

  /** Bottom padding for scrolling pages (clears the gesture indicator). */
  bottomPad(): number {
    return this.safeBottom + 20;
  }

  // =====================================================================
  // UI helpers
  // =====================================================================

  /**
   * 显示短暂提示（2.2 秒）。UI 上下文不可用时退化为写日志。
   * @param msg 提示文本
   */
  toast(msg: string): void {
    const ui = this.uiCtx;
    if (ui === null) {
      Log.i('Toast', msg);
      return;
    }
    try {
      ui.getPromptAction().showToast({ message: msg, duration: 2200 });
    } catch (e) {
      Log.i('Toast', msg);
    }
  }

  /** Two-button confirmation; resolves true when confirmed */
  /**
   * 中文说明：显示双按钮确认对话框。
   * @param title 标题
   * @param message 正文
   * @param okText 确认按钮文字
   * @param danger 是否为危险操作（确认按钮显示为红色）
   * @returns 用户确认 resolve(true)；取消、点击外部关闭或无法显示时 resolve(false)
   */
  confirm(title: string, message: string, okText: string, danger: boolean): Promise<boolean> {
    return new Promise<boolean>((resolve: (v: boolean) => void) => {
      const ui = this.uiCtx;
      if (ui === null) {
        resolve(false);
        return;
      }
      const p = this.palette();
      try {
        ui.showAlertDialog({
          title: title,
          message: message,
          autoCancel: true,
          alignment: DialogAlignment.Center,
          primaryButton: {
            value: t('取消'),
            action: () => {
              resolve(false);
            }
          },
          secondaryButton: {
            value: okText,
            fontColor: danger ? p.bad : p.accent,
            action: () => {
              resolve(true);
            }
          },
          cancel: () => {
            resolve(false);
          }
        });
      } catch (e) {
        Log.e('Store', 'showAlertDialog failed', e as Object);
        resolve(false);
      }
    });
  }
  /** Dialog with several stacked buttons; resolves the index picked, or -1 when cancelled. */
  choose(title: string, message: string, options: string[]): Promise<number> {
    return new Promise<number>((resolve: (v: number) => void) => {
      const ui = this.uiCtx;
      if (ui === null) {
        resolve(-1);
        return;
      }
      const p = this.palette();
      const buttons: AlertDialogButtonOptions[] = options.map((o: string, i: number): AlertDialogButtonOptions => {
        const b: AlertDialogButtonOptions = {
          value: o,
          fontColor: p.accent,
          action: () => {
            resolve(i);
          }
        };
        return b;
      });
      buttons.push({
        value: t('取消'), fontColor: p.subtle, action: () => {
          resolve(-1);
        }
      });
      try {
        ui.showAlertDialog({
          title: title,
          message: message,
          autoCancel: true,
          alignment: DialogAlignment.Center,
          buttonDirection: DialogButtonDirection.VERTICAL,
          buttons: buttons,
          cancel: () => {
            resolve(-1);
          }
        });
      } catch (e) {
        Log.e('Store', 'showAlertDialog failed', e as Object);
        resolve(-1);
      }
    });
  }

  async run(label: string, okMsg: string, task: Task): Promise<boolean> {
    try {
      await task();
      if (okMsg.length > 0) {
        this.toast(okMsg);
      }
      return true;
    } catch (e) {
      Log.e('Action', label + ' failed', e as Object);
      this.toast(tf('{0}失败：{1}', label, (e as Error).message ?? String(e)));
      return false;
    }
  }


  /**
   * 推入一个导航页面。
   * @param name 路由名（与 Navigation 的 navDestination 对应）
   * @param param 页面参数；null 时传入空对象
   */
  push(name: string, param: Object | null): void {
    // Pages test the parameter with instanceof, so "no parameter" is passed as a plain empty object
    const arg: Object = param !== null ? param : new Object();
    this.nav.pushPathByName(name, arg, true);
  }

  /** 返回上一页（带动画） */
  pop(): void {
    this.nav.pop(true);
  }
}

