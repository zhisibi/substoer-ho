/**
 * Sub-Store 更新: shows the backend / web UI versions in use (built-in or downloaded), checks the repo's
 * manifest, installs newer builds and restores the built-in versions. Logic in common/SsUpdate.ets.
 */
import { t, tf } from '../common/I18n';
import { Store } from '../common/Store';
import { LINES, SsUpdate } from '../common/SsUpdate';
import { ActionButton, CardGroup, NavRow, PageHeader, Segmented, SwitchRow } from '../components/Widgets';
import { pageBackdrop } from '../components/Backdrop';

@ComponentV2
export struct UpdatePage {
  private store: Store = Store.get();
  @Local u: SsUpdate = SsUpdate.get();
  @Local line: number = 0;
  @Local auto: boolean = true;

  aboutToAppear(): void {
    this.u.refreshLocal();
    this.line = this.u.line();
    this.auto = this.u.autoCheck();
  }

  verText(v: string, updated: boolean): string {
    return v + ' · ' + (updated ? t('已更新') : t('内置'));
  }

  latestText(v: string, isNew: boolean): string {
    if (!this.u.checked) {
      return t('未检查');
    }
    return isNew ? tf('{0} 可更新', v) : t('已是最新');
  }

  statusText(): string {
    if (this.u.error.length > 0) {
      return tf('检查失败：{0}', this.u.error);
    }
    if (!this.u.checked) {
      return t('点“检查更新”从 GitHub 获取最新构建。');
    }
    if (this.u.backendNew && !this.u.compatible) {
      return t('新版后端需要更新的 咪咪SubStore 才能运行，请先更新本应用；前端仍可单独更新。');
    }
    if (this.u.hasNew()) {
      return t('有新版本。更新会先校验文件并试运行后端，成功后自动重启服务，订阅和设置不受影响。');
    }
    return this.u.built.length > 0 ? tf('已是最新（构建于 {0}）', this.u.built) : t('已是最新');
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({
          title: t('Sub-Store 更新'), showBack: true, onBack: () => {
            this.store.pop();
          }
        })
        Scroll() {
          Column({ space: 12 }) {
            CardGroup({ title: t('版本') }) {
              NavRow({
                icon: $r('sys.symbol.externaldrive'), title: t('后端'),
                value: this.verText(this.u.backend, this.u.backendUpdated), chevron: false
              })
              NavRow({
                icon: $r('sys.symbol.arrow_down_circle'), title: t('最新后端'),
                value: this.latestText(this.u.latestBackend, this.u.backendNew), chevron: false
              })
              NavRow({
                icon: $r('sys.symbol.rectangle_stack'), title: t('前端'),
                value: this.verText(this.u.frontend, this.u.frontendUpdated), chevron: false
              })
              NavRow({
                icon: $r('sys.symbol.arrow_down_circle'), title: t('最新前端'),
                value: this.latestText(this.u.latestFrontend, this.u.frontendNew), chevron: false
              })
            }

            Text(this.statusText())
              .fontSize(13)
              .lineHeight(19)
              .fontColor(this.u.error.length > 0 ? this.store.palette().bad : this.store.palette().subtle)
              .width('100%')
              .padding({ left: 6, right: 6 })

            if (this.u.hasNew()) {
              ActionButton({
                text: t('立即更新'), fullWidth: true, busy: this.u.busy, onTap: () => {
                  this.u.install();
                }
              })
            } else {
              ActionButton({
                text: t('检查更新'), fullWidth: true, busy: this.u.busy, onTap: () => {
                  this.u.check(false);
                }
              })
            }
            if (this.u.backendUpdated || this.u.frontendUpdated) {
              ActionButton({
                text: t('恢复内置版本'), filled: false, fullWidth: true, onTap: () => {
                  this.u.rollback();
                }
              })
            }

            CardGroup({ title: t('下载线路') }) {
              Segmented({
                options: LINES.map((s: string) => t(s)), selected: this.line, onPick: (i: number) => {
                  this.line = i;
                  this.u.setLine(i);
                }
              })
                .padding({ left: 12, right: 12, top: 12, bottom: 8 })
              Text(t('国内直连 GitHub 可能很慢；“自动”先试 GitHub，失败再走 ghfast.top、gh-proxy.com 等公共加速。文件都会按清单校验 SHA-256。'))
                .fontSize(12)
                .lineHeight(18)
                .fontColor(this.store.palette().subtle)
                .padding({ left: 16, right: 16, bottom: 12 })
              SwitchRow({
                title: t('启动时检查更新'), desc: t('每天最多检查一次，有新版本时提示'), on: this.auto,
                onToggle: (v: boolean) => {
                  this.auto = v;
                  this.u.setAutoCheck(v);
                }
              })
            }

            Text(t('更新来自本应用的开源仓库：GitHub Actions 自动跟进 sub-store-org 的正式发布，套用与安装包相同的适配补丁并完成冒烟测试后发布。新后端启动失败时会自动退回内置版本。'))
              .fontSize(12)
              .lineHeight(18)
              .fontColor(this.store.palette().subtle)
              .width('100%')
              .padding({ left: 6, right: 6 })
            NavRow({
              icon: $r('sys.symbol.link'), title: t('开源仓库'), value: 'zhisibi/substoer-ho', onTap: () => {
                this.store.ctx?.openLink('https://github.com/zhisibi/substoer-ho', { appLinkingOnly: false });
              }
            })
          }
          .padding({ left: 12, right: 12, top: 4, bottom: this.store.safeBottom + 24 })
          .constraintSize({ maxWidth: 760 })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor(this.store.palette().bg)
    .background(pageBackdrop)
  }
}
