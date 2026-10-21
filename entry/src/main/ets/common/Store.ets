/**
 * Store.ets: global app state (singleton): settings (server port / autostart / LAN access, theme, accent,
 * background, glass, language), privacy consent, window insets and breakpoints, toast / confirm helpers, navigation.
 * Sub-Store's own data (subscriptions, collections, artifacts, files, settings) lives in the embedded backend's
 * store under filesDir/substore; the HTTP server that runs it is Server.ets.
 */
import { LangState, isEn, resolveLang, t, tf } from './I18n';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { Prefs } from './Prefs';
import { CORE_VERSION, DEFAULT_PORT } from './AppInfo';
import {
  ACCENTS, AccentDef, BACKDROPS, BackdropDef, Palette, applyAccent, applyBackdrop, darkPalette, findAccent,
  findBackdrop, lightPalette
} from './Theme';
import { Log } from './Log';
import { CoreApi } from './Core';
import { AppLock } from './AppLock';

/** Bump when the privacy policy or user agreement changes: everyone is asked to consent again. */
export const PRIVACY_VERSION: number = 3;

export class SectionDef {
  key: string;
  /** Chinese source; render with t() */
  title: string;
  short: string;
  icon: Resource;

  constructor(key: string, title: string, short: string, icon: Resource) {
    this.key = key;
    this.title = title;
    this.short = short;
    this.icon = icon;
  }
}

export const SECTIONS: SectionDef[] = [
  new SectionDef('store', 'Sub-Store', 'Sub-Store', $r('sys.symbol.rectangle_stack')),
  new SectionDef('server', '服务', '服务', $r('sys.symbol.dot_radiowaves_left_and_right')),
  new SectionDef('settings', '设置', '设置', $r('sys.symbol.gearshape'))
];

/** Sub-Store (the bundled web UI) is the landing tab */
export const PHONE_TABS: string[] = ['store', 'server', 'settings'];

export function sectionOf(key: string): SectionDef {
  for (const s of SECTIONS) {
    if (s.key === key) {
      return s;
    }
  }
  return SECTIONS[0];
}

export type Breakpoint = 'sm' | 'md' | 'lg';

export const BAR_H: number = 52;
export const BAR_PILL_H: number = 46;
export const BAR_TAB_W: number = 72;
export const BAR_GAP: number = 8;

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
  /** '' = core OK, 'missing' = libmimisubstore.so not in the HAP, else the wrong version found */
  @Trace coreProblem: string = '';
  @Trace themeMode: string = 'system';
  @Trace accentKey: string = 'red';
  @Trace langPref: string = 'system';
  @Trace bgKey: string = 'none';
  @Trace bgImage: string = '';
  @Trace glass: boolean = false;
  @Trace glassLevel: number = 1;
  @Trace glow: boolean = false;
  /** server settings */
  @Trace port: number = DEFAULT_PORT;
  @Trace autoStart: boolean = true;
  /** listen on every interface (LAN) or 127.0.0.1 only */
  @Trace lanAccess: boolean = false;
  /** LAN mode: also serve the Sub-Store web UI + API to other devices (off = only /download and /share) */
  @Trace lanUI: boolean = false;
  /** keep serving in the background (continuous task) */
  @Trace background: boolean = true;
  @Trace guideSeen: boolean = false;
  foreground: boolean = true;

  @Trace systemDark: boolean = false;
  @Trace bp: Breakpoint = 'sm';
  @Trace safeTop: number = 0;
  @Trace safeBottom: number = 0;
  @Trace section: string = 'store';
  @Trace barCollapsed: boolean = false;
  /** bumped on language change so every view rebuilds */
  @Trace epoch: number = 0;

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
    this.themeMode = p.str('theme', 'system');
    this.accentKey = p.str('accent', 'red');
    this.langPref = p.str('lang', 'system');
    LangState.get().lang = resolveLang(this.langPref);
    this.bgKey = p.str('bg', 'none');
    this.bgImage = p.str('bgImage', '');
    if (this.bgKey === 'image' && this.bgImage.length === 0) {
      this.bgKey = 'none';
    }
    this.glass = p.bool('glass', false);
    this.glassLevel = p.num('glassLevel', 1);
    this.glow = p.bool('glow', false);
    this.port = p.num('port', DEFAULT_PORT);
    this.autoStart = p.bool('autoStart', true);
    this.lanAccess = p.bool('lanAccess', false);
    this.lanUI = p.bool('lanUI', false);
    this.background = p.bool('background', true);
    this.guideSeen = p.bool('guideSeen', false);
    AppLock.get().init(p, ctx.filesDir);
    this.applyColorMode();
    const cv = CoreApi.version();
    this.coreProblem = cv.length === 0 ? 'missing' : (cv === CORE_VERSION ? '' : cv);
    Log.i('Store', 'init: core ' + cv);
  }

  acceptPrivacy(): void {
    this.consented = true;
    this.prefs?.put('consent', PRIVACY_VERSION);
    AppLock.get().afterConsent();
  }

  /** Withdraw consent: forget it and quit; next launch asks again. */
  revokePrivacy(): void {
    this.prefs?.put('consent', 0);
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

  // ------------------------------------------------------------------ settings

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
    } else if (key === 'guideSeen') {
      this.guideSeen = v as boolean;
    }
    this.prefs?.put(key, v);
  }

  pref(): Prefs | null {
    return this.prefs;
  }

  // ------------------------------------------------------------------ appearance, window, dialogs


  /**
   * 当前是否应使用深色主题。
   * @returns themeMode 为 'dark'/'light' 时按用户选择；'system' 时跟随系统
   */
  isDark(): boolean {
    if (this.themeMode === 'dark') {
      return true;
    }
    if (this.themeMode === 'light') {
      return false;
    }
    return this.systemDark;
  }

  /**
   * 计算当前生效的调色板：明暗基础色 -> 叠加强调色 -> 根据背景/毛玻璃调整透明度。
   * @returns 新的 Palette 实例（每次调用都会新建，调用方可放心修改）
   */
  palette(): Palette {
    const p = this.isDark() ? darkPalette() : lightPalette();
    applyAccent(p, this.accent());
    return applyBackdrop(p, this.hasBackdrop(), this.glass);
  }

  /** A picture or gradient is drawn behind the pages (cards turn translucent) */
  /**
   * 中文说明：是否在页面后绘制了背景（图片、渐变或光晕效果），为 true 时卡片和栏位变为半透明。
   */
  hasBackdrop(): boolean {
    return this.bgKey !== 'none' || this.glow;
  }

  /**
   * 当前渐变背景定义。
   * @returns 渐变背景；无背景或使用自定义图片时返回 null
   */
  backdrop(): BackdropDef | null {
    return this.bgKey === 'none' || this.bgKey === 'image' ? null : findBackdrop(this.bgKey);
  }

  /** 全部可选渐变背景 */
  backdrops(): BackdropDef[] {
    return BACKDROPS;
  }

  /**
   * Frosted glass blur radius (vp) for bars and cards; 0 when off. A plain backdropBlur is used instead of a
   * BlurStyle material: the system materials add their own opaque tint, which under our translucent card colour
   * left the effect invisible.
   */
  /**
   * 中文说明：毛玻璃模糊半径（vp），供 blurPx() 换算后给 .backdropBlur() 使用；关闭毛玻璃时返回 0。
   * 强度：glassLevel 0 -> 16，1 -> 32，2 -> 56。
   * 为什么用 backdropBlur 而不是 backgroundBlurStyle(BlurStyle)：系统的模糊材质会自带一层不透明的着色，
   * 叠在我们已经调成半透明的卡片颜色下面后，背景几乎被完全遮住，毛玻璃效果看不出来；
   * backdropBlur 只对背后内容做纯模糊、不额外着色，透明度完全由 Theme.applyBackdrop() 控制。
   * 注意：backdropBlur 的参数单位是 px，调用处请使用 blurPx()。
   */
  blurRadius(): number {
    if (!this.glass) {
      return 0;
    }
    return this.glassLevel <= 0 ? 16 : this.glassLevel === 1 ? 32 : 56;
  }
  /**
   * 毛玻璃模糊半径换算成 px，直接传给 .backdropBlur()。
   * 用 UIContext.vp2px（全局 vp2px 已弃用）；窗口还没就绪时按 3 倍密度估算（此时界面也还没显示）。
   */
  blurPx(): number {
    const r = this.blurRadius();
    if (r === 0) {
      return 0;
    }
    return this.uiCtx !== null ? this.uiCtx.vp2px(r) : r * 3;
  }


  /** Blur material for bars and cards when frosted glass is on */
  /**
   * 中文说明：毛玻璃对应的系统模糊材质（按强度选择 ULTRA_THIN/THIN/REGULAR）；关闭时为 NONE。
   * 注意：当前栏位和卡片实际使用 blurRadius() + backdropBlur，原因见 blurRadius() 注释。
   */
  blurStyle(): BlurStyle {
    if (!this.glass) {
      return BlurStyle.NONE;
    }
    return this.glassLevel <= 0 ? BlurStyle.COMPONENT_ULTRA_THIN :
      this.glassLevel === 1 ? BlurStyle.COMPONENT_THIN : BlurStyle.COMPONENT_REGULAR;
  }

  /** Background of the floating tab bar and the rail */
  /**
   * 中文说明：浮动标签栏和侧边栏的背景色（已按背景/毛玻璃设置调整透明度）。
   */
  barColor(): string {
    const p = this.palette();
    return p.bar;
  }

  /**
   * 设置背景并持久化。
   * @param key 'none' | 渐变背景键 | 'image'
   */
  setBackdrop(key: string): void {
    this.bgKey = key;
    this.prefs?.put('bg', key);
  }

  /**
   * 设置自定义背景图片并切换为图片背景。
   * @param path 已复制到应用沙箱的图片绝对路径（系统选择器的临时 URI 不能长期使用）
   */
  setBackdropImage(path: string): void {
    this.bgImage = path;
    this.prefs?.put('bgImage', path);
    this.setBackdrop('image');
  }

  /**
   * 开关毛玻璃效果并持久化。
   * @param on 是否开启
   */
  setGlass(on: boolean): void {
    this.glass = on;
    this.prefs?.put('glass', on);
  }

  /**
   * 设置毛玻璃强度并持久化。
   * @param level 0 轻、1 中、2 强
   */
  setGlassLevel(level: number): void {
    this.glassLevel = level;
    this.prefs?.put('glassLevel', level);
  }

  /**
   * 开关沉浸光效（内容后方的强调色光晕）并持久化。
   * @param on 是否开启
   */
  setGlow(on: boolean): void {
    this.glow = on;
    this.prefs?.put('glow', on);
  }

  /** Changes the UI language; views are re-created so cached texts follow */
  /**
   * 中文说明：切换界面语言并持久化。
   * @param pref 'system' | 'zh' | 'en'
   * 注意：实际语言变化时 epoch 自增，让以 epoch 为键的页面重建，使缓存在 build 之外的文案也更新。
   */
  setLang(pref: string): void {
    this.langPref = pref;
    this.prefs?.put('lang', pref);
    const lang = resolveLang(pref);
    if (lang !== LangState.get().lang) {
      LangState.get().lang = lang;
      this.epoch++;
    }
  }

  /** System language changed while the app runs */
  /**
   * 中文说明：系统语言变化时调用；只有用户选择“跟随系统”时才重新解析语言。
   */
  onSystemLanguage(): void {
    if (this.langPref === 'system') {
      this.setLang('system');
    }
  }

  // ---------------- floating tab bar ----------------

  // 上一次拖动的参考位置，用于计算手指移动方向与距离
  private dragLast: number = 0;

  /** Vertical drag on the content (phone): finger up folds the tab bar, finger down restores it */
  /**
   * 中文说明：处理内容区域的竖向拖动（仅手机断点）：手指上滑超过 24vp 折叠标签栏，下滑超过 24vp 展开。
   * @param offsetY 拖动手势的累计竖向偏移
   * @param start 是否为手势开始
   * 注意：在“继续朝同一方向移动”时不更新参考点，以便累计距离；方向反转时才把参考点移到当前位置，
   *       这样小幅抖动不会让标签栏反复折叠展开。
   */
  onContentDrag(offsetY: number, start: boolean): void {
    if (this.bp !== 'sm') {
      return;
    }
    if (start) {
      this.dragLast = offsetY;
      return;
    }
    const d = offsetY - this.dragLast;
    if (d < -24 && !this.barCollapsed) {
      this.setBarCollapsed(true);
      this.dragLast = offsetY;
    } else if (d > 24 && this.barCollapsed) {
      this.setBarCollapsed(false);
      this.dragLast = offsetY;
    } else if ((d < 0 && !this.barCollapsed) || (d > 0 && this.barCollapsed)) {
      // keep measuring from the turning point
    } else {
      this.dragLast = offsetY;
    }
  }

  /**
   * 设置标签栏折叠状态（有 UI 上下文时带 280ms 动画）。
   * @param v true 折叠为圆形按钮，false 展开
   */
  setBarCollapsed(v: boolean): void {
    if (v === this.barCollapsed) {
      return;
    }
    const ui = this.uiCtx;
    if (ui !== null) {
      ui.animateTo({ duration: 280, curve: Curve.FastOutSlowIn }, () => {
        this.barCollapsed = v;
      });
    } else {
      this.barCollapsed = v;
    }
  }

  /** 当前强调色定义 */
  accent(): AccentDef {
    return findAccent(this.accentKey);
  }

  /** 全部可选强调色 */
  accents(): AccentDef[] {
    return ACCENTS;
  }

  /**
   * 设置主题模式并持久化，同时让系统组件跟随。
   * @param mode 'system' | 'light' | 'dark'
   */
  setThemeMode(mode: string): void {
    this.themeMode = mode;
    this.prefs?.put('theme', mode);
    this.applyColorMode();
  }

  /**
   * 设置强调色并持久化。
   * @param key 强调色键
   */
  setAccent(key: string): void {
    this.accentKey = key;
    this.prefs?.put('accent', key);
  }

  /** Lets system components (dialogs, pickers, toasts) follow the in-app theme */
  /**
   * 中文说明：把应用内主题同步到应用级颜色模式，使系统弹窗、选择器、toast 也使用相同的深浅色；
   * 'system' 对应 COLOR_MODE_NOT_SET（交还给系统决定）。随后刷新状态栏图标颜色。
   */
  applyColorMode(): void {
    const ctx = this.ctx;
    if (ctx !== null) {
      try {
        const mode = this.themeMode === 'dark' ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK :
          this.themeMode === 'light' ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT :
          ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
        ctx.getApplicationContext().setColorMode(mode);
      } catch (e) {
        Log.w('Store', 'setColorMode failed');
      }
    }
    this.applySystemBar();
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

  /**
   * 根据窗口宽度更新断点。
   * @param vpWidth 窗口宽度（vp）
   * 注意：从平板切到手机时，若当前分区不在底部栏中则切到“更多”；反之从手机切到平板时“更多”不存在，改为订阅分区。
   */
  setWidth(vpWidth: number): void {
    const bp: Breakpoint = vpWidth >= 840 ? 'lg' : vpWidth >= 600 ? 'md' : 'sm';
    if (bp !== this.bp) {
      this.bp = bp;
      // Phone bar has no slot for the extra sections: fall back to the "more" list
    }
  }

  /** 是否为宽屏（md 或 lg，使用侧边栏布局） */
  isWide(): boolean {
    return this.bp !== 'sm';
  }

  /**
   * Bottom padding for scrolling content. Phones show the tab bar below the content (it already covers the
   * gesture area); tablets and pushed pages extend to the screen edge and must clear the gesture indicator.
   */
  /**
   * 中文说明：滚动内容的底部内边距（vp）。
   * @param asPage 是否为推入的独立页面
   * @returns 手机主分区需要让出浮动标签栏的高度；平板与独立页面只需让出手势指示条
   */
  bottomPad(asPage: boolean): number {
    return (asPage || this.isWide()) ? this.safeBottom + 20 : this.safeBottom + BAR_H + BAR_GAP + 16;
  }

  /** Columns for card lists */
  /** 卡片列表的列数：lg 断点双列，其余单列 */
  lanes(): number {
    return this.bp === 'lg' ? 2 : 1;
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

