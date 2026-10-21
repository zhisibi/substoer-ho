/**
 * 服务: a big round power button in the 猫Box style (dashed ring when stopped, solid accent ring + filled disc when
 * running, spinner while starting / stopping), then collapsible cards for the addresses, port & LAN access, and
 * background & autostart, and the always-open 运行日志: server events (start / stop / bind errors / background task),
 * Sub-Store backend console output, and access lines (subscription downloads and requests from other devices; the
 * web UI's own traffic is not logged). Tapping a row opens a sheet with the whole entry (monospace, 复制).
 */
import { t, tf } from '../common/I18n';
import { Store } from '../common/Store';
import { AccessLine, Server } from '../common/Server';
import { ActionButton, CardGroup, IconBtn, NavRow, PageHeader, SwitchRow } from '../components/Widgets';
import { promptText } from '../components/InputDialog';
import { fmtBytes, fmtClock, fmtDuration } from '../common/Format';
import { DEFAULT_PORT } from '../common/AppInfo';
import { FileUtil } from '../common/FileUtil';

const LOG_H: number = 380;

@ComponentV2
export struct ServerView {
  private store: Store = Store.get();
  private srv: Server = Server.get();
  private logScroller: Scroller = new Scroller();
  @Local now: number = Date.now();
  /** follow new lines (off once the user scrolls up, back on at the bottom) */
  @Local follow: boolean = true;
  /** the user asked to stop: spinner on the button until the core says it stopped */
  @Local stopping: boolean = false;
  /** header refresh: spinner on the top-right button until the addresses / status are re-read */
  @Local refreshing: boolean = false;
  /** run-log detail sheet (1.0.5): the tapped entry, shown in full */
  @Local detailOpen: boolean = false;
  @Local detail: AccessLine = new AccessLine();
  private tick: number = -1;
  private lastSeq: number = -1;

  aboutToAppear(): void {
    this.srv.refreshIps();
    this.srv.poll();
    this.tick = setInterval(() => {
      this.now = Date.now();
      this.autoScroll();
    }, 500);
  }

  aboutToDisappear(): void {
    clearInterval(this.tick);
  }

  autoScroll(): void {
    const l = this.srv.recentLogs();
    const seq = l.length > 0 ? l[l.length - 1].seq : 0;
    if (seq !== this.lastSeq) {
      this.lastSeq = seq;
      if (this.follow && l.length > 0) {
        this.logScroller.scrollToIndex(l.length - 1, true);
      }
    }
  }

  /** stopped | starting | running | stopping */
  state(): string {
    if (this.srv.busy) {
      return this.srv.running || this.stopping ? 'stopping' : 'starting';
    }
    return this.srv.running ? 'running' : 'stopped';
  }

  isOn(): boolean {
    return this.state() === 'running';
  }

  /** the disc is filled while running and while starting (as on 猫Box) */
  filled(): boolean {
    return this.state() === 'running' || this.state() === 'starting';
  }

  statusText(): string {
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

  async explainBackground(): Promise<void> {
    await this.store.confirm(t('关于后台运行'),
      t('开启后，服务启动时会向系统申请“数据传输”长时任务并显示常驻通知，切到后台后继续提供订阅下载。\n\n但 HarmonyOS 可能仍会结束它：数据传输任务需要持续更新进度，系统检测到长时间无进度时会取消任务（约 10 分钟），省电策略或清理后台也会停止本应用。回到前台后可再次启动服务。\n\n需要长期稳定提供订阅时，建议保持应用在前台或使用常开的电脑 / NAS。'),
      t('我知道了'), false);
  }

  /**
   * Top-right 刷新: re-reads the LAN addresses and the server status. Up to 1.0.4 it did that silently (and the
   * 0.5 s poll already kept the status current), so a tap looked like it did nothing; now it spins briefly and
   * says what it found.
   */
  refresh(): void {
    if (this.refreshing) {
      return;
    }
    this.refreshing = true;
    this.srv.refreshIps();
    this.srv.poll();
    setTimeout(() => {
      this.refreshing = false;
      if (!this.store.lanAccess) {
        this.store.toast(t('已刷新：仅本机访问'));
      } else if (this.srv.ips.length === 0) {
        this.store.toast(t('已刷新：没有检测到局域网地址'));
      } else {
        this.store.toast(tf('已刷新：{0} 个局域网地址', this.srv.ips.length));
      }
    }, 450);
  }

  openDetail(l: AccessLine): void {
    this.detail = l;
    this.detailOpen = true;
  }

  /** Full text of one log entry (detail sheet + 复制). */
  detailText(l: AccessLine): string {
    const d = new Date(l.time);
    const p2 = (n: number): string => (n < 10 ? '0' : '') + n;
    const when = d.getFullYear() + '-' + p2(d.getMonth() + 1) + '-' + p2(d.getDate()) + ' ' + fmtClock(l.time);
    const out: string[] = [];
    out.push(t('时间') + ': ' + when);
    if (l.kind === 'event') {
      out.push(t('级别') + ': ' + (l.level.length > 0 ? l.level : 'info'));
      out.push('');
      out.push(l.msg);
    } else {
      out.push(t('状态') + ': ' + l.status);
      out.push(t('客户端') + ': ' + l.ip);
      if (l.method.length > 0) {
        out.push(t('方法') + ': ' + l.method);
      }
      out.push(t('路径') + ': ' + l.path);
      if (l.bytes > 0) {
        out.push(t('大小') + ': ' + fmtBytes(l.bytes));
      }
      out.push(t('耗时') + ': ' + l.ms + ' ms');
      if (l.ua.length > 0) {
        out.push('User-Agent: ' + l.ua);
      }
      if (l.msg.length > 0) {
        out.push('');
        out.push(l.msg);
      }
    }
    return out.join('\n');
  }

  @Builder
  detailSheet() {
    Column({ space: 12 }) {
      Text(this.detail.kind === 'event' ? t('日志详情') : t('访问详情'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.store.palette().text)
        .width('100%')
      Scroll() {
        Text(this.detailText(this.detail))
          .fontSize(13)
          .lineHeight(20)
          .fontFamily('monospace')
          .fontColor(this.store.palette().text)
          .copyOption(CopyOptions.LocalDevice)
          .wordBreak(WordBreak.BREAK_ALL)
          .width('100%')
          .padding(14)
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Auto)
      .borderRadius(14)
      .backgroundColor(this.store.palette().card)
      ActionButton({
        text: t('复制'), fullWidth: true, onTap: () => {
          FileUtil.copyText(this.detailText(this.detail));
          this.store.toast(t('已复制'));
        }
      })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 4, bottom: this.store.safeBottom + 16 })
  }

  // ------------------------------------------------------------------ hero (猫Box power button)

  @Builder
  hero() {
    Column() {
      Stack() {
        Circle()
          .width(176)
          .height(176)
          .fill(Color.Transparent)
          .stroke(this.isOn() ? this.store.palette().accentUi : this.store.palette().outline)
          .strokeWidth(this.isOn() ? 5 : 2)
          .strokeDashArray(this.isOn() ? [] : [6, 8])
          .opacity(this.isOn() ? 0.55 : 1)
        Column({ space: 6 }) {
          if (this.srv.busy) {
            LoadingProgress().width(44).height(44)
              .color(this.state() === 'starting' ? this.store.palette().onPrimary : this.store.palette().accentUi)
          } else {
            SymbolGlyph($r('sys.symbol.power'))
              .fontSize(46)
              .fontColor([this.isOn() ? this.store.palette().onPrimary : this.store.palette().accentUi])
          }
          Text(this.statusText())
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.filled() ? this.store.palette().onPrimary : this.store.palette().text)
        }
        .justifyContent(FlexAlign.Center)
        .width(144)
        .height(144)
        .borderRadius(72)
        .backgroundColor(this.filled() ? this.store.palette().primary : this.store.palette().accentSoft)
        .shadow(this.isOn() ? { radius: 28, color: this.store.palette().accentSoft, offsetY: 6 } :
          { radius: 0, color: Color.Transparent })
        .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.92 })
        .animation({ duration: 250, curve: Curve.EaseOut })
        .accessibilityText(this.isOn() ? t('停止服务') : t('启动服务'))
        .onClick(() => {
          this.toggle();
        })
      }
      .width(176)
      .height(176)
      .margin({ top: 14, bottom: 14 })

      Text(this.isOn() ? tf('端口 {0} · {1}', this.store.port, this.store.lanAccess ? t('局域网可访问') : t('仅本机')) :
        (this.srv.backendVer.length > 0 ? tf('Sub-Store 后端 {0}', this.srv.backendVer) : t('Sub-Store 后端')))
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.store.palette().text)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.isOn()) {
        Text(tf('已运行 {0} · {1} 次请求', fmtDuration(Math.max(0, Math.floor((this.now - this.srv.started) / 1000))),
          this.srv.requests))
          .fontSize(12)
          .fontColor(this.store.palette().subtle)
          .fontFeature('"tnum" on')
          .margin({ top: 6 })
      } else {
        Text(t('点按圆形按钮启动 Sub-Store 服务'))
          .fontSize(12)
          .fontColor(this.store.palette().subtle)
          .margin({ top: 6 })
      }
      if (this.srv.error.length > 0 && !this.srv.running) {
        Text(this.srv.error)
          .fontSize(12)
          .fontColor(this.store.palette().bad)
          .maxLines(4)
          .textAlign(TextAlign.Center)
          .width('100%')
          .margin({ top: 12 })
      }
      if (this.srv.running && this.store.background && !this.srv.bgActive) {
        Text(t('后台运行未获系统允许，切到后台后服务可能暂停'))
          .fontSize(12)
          .fontColor(this.store.palette().warn)
          .textAlign(TextAlign.Center)
          .width('100%')
          .margin({ top: 10 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 16, bottom: 18, left: 16, right: 16 })
    .borderRadius(32)
    .backgroundColor(this.store.palette().card)
    .backdropBlur(this.store.blurPx())
  }

  // ------------------------------------------------------------------ run log

  @Builder
  logRow(l: AccessLine) {
    if (l.kind === 'event') {
      Row({ space: 8 }) {
        Text(fmtClock(l.time)).fontSize(11).fontFamily('monospace').fontColor(this.store.palette().subtle)
        Row()
          .width(7)
          .height(7)
          .borderRadius(4)
          .backgroundColor(l.level === 'error' ? this.store.palette().bad :
            (l.level === 'warn' ? this.store.palette().warn : this.store.palette().info))
        Text(l.msg)
          .fontSize(12)
          .fontColor(l.level === 'error' ? this.store.palette().bad :
            (l.level === 'warn' ? this.store.palette().warn : this.store.palette().text))
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding({ left: 14, right: 12, top: 6, bottom: 6 })
    } else {
      Column({ space: 2 }) {
        Row({ space: 8 }) {
          Text(fmtClock(l.time)).fontSize(11).fontFamily('monospace').fontColor(this.store.palette().subtle)
          Text(String(l.status))
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(l.status === 200 ? this.store.palette().good : this.store.palette().bad)
          Text(l.ip).fontSize(12).fontFamily('monospace').fontColor(this.store.palette().text)
          Text(l.method + ' ' + l.path)
            .fontSize(12)
            .fontColor(this.store.palette().text)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        Text((l.bytes > 0 ? fmtBytes(l.bytes) + ' · ' : '') + l.ms + ' ms' + (l.ua.length > 0 ? ' · ' + l.ua : ''))
          .fontSize(11)
          .fontColor(this.store.palette().subtle)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .width('100%')
      .padding({ left: 14, right: 12, top: 6, bottom: 6 })
    }
  }

  @Builder
  runLog() {
    Column() {
      Row({ space: 8 }) {
        Text(tf('运行日志（{0}）', this.srv.logs.length))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.store.palette().text)
          .layoutWeight(1)
        Text(this.follow ? t('自动滚动') : t('已暂停滚动'))
          .fontSize(12)
          .fontColor(this.follow ? this.store.palette().accent : this.store.palette().subtle)
          .backgroundColor(this.follow ? this.store.palette().accentSoft : this.store.palette().chip)
          .borderRadius(12)
          .height(28)
          .padding({ left: 10, right: 10 })
          .onClick(() => {
            this.follow = !this.follow;
            if (this.follow && this.srv.logs.length > 0) {
              this.logScroller.scrollToIndex(this.srv.recentLogs().length - 1, true);
            }
          })
        IconBtn({
          icon: $r('sys.symbol.doc_text'), label: t('完整日志'), iconSize: 18, box: 40, onTap: () => {
            this.store.push('logs', null);
          }
        })
        IconBtn({
          icon: $r('sys.symbol.trash'), label: t('清空日志'), iconSize: 18, box: 40,
          active: this.srv.logs.length > 0, onTap: () => {
            this.srv.clearLogs();
          }
        })
      }
      .width('100%')
      .padding({ left: 16, right: 6, top: 6 })

      if (this.srv.logs.length === 0) {
        Text(t('还没有日志。启动、停止服务和客户端下载订阅都会实时显示在这里。'))
          .fontSize(12)
          .fontColor(this.store.palette().subtle)
          .padding(16)
          .width('100%')
      } else {
        List({ scroller: this.logScroller }) {
          ForEach(this.srv.recentLogs(), (l: AccessLine) => {
            ListItem() {
              this.logRow(l)
            }
            .width('100%')
            .accessibilityText(t('查看日志详情'))
            .onClick(() => {
              this.openDetail(l);
            })
          }, (l: AccessLine) => String(l.seq))
        }
        .height(LOG_H)
        .width('100%')
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.None)
        .divider({ strokeWidth: 0.5, color: this.store.palette().divider, startMargin: 14, endMargin: 12 })
        .nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
        .onScrollFrameBegin((offset: number, st: ScrollState) => {
          // a finger scrolling up to read pauses following (scrollToIndex does not fire this); the end resumes it
          if (offset < 0 && st !== ScrollState.Idle) {
            this.follow = false;
          }
          return { offsetRemain: offset };
        })
        .onReachEnd(() => {
          this.follow = true;
        })
      }
    }
    .width('100%')
    .padding({ bottom: 6 })
    .backgroundColor(this.store.palette().card)
    .backdropBlur(this.store.blurPx())
    .borderRadius(16)
  }

  build() {
    Column() {
      PageHeader({ title: t('服务'), subtitle: this.srv.running ? tf('运行中 · 端口 {0}', this.store.port) : t('未运行') }) {
        IconBtn({
          icon: $r('sys.symbol.arrow_2_circlepath'), label: t('刷新地址与状态'), busy: this.refreshing, onTap: () => {
            this.refresh();
          }
        })
      }
      Scroll() {
        Column({ space: 14 }) {
          this.hero()

          CardGroup({
            title: t('访问地址'), collapsible: true, icon: $r('sys.symbol.wifi'),
            summary: this.store.lanAccess ? tf('本机 + {0} 个局域网地址', this.srv.ips.length) : t('仅本机')
          }) {
            NavRow({ icon: $r('sys.symbol.lock'), title: t('本机'), value: '127.0.0.1:' + this.store.port, chevron: false })
            if (this.store.lanAccess) {
              ForEach(this.srv.ips, (ip: string) => {
                NavRow({ icon: $r('sys.symbol.wifi'), title: t('局域网'), value: ip + ':' + this.store.port, chevron: false })
              }, (ip: string) => ip)
              if (this.srv.ips.length === 0) {
                Text(t('没有检测到局域网 IP：连接 Wi-Fi 或开启热点后点右上角刷新。'))
                  .fontSize(12).fontColor(this.store.palette().subtle).padding({ left: 16, right: 16, bottom: 12 })
              }
            } else {
              Text(t('已设置为仅本机访问，局域网设备无法下载。')).fontSize(12).fontColor(this.store.palette().subtle)
                .padding({ left: 16, right: 16, bottom: 12 })
            }
            Text(t('Sub-Store 里复制的订阅链接是 127.0.0.1 地址，供本机客户端使用；其他设备请把地址换成上面的局域网地址。其他设备只能访问 /download 和 /share 订阅链接。'))
              .fontSize(12).fontColor(this.store.palette().subtle).padding({ left: 16, right: 16, bottom: 12 })
          }

          CardGroup({
            title: t('端口与访问控制'), collapsible: true, icon: $r('sys.symbol.key'),
            summary: tf('端口 {0}', this.store.port) + (this.store.lanAccess ? ' · ' + t('局域网') : ' · ' + t('仅本机'))
          }) {
            NavRow({
              icon: $r('sys.symbol.gearshape'), title: t('端口'), value: String(this.store.port), onTap: () => {
                this.editPort();
              }
            })
            SwitchRow({
              title: t('允许局域网访问'), desc: t('开启后局域网设备可下载订阅（/download、/share）；关闭则只监听 127.0.0.1'), on: this.store.lanAccess,
              onToggle: (v: boolean) => {
                this.store.setOpt('lanAccess', v);
                this.srv.restartIfRunning();
              }
            })
            if (this.store.lanAccess) {
              SwitchRow({
                title: t('局域网也可打开管理界面'), desc: t('允许其他设备在浏览器中打开 Sub-Store 界面并调用后端接口。后端没有登录验证，同一网络里的任何人都能查看和修改你的数据，仅在可信网络中开启'),
                on: this.store.lanUI,
                onToggle: async (v: boolean) => {
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
              })
            }
          }

          CardGroup({
            title: t('后台与自动启动'), collapsible: true, icon: $r('sys.symbol.clock'),
            summary: (this.store.background ? t('后台运行') : t('仅前台')) + (this.store.autoStart ? ' · ' + t('自动启动') : '')
          }) {
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
            NavRow({
              icon: $r('sys.symbol.info_circle'), title: t('关于后台运行'), onTap: () => {
                this.explainBackground();
              }
            })
            SwitchRow({
              title: t('打开应用时自动启动服务'), on: this.store.autoStart, onToggle: (v: boolean) => {
                this.store.setOpt('autoStart', v);
              }
            })
            if (this.srv.running) {
              NavRow({
                title: t('后台任务'), value: this.srv.bgActive ? t('运行中') : t('未开启'), chevron: false
              })
            }
          }

          this.runLog()
        }
        .padding({ left: 12, right: 12, top: 4, bottom: this.store.bottomPad(false) })
        .constraintSize({ maxWidth: 760 })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      Column().width('100%').height(0)
        .bindSheet(this.detailOpen, this.detailSheet(), {
          height: SheetSize.MEDIUM, backgroundColor: this.store.palette().sheet, showClose: true,
          onDisappear: () => {
            this.detailOpen = false;
          }
        })
    }
    .width('100%')
    .height('100%')
  }
}
