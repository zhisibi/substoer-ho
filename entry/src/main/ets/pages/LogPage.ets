/**
 * 完整日志: every run-log entry the core keeps (up to 2000): service events, Sub-Store backend console output and
 * access lines, oldest first, each shown in full (no line cap, selectable). Filter 全部 / 后端 / 访问 / 错误;
 * the header copies the filtered log as plain text, saves it to a .log file, or clears it.
 */
import { t, tf } from '../common/I18n';
import { Store } from '../common/Store';
import { AccessLine, Server } from '../common/Server';
import { IconBtn, PageHeader, Segmented } from '../components/Widgets';
import { FileUtil } from '../common/FileUtil';
import { fmtBytes } from '../common/Format';
import { pageBackdrop } from '../components/Backdrop';

const FILTERS: string[] = ['全部', '后端', '访问', '错误'];

function p2(n: number): string {
  return (n < 10 ? '0' : '') + n;
}

function stamp(ms: number): string {
  const d = new Date(ms);
  return d.getFullYear() + '-' + p2(d.getMonth() + 1) + '-' + p2(d.getDate()) + ' ' + p2(d.getHours()) + ':' +
    p2(d.getMinutes()) + ':' + p2(d.getSeconds());
}

/** One entry as a plain-text log line (also what 复制 / 保存 write). */
export function logLineText(l: AccessLine): string {
  if (l.kind === 'event') {
    return stamp(l.time) + ' [' + (l.level.length > 0 ? l.level : 'info') + '] ' + l.msg;
  }
  return stamp(l.time) + ' [access] ' + l.status + ' ' + l.ip + ' ' + l.method + ' ' + l.path +
    (l.bytes > 0 ? ' ' + fmtBytes(l.bytes) : '') + ' ' + l.ms + 'ms' + (l.ua.length > 0 ? ' UA=' + l.ua : '');
}

function isBackend(l: AccessLine): boolean {
  return l.kind === 'event' && l.msg.startsWith('[sub-store]');
}

function isError(l: AccessLine): boolean {
  return (l.kind === 'event' && (l.level === 'error' || l.msg.indexOf('ERROR') >= 0)) ||
    (l.kind === 'access' && l.status >= 400);
}

@ComponentV2
export struct LogPage {
  private store: Store = Store.get();
  @Local srv: Server = Server.get();
  @Local filter: number = 0;
  private scroller: Scroller = new Scroller();

  shown(): AccessLine[] {
    const all = this.srv.logs;
    switch (this.filter) {
      case 1:
        return all.filter((l: AccessLine) => isBackend(l));
      case 2:
        return all.filter((l: AccessLine) => l.kind === 'access');
      case 3:
        return all.filter((l: AccessLine) => isError(l));
      default:
        return all;
    }
  }

  allText(): string {
    return this.shown().map((l: AccessLine) => logLineText(l)).join('\n');
  }

  copyAll(): void {
    const list = this.shown();
    if (list.length === 0) {
      this.store.toast(t('没有日志'));
      return;
    }
    FileUtil.copyText(this.allText());
    this.store.toast(tf('已复制 {0} 条日志', list.length));
  }

  async saveAll(): Promise<void> {
    const ctx = this.store.ctx;
    if (ctx === null || this.shown().length === 0) {
      this.store.toast(t('没有日志'));
      return;
    }
    const d = new Date();
    const name = 'mimisubstore-' + d.getFullYear() + p2(d.getMonth() + 1) + p2(d.getDate()) + '-' + p2(d.getHours()) +
      p2(d.getMinutes()) + '.log';
    try {
      const saved = await FileUtil.saveTextAs(ctx, name, this.allText() + '\n');
      if (saved.length > 0) {
        this.store.toast(tf('已保存：{0}', saved));
      }
    } catch (e) {
      this.store.toast(tf('保存失败：{0}', (e as Error).message ?? ''));
    }
  }

  async clear(): Promise<void> {
    if (await this.store.confirm(t('清空日志'), t('清空全部运行日志？'), t('清空'), true)) {
      this.srv.clearLogs();
    }
  }

  @Builder
  row(l: AccessLine) {
    Text(logLineText(l))
      .fontSize(11.5)
      .lineHeight(17)
      .fontFamily('monospace')
      .wordBreak(WordBreak.BREAK_ALL)
      .copyOption(CopyOptions.LocalDevice)
      .fontColor(isError(l) ? this.store.palette().bad :
        (l.level === 'warn' ? this.store.palette().warn : this.store.palette().text))
      .width('100%')
      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({
          title: t('完整日志'), subtitle: tf('{0} 条', this.shown().length), showBack: true, onBack: () => {
            this.store.pop();
          }
        }) {
          IconBtn({
            icon: $r('sys.symbol.doc_filled_on_doc'), label: t('复制全部'), onTap: () => {
              this.copyAll();
            }
          })
          IconBtn({
            icon: $r('sys.symbol.square_and_arrow_down'), label: t('保存为文件'), onTap: () => {
              this.saveAll();
            }
          })
          IconBtn({
            icon: $r('sys.symbol.trash'), label: t('清空日志'), active: this.srv.logs.length > 0, onTap: () => {
              this.clear();
            }
          })
        }
        Segmented({
          options: FILTERS.map((s: string) => t(s)), selected: this.filter, onPick: (i: number) => {
            this.filter = i;
          }
        })
          .padding({ left: 12, right: 12, bottom: 8 })
        if (this.shown().length === 0) {
          Text(t('没有日志'))
            .fontSize(13)
            .fontColor(this.store.palette().subtle)
            .padding(24)
        } else {
          List({ scroller: this.scroller, initialIndex: Math.max(0, this.shown().length - 1) }) {
            ForEach(this.shown(), (l: AccessLine) => {
              ListItem() {
                this.row(l)
              }
            }, (l: AccessLine) => String(l.seq))
          }
          .layoutWeight(1)
          .width('100%')
          .cachedCount(20)
          .scrollBar(BarState.Auto)
          .divider({ strokeWidth: 0.5, color: this.store.palette().divider, startMargin: 12, endMargin: 12 })
          .backgroundColor(this.store.palette().card)
          .padding({ bottom: this.store.safeBottom })
        }
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor(this.store.palette().bg)
    .background(pageBackdrop)
  }
}
