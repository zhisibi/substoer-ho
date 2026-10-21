/**
 * Server.ets — the local Sub-Store server (runs inside libmimisubstore.so: Go net/http + the Sub-Store backend
 * running in an embedded JS engine, + the bundled Sub-Store web UI).
 *
 *  - start / stop with the port and LAN (0.0.0.0) or local-only (127.0.0.1) binding; started on every launch because
 *    the Sub-Store tab is served by it. Other devices only reach /download and /share unless lanUI is on;
 *  - LAN IPv4 addresses from @kit.NetworkKit (core net.Interfaces as a fallback);
 *  - run log (运行日志): server events (start / stop / bind errors, background task) and access lines, polled from the
 *    core every 1.5 s while the app is in the foreground, oldest first;
 *  - optional continuous task (backgroundTaskManager, DATA_TRANSFER) so the server keeps answering in the background.
 *    HarmonyOS may still end it (DATA_TRANSFER expects progress updates; the system cancels a task without them
 *    after about 10 minutes) — Settings explains this honestly.
 */
import { connection } from '@kit.NetworkKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent, WantAgent } from '@kit.AbilityKit';
import { t, tf } from './I18n';
import { Store } from './Store';
import { CoreApi, req } from './Core';
import { JObj, asArr, asObj, jBool, jNum, jStr } from './Json';
import { Log } from './Log';
import { LanCandidate, pickLanIps } from './Lan';

export class AccessLine {
  seq: number = 0;
  time: number = 0;
  /** access | event */
  kind: string = 'access';
  /** event: info | warn | error */
  level: string = '';
  msg: string = '';
  ip: string = '';
  method: string = '';
  path: string = '';
  status: number = 0;
  ms: number = 0;
  bytes: number = 0;
  ua: string = '';
}

@ObservedV2
export class Server {
  private static inst: Server | null = null;

  static get(): Server {
    if (Server.inst === null) {
      Server.inst = new Server();
    }
    return Server.inst;
  }

  @Trace running: boolean = false;
  @Trace busy: boolean = false;
  @Trace started: number = 0;
  @Trace requests: number = 0;
  @Trace error: string = '';
  /** backend loaded + time it took */
  @Trace engineOk: boolean = false;
  @Trace initMs: number = 0;
  @Trace backendVer: string = '';
  @Trace frontendVer: string = '';
  /** bumped after each successful start so the web view reloads */
  @Trace startEpoch: number = 0;
  @Trace ips: string[] = [];
  @Trace logs: AccessLine[] = [];
  /** continuous task active */
  @Trace bgActive: boolean = false;
  private seq: number = 0;
  private timer: number = -1;

  init(): void {
    this.refreshIps();
    this.poll();
    this.startPolling();
  }

  /** Adds an app-side event (background task …) to the core's run log. */
  event(level: string, text: string): void {
    const q = req('event');
    q['level'] = level;
    q['text'] = text;
    CoreApi.call(q);
  }

  /**
   * LAN IPv4 addresses of this device (Wi-Fi / Ethernet / hotspot). Addresses on VPN / TUN / cellular links and the
   * proxy fake-ip range 198.18.0.0/15 are dropped (pickLanIps): a proxy app's VPN used to show up as "局域网 198.18.0.1".
   * Sources: NetworkKit (bearer type + interface name) and the core's net.Interfaces (interface name, also sees the
   * hotspot interface that NetworkKit does not list).
   */
  refreshIps(): void {
    const cands: LanCandidate[] = [];
    try {
      const nets = connection.getAllNetsSync();
      for (const n of nets) {
        let kind = '';
        try {
          const caps = connection.getNetCapabilitiesSync(n);
          const bt = caps.bearerTypes ?? [];
          if (bt.indexOf(connection.NetBearType.BEARER_VPN) >= 0) {
            kind = 'vpn';
          } else if (bt.indexOf(connection.NetBearType.BEARER_CELLULAR) >= 0) {
            kind = 'cellular';
          } else if (bt.indexOf(connection.NetBearType.BEARER_WIFI) >= 0) {
            kind = 'wifi';
          } else if (bt.indexOf(connection.NetBearType.BEARER_ETHERNET) >= 0) {
            kind = 'ethernet';
          }
        } catch (e) {
          Log.w('Server', 'net capabilities unavailable');
        }
        try {
          const props = connection.getConnectionPropertiesSync(n);
          for (const la of props.linkAddresses ?? []) {
            const c = new LanCandidate();
            c.ip = la.address.address;
            c.iface = props.interfaceName ?? '';
            c.kind = kind;
            cands.push(c);
          }
        } catch (e) {
          Log.w('Server', 'connection properties unavailable');
        }
      }
    } catch (e) {
      Log.w('Server', 'getAllNets failed');
    }
    const res = CoreApi.call(req('ifaddrs'));
    for (const x of asArr(res['addrs'])) {
      const o = asObj(x);
      if (o !== undefined) {
        const c = new LanCandidate();
        c.ip = jStr(o, 'ip');
        c.iface = jStr(o, 'name');
        cands.push(c);
      }
    }
    this.ips = pickLanIps(cands);
  }

  /** Base URL of the server on this device (the web UI loads from here). */
  localBase(): string {
    return 'http://127.0.0.1:' + Store.get().port;
  }

  /** Web UI URL: ?api= points the Sub-Store front-end at the bundled backend. */
  webUrl(): string {
    const b = this.localBase();
    return b + '/?api=' + encodeURIComponent(b);
  }

  /** Every base URL subscription links can be fetched from: 127.0.0.1 first, then each LAN address. */
  bases(): string[] {
    const store = Store.get();
    const out: string[] = [this.localBase()];
    if (store.lanAccess) {
      for (const ip of this.ips) {
        out.push('http://' + ip + ':' + store.port);
      }
    }
    return out;
  }

  dataDir(): string {
    const ctx = Store.get().ctx;
    return ctx !== null ? ctx.filesDir + '/substore' : '';
  }

  async start(): Promise<boolean> {
    const store = Store.get();
    if (this.busy) {
      return false;
    }
    if (store.coreProblem === 'missing') {
      store.warnCore();
      return false;
    }
    this.busy = true;
    try {
      const lq = req('lanUI');
      lq['on'] = store.lanUI;
      CoreApi.call(lq);
      const q = req('start');
      q['host'] = store.lanAccess ? '0.0.0.0' : '127.0.0.1';
      q['port'] = store.port;
      q['dir'] = this.dataDir();
      // first start loads the Sub-Store backend (~0.3–1 s): off the UI thread
      const res = await CoreApi.callAsync(q);
      const err = jStr(res, 'error');
      if (err.length > 0) {
        this.error = err.indexOf('already in use') >= 0 ? tf('端口 {0} 已被占用，请在设置中换一个端口', store.port) : err;
        store.toast(tf('启动失败：{0}', this.error));
        return false;
      }
      this.error = '';
      this.startEpoch++;
      this.refreshIps();
      this.poll();
      if (store.background) {
        await this.startBackground();
      }
      this.poll();
      return true;
    } finally {
      this.busy = false;
    }
  }

  async stop(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      CoreApi.call(req('stop'));
      await this.stopBackground();
    } finally {
      this.busy = false;
    }
    this.poll();
  }

  /** Restart after a port / binding change (only if running). */
  async restartIfRunning(): Promise<void> {
    if (this.running) {
      await this.stop();
      await this.start();
    }
  }

  setLanUI(on: boolean): void {
    const q = req('lanUI');
    q['on'] = on;
    CoreApi.call(q);
  }

  /** Reads status + new log lines from the core. */
  poll(): void {
    const st = CoreApi.call(req('status'));
    this.running = jBool(st, 'running', false);
    this.started = jNum(st, 'started');
    this.requests = jNum(st, 'requests');
    this.engineOk = jBool(st, 'engineOk', false);
    this.initMs = jNum(st, 'initMs');
    this.backendVer = jStr(st, 'backend');
    this.frontendVer = jStr(st, 'frontend');
    const e = jStr(st, 'lastErr').length > 0 ? jStr(st, 'lastErr') : jStr(st, 'engineErr');
    if (e.length > 0) {
      this.error = e;
    }
    const q = req('logs');
    q['after'] = this.seq;
    const res = CoreApi.call(q);
    const lines = asArr(res['lines']);
    if (lines.length > 0) {
      const add: AccessLine[] = [];
      for (const l of lines) {
        const o = asObj(l);
        if (o !== undefined) {
          add.push(toLine(o));
        }
      }
      const all = this.logs.concat(add);
      this.logs = all.length > 2000 ? all.slice(all.length - 2000) : all;
      this.seq = jNum(res, 'seq');
    }
  }

  /** The newest lines for the 服务 page (the full list is on the 完整日志 page). */
  recentLogs(): AccessLine[] {
    const l = this.logs;
    return l.length > 300 ? l.slice(l.length - 300) : l;
  }

  clearLogs(): void {
    CoreApi.call(req('clearLogs'));
    this.logs = [];
  }

  private startPolling(): void {
    this.stopPolling();
    this.timer = setInterval(() => {
      if (Store.get().foreground) {
        this.poll();
      }
    }, 1500);
  }

  private stopPolling(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  onForeground(): void {
    this.refreshIps();
    this.poll();
  }

  // ------------------------------------------------------------------ continuous task

  async startBackground(): Promise<void> {
    const store = Store.get();
    const ctx = store.ctx;
    if (ctx === null || this.bgActive) {
      return;
    }
    try {
      const info: wantAgent.WantAgentInfo = {
        wants: [{ bundleName: ctx.abilityInfo.bundleName, abilityName: ctx.abilityInfo.name }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const agent: WantAgent = await wantAgent.getWantAgent(info);
      await backgroundTaskManager.startBackgroundRunning(ctx, backgroundTaskManager.BackgroundMode.DATA_TRANSFER, agent);
      this.bgActive = true;
      Log.i('Server', 'continuous task started');
      this.event('info', t('后台长时任务已开启（数据传输）'));
    } catch (e) {
      Log.w('Server', 'continuous task failed: ' + Log.describe(e as Object));
      this.event('warn', tf('后台长时任务未获系统允许：{0}', Log.describe(e as Object)));
      store.toast(t('后台运行未获系统允许，切到后台后服务可能暂停'));
    }
  }

  async stopBackground(): Promise<void> {
    const ctx = Store.get().ctx;
    if (ctx === null || !this.bgActive) {
      return;
    }
    try {
      await backgroundTaskManager.stopBackgroundRunning(ctx);
    } catch (e) {
      Log.w('Server', 'stop continuous task failed');
    }
    this.bgActive = false;
    this.event('info', t('后台长时任务已结束'));
  }

  /** Deletes every Sub-Store record (the backend's store) and restarts the server if it was running. */
  async wipe(): Promise<void> {
    const was = this.running;
    const q = req('reset');
    q['dir'] = this.dataDir();
    await CoreApi.callAsync(q);
    await this.stopBackground();
    this.poll();
    if (was) {
      await this.start();
    }
  }

  /** App is being destroyed. */
  shutdown(): void {
    CoreApi.call(req('stop'));
    this.stopPolling();
    this.stopBackground();
  }
}

function toLine(o: JObj): AccessLine {
  const l = new AccessLine();
  l.seq = jNum(o, 'seq');
  l.time = jNum(o, 'time');
  l.kind = jStr(o, 'kind').length > 0 ? jStr(o, 'kind') : 'access';
  l.level = jStr(o, 'level');
  l.msg = jStr(o, 'msg');
  l.ip = jStr(o, 'ip');
  l.method = jStr(o, 'method');
  l.path = jStr(o, 'path');
  l.status = jNum(o, 'status');
  l.ms = jNum(o, 'ms');
  l.bytes = jNum(o, 'bytes');
  l.ua = jStr(o, 'ua');
  return l;
}
