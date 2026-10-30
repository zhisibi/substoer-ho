/**
 * 服务管理 — the single native page (opened from the Sub-Store web UI's floating button), styled like the web UI:
 * service start / stop and addresses, port & access control, background & autostart, language, Sub-Store
 * component update, logs, disclaimer and about.
 */
import { t, tf } from '../common/I18n';
import { Store } from '../common/Store';
import { Server } from '../common/Server';
import { LINES, SsUpdate } from '../common/SsUpdate';
import { ActionButton, CardGroup, CellDivider, NavRow, PageHeader, Segmented, SwitchRow } from '../components/Widgets';
import { promptText } from '../components/InputDialog';
import { fmtDuration } from '../common/Format';
import { APP_NAME, DEFAULT_PORT, DEVELOPER, FEEDBACK_QQ_GROUP, UPSTREAM_URL, versionName } from '../common/AppInfo';
import { FileUtil } from '../common/FileUtil';
import { LightSense } from '../common/LightSense';
import { WebHolder } from '../views/StoreView';

const LANGS: string[] = ['system', 'zh', 'en'];
const THEMES: string[] = ['system', 'light', 'dark'];

@ComponentV2
export struct ManagePage {
  private store: Store = Store.get();
  @Local srv: Server = Server.get();
  @Local u: SsUpdate = SsUpdate.get();
  @Local now: number = Date.now();
  @Local stopping: boolean = false;
  @Local line: number = 0;
  @Local auto: boolean = true;
  private tick: number = -1;

  aboutToAppear(): void {
    this.srv.refreshIps();
    this.srv.poll();
    this.u.refreshLocal();
    this.line = this.u.line();
    this.auto = this.u.autoCheck();
    this.tick = setInterval(() => {
      this.now = Date.now();
    }, 1000);
  }

  aboutToDisappear(): void {
    clearInterval(this.tick);
  }

  // ------------------------------------------------------------------ actions

  async toggle(): Promise<void> {
    if (this.srv.busy) {
      return;
    }
    if (this.srv.running) {
      this.stopping = true;
      try {
        await this.srv.stop();
      } finally {
        this.stopping = false;
      }
    } else {
      await this.srv.start();
    }
  }

  async editPort(): Promise<void> {
    const v = await promptText(t('端口'), String(DEFAULT_PORT), String(this.store.port), t('1024–65535，修改后服务会自动重启'), true);
    if (v === null) {
      return;
    }
    const n = Number(v.trim());
    if (!Number.isInteger(n) || n < 1024 || n > 65535) {
      this.store.toast(t('端口需在 1024–65535 之间'));
      return;
    }
    this.store.setOpt('port', n);
    await this.srv.restartIfRunning();
  }

  async setLanAccess(v: boolean): Promise<void> {
    if (v) {
      const ok = await this.store.confirm(t('允许局域网访问'),
        t('开启后，同一局域网内的任何设备无需密码就能下载你的订阅（内容含节点地址和密码），且下载走明文传输。只在家里等可信网络中开启，用完建议关闭。'),
        t('仍然开启'), true);
      if (!ok) {
        return;
      }
    }
    this.store.setOpt('lanAccess', v);
    this.srv.restartIfRunning();
    this.srv.refreshIps();
  }

  async setLanUI(v: boolean): Promise<void> {
    if (v) {
      const ok = await this.store.confirm(t('局域网管理界面'),
        t('Sub-Store 后端没有账号密码。开启后，同一局域网内的任何设备都能打开管理界面，查看、修改或删除你的订阅和节点。\n\n只在家里等可信网络中开启，用完建议关闭。'),
        t('仍然开启'), true);
      if (!ok) {
        return;
      }
    }
    this.store.setOpt('lanUI', v);
    this.srv.setLanUI(v);
  }

  async explainBackground(): Promise<void> {
    await this.store.confirm(t('关于后台运行'),
      t('开启后，服务启动时会向系统申请“数据传输”长时任务并显示常驻通知，切到后台后继续提供订阅下载。\n\n但 HarmonyOS 可能仍会结束它：数据传输任务需要持续更新进度，系统检测到长时间无进度时会取消任务（约 10 分钟），省电策略或清理后台也会停止本应用。回到前台后可再次启动服务。\n\n需要长期稳定提供订阅时，建议保持应用在前台或使用常开的电脑 / NAS。'),
      t('我知道了'), false);
  }

  copy(text: string): void {
    FileUtil.copyText(text);
    this.store.toast(tf('已复制 {0}', text));
  }

  open(url: string): void {
    this.store.ctx?.openLink(url, { appLinkingOnly: false });
  }

  async wipe(): Promise<void> {
    if (!await this.store.confirm(t('清除全部数据'),
      t('将删除 Sub-Store 中的全部订阅、组合订阅、文件、同步配置、归档和设置，且无法恢复。建议先在 Sub-Store 中备份。'),
      t('清除'), true)) {
      return;
    }
    await this.srv.wipe();
    this.store.toast(t('已清除全部数据'));
  }

  async revoke(): Promise<void> {
    if (!await this.store.confirm(t('撤回同意'),
      t('撤回后服务会停止，应用将退出；再次打开需要重新阅读并同意。你保存的数据不会被删除。'), t('撤回并退出'), true)) {
      return;
    }
    this.srv.shutdown();
    this.store.revokePrivacy();
  }

  // ------------------------------------------------------------------ status

  /** stopped | starting | running | stopping */
  state(): string {
    if (this.srv.busy) {
      return this.srv.running || this.stopping ? 'stopping' : 'starting';
    }
    return this.srv.running ? 'running' : 'stopped';
  }

  stateText(): string {
    switch (this.state()) {
      case 'starting':
        return t('启动中…');
      case 'stopping':
        return t('停止中…');
      case 'running':
        return t('运行中');
      default:
        return this.srv.error.length > 0 ? t('启动失败') : t('已停止');
    }
  }

  stateColor(): string {
    const p = this.store.palette();
    switch (this.state()) {
      case 'running':
        return p.good;
      case 'stopped':
        return this.srv.error.length > 0 ? p.bad : p.tertiary;
      default:
        return p.warn;
    }
  }

  localUrl(): string {
    return 'http://127.0.0.1:' + this.store.port;
  }

  @Builder
  statusCard() {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        Image($r('app.media.startIcon')).width(48).height(48).borderRadius(12)
        Column({ space: 4 }) {
          Row({ space: 6 }) {
            Row().width(8).height(8).borderRadius(4).backgroundColor(this.stateColor())
            Text(this.stateText()).fontSize(17).fontWeight(FontWeight.Bold).fontColor(this.store.palette().text)
          }
          Text(this.srv.running ?
            tf('已运行 {0} · {1} 次请求', fmtDuration(Math.max(0, Math.floor((this.now - this.srv.started) / 1000))),
              this.srv.requests) :
            (this.srv.backendVer.length > 0 ? tf('Sub-Store 后端 {0}', this.srv.backendVer) : t('Sub-Store 后端')))
            .fontSize(13)
            .fontColor(this.store.palette().tertiary)
            .fontFeature('"tnum" on')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')

      if (this.srv.error.length > 0 && !this.srv.running) {
        Text(this.srv.error).fontSize(13).fontColor(this.store.palette().bad).maxLines(4).width('100%')
      }
      if (this.srv.running && this.store.background && !this.srv.bgActive) {
        Text(t('后台运行未获系统允许，切到后台后服务可能暂停')).fontSize(12).fontColor(this.store.palette().warn).width('100%')
      }

      ActionButton({
        text: this.srv.running ? t('停止服务') : t('启动服务'), filled: !this.srv.running, danger: this.srv.running,
        busy: this.srv.busy, fullWidth: true, onTap: () => {
          this.toggle();
        }
      })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.store.palette().card)
    .borderRadius(12)
  }

  // ------------------------------------------------------------------ sections

  @Builder
  addresses() {
    CardGroup({
      title: t('访问地址'), collapsible: true, open: true, summary: '127.0.0.1:' + this.store.port,
      footer: t('Sub-Store 里复制的订阅链接是 127.0.0.1 地址，供本机客户端使用；其他设备请换成局域网地址（只能访问 /download 和 /share）。点按地址可复制。')
    }) {
      NavRow({
        icon: $r('sys.symbol.lock'), title: t('本机'), value: '127.0.0.1:' + this.store.port, chevron: false, onTap: () => {
          this.copy(this.localUrl());
        }
      })
      if (this.store.lanAccess) {
        ForEach(this.srv.ips, (ip: string) => {
          CellDivider()
          NavRow({
            icon: $r('sys.symbol.wifi'), title: t('局域网'), value: ip + ':' + this.store.port, chevron: false, onTap: () => {
              this.copy('http://' + ip + ':' + this.store.port);
            }
          })
        }, (ip: string) => ip)
        if (this.srv.ips.length === 0) {
          CellDivider()
          NavRow({
            icon: $r('sys.symbol.wifi'), title: t('局域网'), value: t('未检测到，点按刷新'), chevron: false, onTap: () => {
              this.srv.refreshIps();
            }
          })
        }
      }
    }
  }

  @Builder
  access() {
    CardGroup({ title: t('端口与访问控制'), collapsible: true, open: false, summary: String(this.store.port) }) {
      NavRow({
        icon: $r('sys.symbol.gearshape'), title: t('端口'), value: String(this.store.port), onTap: () => {
          this.editPort();
        }
      })
      CellDivider()
      SwitchRow({
        title: t('允许局域网访问'), desc: t('开启后局域网设备可下载订阅（/download、/share）；关闭则只监听 127.0.0.1'),
        on: this.store.lanAccess, onToggle: (v: boolean) => {
          this.setLanAccess(v);
        }
      })
      if (this.store.lanAccess) {
        CellDivider()
        SwitchRow({
          title: t('局域网也可打开管理界面'), desc: t('后端没有登录验证，同一网络里的任何人都能查看和修改你的数据，仅在可信网络中开启'),
          on: this.store.lanUI, onToggle: (v: boolean) => {
            this.setLanUI(v);
          }
        })
      }
    }
  }

  @Builder
  bgSection() {
    CardGroup({ title: t('后台与自动启动'), collapsible: true, open: false }) {
      SwitchRow({
        title: t('后台继续运行'), desc: t('启动服务时申请系统长时任务（常驻通知），系统仍可能结束它'), on: this.store.background,
        onToggle: (v: boolean) => {
          this.store.setOpt('background', v);
          if (this.srv.running) {
            if (v) {
              this.srv.startBackground();
            } else {
              this.srv.stopBackground();
            }
          }
        }
      })
      CellDivider()
      SwitchRow({
        title: t('打开应用时自动启动服务'), on: this.store.autoStart, onToggle: (v: boolean) => {
          this.store.setOpt('autoStart', v);
        }
      })
      CellDivider()
      NavRow({
        icon: $r('sys.symbol.info_circle'), title: t('关于后台运行'),
        value: this.srv.running ? (this.srv.bgActive ? t('后台任务运行中') : t('后台任务未开启')) : '', onTap: () => {
          this.explainBackground();
        }
      })
    }
  }

  themeLabel(): string {
    const labels: string[] = [t('跟随系统'), t('浅色'), t('深色')];
    return labels[Math.max(0, THEMES.indexOf(this.store.themeMode))];
  }

  @Builder
  appearance() {
    CardGroup({ title: t('外观'), collapsible: true, open: false, summary: this.themeLabel() }) {
      Column({ space: 10 }) {
        Text(t('主题')).fontSize(13).fontColor(this.store.palette().tertiary).width('100%')
        Segmented({
          options: [t('跟随系统'), t('浅色'), t('深色')], selected: Math.max(0, THEMES.indexOf(this.store.themeMode)),
          onPick: (i: number) => {
            this.store.setThemeMode(THEMES[i]);
            WebHolder.applyGlass();
          }
        })
      }
      .padding({ left: 16, right: 16, top: 12, bottom: 6 })
      CellDivider()
      SwitchRow({
        title: t('导航栏沉浸光感'),
        desc: LightSense.material() ? t('顶栏呈悬浮玻璃胶囊，网页底部导航栏呈毛玻璃透光效果') :
          t('顶栏与网页底部导航栏呈毛玻璃透光效果（此设备不支持系统沉浸材质）'),
        on: this.store.navLight, onToggle: (v: boolean) => {
          this.store.setNavLight(v);
          WebHolder.applyGlass();
        }
      })
    }
  }

  @Builder
  language() {
    CardGroup({
      title: t('语言'), collapsible: true, open: false,
      summary: [t('跟随系统'), '中文', 'English'][Math.max(0, LANGS.indexOf(this.store.langPref))]
    }) {
      Segmented({
        options: [t('跟随系统'), '中文', 'English'], selected: Math.max(0, LANGS.indexOf(this.store.langPref)),
        onPick: (i: number) => {
          this.store.setLang(LANGS[i]);
        }
      })
        .padding(12)
    }
  }

  verText(v: string, updated: boolean, latest: string, isNew: boolean): string {
    const cur = v + (updated ? '' : ' · ' + t('内置'));
    if (!this.u.checked) {
      return cur;
    }
    return isNew ? cur + ' → ' + latest : cur + ' · ' + t('已是最新');
  }

  updStatus(): string {
    if (this.u.error.length > 0) {
      return tf('检查失败：{0}', this.u.error);
    }
    if (!this.u.checked) {
      return t('后端和前端由本项目的 GitHub Actions 跟进 Sub-Store 官方发布自动构建，安装前校验 SHA-256 并试运行，失败自动退回内置版本。');
    }
    if (this.u.backendNew && !this.u.compatible) {
      return t('新版后端需要更新本应用后才能运行；前端仍可单独更新。');
    }
    if (this.u.hasNew()) {
      return t('有新版本。更新后服务会自动重启，订阅和设置不受影响。');
    }
    return this.u.built.length > 0 ? tf('已是最新（构建于 {0}）', this.u.built) : t('已是最新');
  }

  @Builder
  update() {
    CardGroup({ title: t('Sub-Store 更新'), collapsible: true, open: false, summary: this.u.backend, footer: this.updStatus() }) {
      NavRow({
        icon: $r('sys.symbol.externaldrive'), title: t('后端'), chevron: false,
        value: this.verText(this.u.backend, this.u.backendUpdated, this.u.latestBackend, this.u.backendNew)
      })
      CellDivider()
      NavRow({
        icon: $r('sys.symbol.rectangle_stack'), title: t('前端'), chevron: false,
        value: this.verText(this.u.frontend, this.u.frontendUpdated, this.u.latestFrontend, this.u.frontendNew)
      })
      CellDivider()
      Column({ space: 10 }) {
        Text(t('下载线路')).fontSize(13).fontColor(this.store.palette().tertiary).width('100%')
        Segmented({
          options: LINES.map((s: string) => t(s)), selected: this.line, onPick: (i: number) => {
            this.line = i;
            this.u.setLine(i);
          }
        })
        Row({ space: 10 }) {
          if (this.u.backendUpdated || this.u.frontendUpdated) {
            ActionButton({
              text: t('恢复内置版本'), filled: false, onTap: () => {
                this.u.rollback();
              }
            })
          }
          ActionButton({
            text: this.u.hasNew() ? t('立即更新') : t('检查更新'), busy: this.u.busy, fullWidth: true, onTap: () => {
              if (this.u.hasNew()) {
                this.u.install();
              } else {
                this.u.check(false);
              }
            }
          })
            .layoutWeight(1)
        }
        .width('100%')
      }
      .padding({ left: 16, right: 16, top: 12, bottom: 14 })
      CellDivider()
      SwitchRow({
        title: t('启动时检查更新'), desc: t('每天最多检查一次，有新版本时提示'), on: this.auto, onToggle: (v: boolean) => {
          this.auto = v;
          this.u.setAutoCheck(v);
        }
      })
    }
  }

  @Builder
  about() {
    CardGroup({ title: t('关于'), collapsible: true, open: false, summary: versionName() }) {
      Row({ space: 14 }) {
        Image($r('app.media.startIcon')).width(52).height(52).borderRadius(12)
        Column({ space: 3 }) {
          Text(APP_NAME).fontSize(17).fontWeight(FontWeight.Bold).fontColor(this.store.palette().text)
          Text(tf('版本 {0} · Sub-Store 第三方鸿蒙客户端（非官方）', versionName()))
            .fontSize(12)
            .fontColor(this.store.palette().tertiary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 12 })
      CellDivider()
      NavRow({ icon: $r('sys.symbol.person'), title: t('开发者'), value: DEVELOPER, chevron: false })
      CellDivider()
      NavRow({
        icon: $r('sys.symbol.ellipsis_message'), title: t('问题反馈（QQ群）'), value: FEEDBACK_QQ_GROUP, chevron: false, onTap: () => {
          this.copy(FEEDBACK_QQ_GROUP);
        }
      })
      CellDivider()
      NavRow({
        icon: $r('sys.symbol.arrow_down_circle'), title: t('检查更新'), value: this.u.appChecking ? t('检查中…') : '',
        onTap: () => {
          this.u.checkApp();
        }
      })
      CellDivider()
      NavRow({
        icon: $r('sys.symbol.rectangle_stack'), title: t('基于 Sub-Store'), value: 'sub-store-org/Sub-Store', onTap: () => {
          this.open(UPSTREAM_URL);
        }
      })
      CellDivider()
      NavRow({
        icon: $r('sys.symbol.doc_text'), title: t('开源许可'), onTap: () => {
          this.store.push('licenses', null);
        }
      })
      CellDivider()
      NavRow({
        icon: $r('sys.symbol.trash'), title: t('清除全部数据'), danger: true, chevron: false, onTap: () => {
          this.wipe();
        }
      })
      CellDivider()
      NavRow({
        icon: $r('sys.symbol.xmark_circle'), title: t('撤回同意'), danger: true, chevron: false, onTap: () => {
          this.revoke();
        }
      })
    }
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({
          title: t('服务管理'), showBack: true, onBack: () => {
            this.store.pop();
          }
        })
        Scroll() {
          Column({ space: 20 }) {
            this.statusCard()
            this.addresses()
            this.access()
            this.bgSection()
            this.appearance()
            this.language()
            this.update()
            CardGroup({ title: t('日志与声明'), collapsible: true, open: false, summary: String(this.srv.logs.length) }) {
              NavRow({
                icon: $r('sys.symbol.doc_text'), title: t('运行日志'), value: String(this.srv.logs.length), onTap: () => {
                  this.store.push('logs', null);
                }
              })
              CellDivider()
              NavRow({
                icon: $r('sys.symbol.checkmark_shield'), title: t('免责声明与隐私说明'), onTap: () => {
                  this.store.push('legal', 'disclaimer');
                }
              })
              CellDivider()
              NavRow({
                icon: $r('sys.symbol.lock'), title: t('隐私政策'), onTap: () => {
                  this.store.push('legal', 'privacy');
                }
              })
              CellDivider()
              NavRow({
                icon: $r('sys.symbol.doc_text'), title: t('用户协议'), onTap: () => {
                  this.store.push('legal', 'terms');
                }
              })
            }
            this.about()
          }
          .padding({ left: 14, right: 14, top: 4, bottom: this.store.bottomPad() })
          .constraintSize({ maxWidth: 760 })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor(this.store.palette().bg)
  }
}
