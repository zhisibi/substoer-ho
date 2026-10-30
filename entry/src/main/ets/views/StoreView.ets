/**
 * StoreView: the Sub-Store web UI (upstream Sub-Store-Front-End, bundled in the core) served by the local server at
 * http://127.0.0.1:<port>/ and shown in ArkWeb, with ?api= pointing it at the embedded backend.
 *  - links that leave 127.0.0.1 (docs, GitHub, clash:// / sing-box:// one-tap imports) open in the system;
 *  - file inputs (restore a backup, import a file) use the system picker; downloads (backups, exported configs) are
 *    saved with the system save dialog;
 *  - navigator.clipboard is bridged to the system pasteboard (ArkWeb has no permission UI for it);
 *  - while the server is stopped a placeholder with a start button is shown instead.
 */
import { webview } from '@kit.ArkWeb';
import { t, tf } from '../common/I18n';
import { Store } from '../common/Store';
import { Server } from '../common/Server';
import { FileUtil } from '../common/FileUtil';
import { Log } from '../common/Log';
import { ActionButton } from '../components/Widgets';

export class WebHolder {
  static controller: webview.WebviewController = new webview.WebviewController();
  static attached: boolean = false;
  static delegate: webview.WebDownloadDelegate = new webview.WebDownloadDelegate();
  static delegateBound: boolean = false;

  /** Back inside the web UI; false when there is no history (the page handles the back press itself then). */
  static back(): boolean {
    try {
      if (WebHolder.attached && WebHolder.controller.accessBackward()) {
        WebHolder.controller.backward();
        return true;
      }
    } catch (e) {
    }
    return false;
  }

  static reload(url: string): void {
    if (!WebHolder.attached) {
      return;
    }
    try {
      WebHolder.controller.loadUrl(url);
    } catch (e) {
      Log.w('Web', 'loadUrl failed');
    }
  }

  /** (Re)apply the 沉浸光感 style to the web tab bar from the current settings; safe to call any time. */
  static applyGlass(): void {
    if (!WebHolder.attached) {
      return;
    }
    const st = Store.get();
    try {
      WebHolder.controller.runJavaScript(glassScript(st.navLight, st.isDark()));
    } catch (e) {
      Log.w('Web', 'glass apply failed');
    }
  }
}

/**
 * 导航栏沉浸光感 for the web UI: the bottom tab bar (.nut-tabbar inside .tab-bar-wrapper) belongs to the
 * web front-end, so the native glass material cannot reach it — when the setting is on, a style sheet is
 * injected that restyles the bar as a floating glass capsule in the MimiSSH manner: strong backdrop blur
 * and saturation, a tint gradient, a diagonal specular sheen (::before), and the two-layer light rim
 * (bright top edge + soft inner glow) that LightSense.GlassRimMod draws natively.
 */
function glassScript(on: boolean, dark: boolean): string {
  const tint = dark ? 'linear-gradient(180deg,rgba(64,70,82,0.42),rgba(24,26,32,0.50))' :
    'linear-gradient(180deg,rgba(255,255,255,0.50),rgba(255,255,255,0.28))';
  const rim = dark ? 'rgba(255,255,255,0.22)' : 'rgba(255,255,255,0.70)';
  const rimSoft = dark ? 'rgba(255,255,255,0.10)' : 'rgba(255,255,255,0.35)';
  const sheen = dark ? 'rgba(255,255,255,0.13)' : 'rgba(255,255,255,0.38)';
  const shadow = dark ? '0 14px 34px rgba(0,0,0,0.42)' : '0 14px 34px rgba(15,23,42,0.16)';
  const css = on ?
    '.tab-bar-wrapper{background:transparent!important}' +
    '.nut-tabbar{position:fixed!important;left:14px!important;right:14px!important;width:auto!important;' +
    'bottom:calc(env(safe-area-inset-bottom, 0px) + 10px)!important;border-radius:30px!important;overflow:hidden!important;' +
    'background:' + tint + '!important;' +
    '-webkit-backdrop-filter:blur(30px) saturate(200%) brightness(1.05);' +
    'backdrop-filter:blur(30px) saturate(200%) brightness(1.05);' +
    'border:1px solid ' + rimSoft + '!important;' +
    'box-shadow:inset 0 1px 1px ' + rim + ',inset 0 -1px 1px ' + rimSoft + ',' +
    'inset 1px 0 1px ' + rimSoft + ',inset -1px 0 1px ' + rimSoft + ',' + shadow + '!important}' +
    '.nut-tabbar::before{content:"";position:absolute;left:0;top:0;right:0;bottom:0;pointer-events:none;' +
    'background:linear-gradient(115deg,' + sheen + ' 0%,rgba(255,255,255,0) 42%)}' +
    '.nut-tabbar-item,.nut-tabbar-item_icon-box{position:relative;z-index:1}' : '';
  return '(function(){try{' +
    'var old=document.getElementById("mss-glass");' +
    (on ? 'var css=' + JSON.stringify(css) + ';' +
      'if(!old){old=document.createElement("style");old.id="mss-glass";(document.head||document.documentElement).appendChild(old);}' +
      'if(old.textContent!==css){old.textContent=css;}'
      : 'if(old){old.remove();}') +
    '}catch(e){}})();';
}

/** Host object exposed to the page as window.SubStoreHost (clipboard bridge). */
class HostBridge {
  copy(text: string): boolean {
    try {
      FileUtil.copyText(text);
      return true;
    } catch (e) {
      return false;
    }
  }
}

const CLIPBOARD_JS: string = `
(function(){
  try {
    var host = window.SubStoreHost;
    if (!host) return;
    var write = function(t){ return host.copy(String(t)) ? Promise.resolve() : Promise.reject(new Error('copy failed')); };
    if (!navigator.clipboard) { Object.defineProperty(navigator, 'clipboard', { value: {}, configurable: true }); }
    try { navigator.clipboard.writeText = write; } catch (e) {
      Object.defineProperty(navigator, 'clipboard', { value: { writeText: write }, configurable: true });
    }
    var origExec = document.execCommand ? document.execCommand.bind(document) : null;
    document.execCommand = function(cmd){
      if (String(cmd).toLowerCase() === 'copy') {
        var sel = window.getSelection ? String(window.getSelection()) : '';
        var el = document.activeElement;
        if (!sel && el && (el.tagName === 'TEXTAREA' || el.tagName === 'INPUT')) {
          sel = el.value.substring(el.selectionStart || 0, el.selectionEnd || el.value.length);
        }
        return host.copy(sel);
      }
      return origExec ? origExec.apply(document, arguments) : false;
    };
  } catch (e) {}
})();
`;

/**
 * Only this app's own service origin may load inside the WebView (plus about:/blob: internals).
 * data:/javascript: are NOT local: they used to be let through here and could run script in the
 * WebView with the clipboard bridge attached. Any other 127.0.0.1 port belongs to another app and
 * is treated as external.
 */
function isLocalUrl(url: string): boolean {
  const l = url.toLowerCase();
  if (l.startsWith('about:') || l.startsWith('blob:')) {
    return true;
  }
  const port = Store.get().port;
  const origins: string[] = ['http://127.0.0.1:' + port, 'http://localhost:' + port];
  for (const o of origins) {
    if (l === o || l.startsWith(o + '/') || l.startsWith(o + '?') || l.startsWith(o + '#')) {
      return true;
    }
  }
  return false;
}

function isBlockedScheme(url: string): boolean {
  const l = url.toLowerCase();
  return l.startsWith('data:') || l.startsWith('javascript:') || l.startsWith('file:');
}

@ComponentV2
export struct StoreView {
  private store: Store = Store.get();
  @Local srv: Server = Server.get();
  private bridge: HostBridge = new HostBridge();
  @Local loading: boolean = true;
  @Local failed: string = '';
  private loadedEpoch: number = -1;

  aboutToAppear(): void {
    this.bindDownloads();
  }

  @Monitor('srv.startEpoch')
  onStarted(): void {
    if (this.srv.startEpoch !== this.loadedEpoch && WebHolder.attached) {
      this.loadedEpoch = this.srv.startEpoch;
      this.failed = '';
      WebHolder.reload(this.srv.webUrl());
    }
  }

  private bindDownloads(): void {
    if (WebHolder.delegateBound) {
      return;
    }
    WebHolder.delegateBound = true;
    const d = WebHolder.delegate;
    d.onBeforeDownload((item: webview.WebDownloadItem): void => {
      const ctx = Store.get().ctx;
      if (ctx === null) {
        item.cancel();
        return;
      }
      let name = item.getSuggestedFileName();
      if (name.length === 0) {
        const p = item.getUrl().split('?')[0];
        name = p.substring(p.lastIndexOf('/') + 1);
      }
      name = FileUtil.sanitizeFileName(name, 'sub-store-' + Date.now());
      const dir = ctx.cacheDir + '/downloads';
      FileUtil.ensureDir(dir);
      const path = dir + '/' + name;
      FileUtil.remove(path);
      item.start(path);
    });
    d.onDownloadFinish((item: webview.WebDownloadItem): void => {
      const st = Store.get();
      const ctx = st.ctx;
      if (ctx === null || item.getState() === webview.WebDownloadState.CANCELED) {
        return;
      }
      const path = item.getFullPath();
      const name = path.substring(path.lastIndexOf('/') + 1);
      FileUtil.exportFile(ctx, path, name).then((ok: boolean): void => {
        if (ok) {
          st.toast(tf('已保存：{0}', name));
        }
        FileUtil.remove(path);
      }).catch((e: Error): void => {
        st.toast(tf('保存失败：{0}', e.message ?? ''));
      });
    });
    d.onDownloadFailed((item: webview.WebDownloadItem): void => {
      Store.get().toast(t('下载失败'));
    });
  }

  private openExternal(url: string): void {
    const ctx = this.store.ctx;
    if (ctx === null) {
      return;
    }
    ctx.openLink(url, { appLinkingOnly: false }).catch((): void => {
      this.store.toast(t('没有可以打开此链接的应用'));
    });
  }

  @Builder
  placeholder() {
    Column({ space: 16 }) {
      Image($r('app.media.startIcon')).width(84).height(84).borderRadius(22)
      if (this.srv.busy) {
        LoadingProgress().width(36).height(36).color(this.store.palette().accentUi)
        Text(t('正在启动 Sub-Store 后端…')).fontSize(15).fontColor(this.store.palette().subtle)
      } else {
        Text(t('Sub-Store 服务未运行')).fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.store.palette().text)
        if (this.srv.error.length > 0) {
          Text(this.srv.error).fontSize(13).fontColor(this.store.palette().bad).textAlign(TextAlign.Center)
            .maxLines(4).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        ActionButton({
          text: t('启动服务'), onTap: () => {
            this.srv.start();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .padding(32)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Stack() {
      Web({ src: this.srv.running ? this.srv.webUrl() : 'about:blank', controller: WebHolder.controller })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .mixedMode(MixedMode.None)
        .fileAccess(false)
        .geolocationAccess(false)
        .zoomAccess(false)
        .overScrollMode(OverScrollMode.NEVER)
        .darkMode(this.store.isDark() ? WebDarkMode.On : WebDarkMode.Off)
        .forceDarkAccess(false)
        .backgroundColor(this.store.isDark() ? '#121212' : '#F4F4F4')
        .javaScriptProxy({
          object: this.bridge,
          name: 'SubStoreHost',
          methodList: ['copy'],
          controller: WebHolder.controller
        })
        .javaScriptOnDocumentStart([{ script: CLIPBOARD_JS, scriptRules: ['*'] }])
        .onControllerAttached(() => {
          WebHolder.attached = true;
          try {
            WebHolder.controller.setDownloadDelegate(WebHolder.delegate);
          } catch (e) {
            Log.w('Web', 'download delegate failed');
          }
          this.loadedEpoch = this.srv.startEpoch;
          if (this.srv.running) {
            WebHolder.reload(this.srv.webUrl());
          }
        })
        .onPageBegin(() => {
          this.loading = true;
        })
        .onPageEnd(() => {
          this.loading = false;
          WebHolder.applyGlass();
        })
        .onErrorReceive((e: OnErrorReceiveEvent) => {
          if (e.request.isMainFrame()) {
            this.failed = e.error.getErrorInfo();
            this.loading = false;
          }
        })
        .onLoadIntercept((e: OnLoadInterceptEvent) => {
          const url = e.data.getRequestUrl();
          if (isLocalUrl(url)) {
            return false;
          }
          if (isBlockedScheme(url)) {
            return true; // dropped, not handed to any other app either
          }
          this.openExternal(url);
          return true;
        })
        .onShowFileSelector((e: OnShowFileSelectorEvent) => {
          const ctx = this.store.ctx;
          if (ctx === null) {
            return false;
          }
          // the web engine reads sandbox paths reliably; copy the picked document into cache first
          FileUtil.pickUris(ctx, 1).then(async (uris: string[]): Promise<void> => {
            const out: string[] = [];
            const dir = ctx.cacheDir + '/uploads';
            FileUtil.ensureDir(dir);
            for (const u of uris) {
              const dest = dir + '/' + FileUtil.nameFromUri(u);
              FileUtil.remove(dest);
              await FileUtil.copyUriToAsync(u, dest);
              out.push(dest);
            }
            e.result.handleFileList(out);
          }).catch((): void => {
            e.result.handleFileList([]);
          });
          return true;
        })
        .onRenderExited(() => {
          if (this.srv.running) {
            setTimeout((): void => WebHolder.reload(this.srv.webUrl()), 300);
          }
        })
        .width('100%')
        .height('100%')
        .visibility(this.srv.running ? Visibility.Visible : Visibility.Hidden)

      if (!this.srv.running) {
        this.placeholder()
      } else if (this.failed.length > 0) {
        Column({ space: 12 }) {
          Text(t('页面加载失败')).fontSize(17).fontColor(this.store.palette().text)
          Text(this.failed).fontSize(13).fontColor(this.store.palette().subtle)
          ActionButton({
            text: t('重新加载'), onTap: () => {
              this.failed = '';
              WebHolder.reload(this.srv.webUrl());
            }
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.store.isDark() ? '#121212' : '#F4F4F4')
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.store.safeTop, bottom: this.store.safeBottom })
    .backgroundColor(this.store.isDark() ? '#121212' : '#F4F4F4')
  }
}
