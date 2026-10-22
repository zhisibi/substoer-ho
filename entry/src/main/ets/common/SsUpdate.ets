/**
 * SsUpdate.ets — in-app update of the Sub-Store backend and web UI (not the app itself).
 *
 * The repo's GitHub Actions workflow follows upstream Sub-Store releases, builds the backend with this app's
 * patches, smoke-tests it and publishes a manifest (see core/ssc/update.go). The core downloads the files,
 * checks their SHA-256, test-starts a new backend in a scratch folder and keeps the built-in copies as fallback.
 */
import { t, tf } from './I18n';
import { CoreApi, req } from './Core';
import { JObj, asObj, jBool, jStr } from './Json';
import { Store } from './Store';
import { Server } from './Server';
import { WebHolder } from '../views/StoreView';
import { versionName } from './AppInfo';

/** 下载线路: 0 自动 (GitHub first, then mirrors), 1 GitHub only, 2 mirrors first */
export const LINES: string[] = ['自动', '直连 GitHub', '加速镜像优先'];
const MIRRORS: string[] = ['https://ghfast.top', 'https://gh-proxy.com'];

@ObservedV2
export class SsUpdate {
  private static inst: SsUpdate | null = null;

  static get(): SsUpdate {
    if (SsUpdate.inst === null) {
      SsUpdate.inst = new SsUpdate();
    }
    return SsUpdate.inst;
  }

  @Trace busy: boolean = false;
  @Trace checked: boolean = false;
  @Trace backend: string = '';
  @Trace frontend: string = '';
  @Trace builtinBackend: string = '';
  @Trace builtinFrontend: string = '';
  @Trace backendUpdated: boolean = false;
  @Trace frontendUpdated: boolean = false;
  @Trace latestBackend: string = '';
  @Trace latestFrontend: string = '';
  @Trace backendNew: boolean = false;
  @Trace frontendNew: boolean = false;
  @Trace compatible: boolean = true;
  @Trace reason: string = '';
  @Trace error: string = '';
  @Trace built: string = '';

  line(): number {
    const v = Number(Store.get().prefStr('ssUpdLine', '0'));
    return isNaN(v) ? 0 : v;
  }

  setLine(i: number): void {
    Store.get().setPref('ssUpdLine', String(i));
  }

  autoCheck(): boolean {
    return Store.get().prefBool('ssUpdAuto', true);
  }

  setAutoCheck(on: boolean): void {
    Store.get().setPref('ssUpdAuto', on);
  }

  mirrors(): string[] {
    switch (this.line()) {
      case 1:
        return [''];
      case 2:
        return [MIRRORS[0], MIRRORS[1], ''];
      default:
        return ['', MIRRORS[0], MIRRORS[1]];
    }
  }

  private apply(o: JObj): void {
    this.backend = jStr(o, 'backend');
    this.frontend = jStr(o, 'frontend');
    this.builtinBackend = jStr(o, 'builtinBackend');
    this.builtinFrontend = jStr(o, 'builtinFrontend');
    this.backendUpdated = jBool(o, 'backendUpdated', false);
    this.frontendUpdated = jBool(o, 'frontendUpdated', false);
    const m = asObj(o['manifest']);
    if (m !== undefined) {
      this.checked = true;
      this.built = jStr(m, 'built');
      const b = asObj(m['backend']);
      const f = asObj(m['frontend']);
      this.latestBackend = b !== undefined ? jStr(b, 'version') : '';
      this.latestFrontend = f !== undefined ? jStr(f, 'version') : '';
      this.backendNew = jBool(o, 'backendNew', false);
      this.frontendNew = jBool(o, 'frontendNew', false);
      this.compatible = jBool(o, 'compatible', true);
      this.reason = jStr(o, 'reason');
    }
  }

  private base(op: string): JObj {
    const q = req(op);
    q['dir'] = Server.get().dataDir();
    return q;
  }

  /** Installed / built-in versions (no network). */
  refreshLocal(): void {
    this.apply(CoreApi.call(this.base('updInfo')));
  }

  hasNew(): boolean {
    return this.checked && (this.frontendNew || (this.backendNew && this.compatible));
  }

  async check(quiet: boolean): Promise<boolean> {
    if (this.busy) {
      return false;
    }
    this.busy = true;
    this.error = '';
    try {
      const q = this.base('updCheck');
      q['mirrors'] = this.mirrors();
      const o = await CoreApi.callAsync(q);
      const err = jStr(o, 'error');
      if (err.length > 0) {
        this.error = err;
        if (!quiet) {
          Store.get().toast(tf('检查失败：{0}', err));
        }
        return false;
      }
      this.apply(o);
      Store.get().setPref('ssUpdLast', String(Date.now()));
      if (!quiet && !this.hasNew()) {
        Store.get().toast(t('Sub-Store 已是最新'));
      }
      return true;
    } finally {
      this.busy = false;
    }
  }

  /** Downloads + installs what is newer, then restarts the service and reloads the web UI. */
  async install(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.error = '';
    let ok = false;
    try {
      const q = this.base('updInstall');
      q['mirrors'] = this.mirrors();
      const o = await CoreApi.callAsync(q);
      const err = jStr(o, 'error');
      if (err.length > 0) {
        this.error = err;
        Store.get().toast(tf('更新失败：{0}', err));
        return;
      }
      this.apply(o);
      ok = true;
    } finally {
      this.busy = false;
    }
    if (ok) {
      await this.reloadService();
      Store.get().toast(tf('已更新到 后端 {0} · 前端 {1}', this.backend, this.frontend));
    }
  }

  async rollback(): Promise<void> {
    const store = Store.get();
    if (!await store.confirm(t('恢复内置版本'), tf('删除下载的更新，改回安装包内置的 后端 {0} · 前端 {1}？你的订阅和设置不受影响。',
      this.builtinBackend, this.builtinFrontend), t('恢复'), true)) {
      return;
    }
    this.apply(CoreApi.call(this.base('updRollback')));
    await this.reloadService();
    store.toast(t('已恢复内置版本'));
  }

  private async reloadService(): Promise<void> {
    const srv = Server.get();
    await srv.restartIfRunning();
    srv.poll();
    if (srv.running) {
      WebHolder.reload(srv.webUrl());
    }
  }

  /** Startup: at most once a day, quietly; a toast when something new is available. */
  async startupCheck(): Promise<void> {
    if (!this.autoCheck() || !Store.get().consented) {
      return;
    }
    const last = Number(Store.get().prefStr('ssUpdLast', '0'));
    if (!isNaN(last) && Date.now() - last < 20 * 3600 * 1000) {
      return;
    }
    if (await this.check(true) && this.hasNew()) {
      Store.get().toast(tf('Sub-Store 有新版本：后端 {0} · 前端 {1}，可在 服务管理 → Sub-Store 更新 安装',
        this.latestBackend, this.latestFrontend));
    }
  }

  @Trace appChecking: boolean = false;

  /** 关于 › 检查更新: the newest v* release of this app on GitHub; offers to open its page. */
  async checkApp(): Promise<void> {
    if (this.appChecking) {
      return;
    }
    const store = Store.get();
    this.appChecking = true;
    let o: JObj = {};
    try {
      const q = req('appRelease');
      q['mirrors'] = this.mirrors();
      o = await CoreApi.callAsync(q);
    } finally {
      this.appChecking = false;
    }
    const err = jStr(o, 'error');
    if (err.length > 0) {
      store.toast(tf('检查失败：{0}', err));
      return;
    }
    const v = jStr(o, 'version');
    if (v.length === 0) {
      store.toast(t('还没有发布版本'));
      return;
    }
    if (!verNewer(v, versionName())) {
      store.toast(tf('已是最新版本（{0}）', versionName()));
      return;
    }
    let notes = jStr(o, 'notes').trim();
    if (notes.length > 600) {
      notes = notes.substring(0, 600) + '…';
    }
    const ok = await store.confirm(tf('发现新版本 {0}', v), (notes.length > 0 ? notes + '\n\n' : '') +
      tf('当前版本 {0}。前往 GitHub Release 下载安装包。', versionName()), t('前往下载'), false);
    const url = jStr(o, 'url');
    if (ok && url.length > 0) {
      store.ctx?.openLink(url, { appLinkingOnly: false });
    }
  }
}

/** a > b for dotted numeric versions */
export function verNewer(a: string, b: string): boolean {
  const pa = a.replace(/^v/, '').split('.');
  const pb = b.replace(/^v/, '').split('.');
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const x = i < pa.length ? parseInt(pa[i], 10) : 0;
    const y = i < pb.length ? parseInt(pb[i], 10) : 0;
    const xa = isNaN(x) ? 0 : x;
    const ya = isNaN(y) ? 0 : y;
    if (xa !== ya) {
      return xa > ya;
    }
  }
  return false;
}
