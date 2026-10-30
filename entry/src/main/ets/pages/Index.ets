/**
 * Root page. First launch: consent (disclaimer & privacy notice). Then the Sub-Store web UI fills the
 * screen; a floating button opens 服务管理 (pages/ManagePage). The disclaimer pops up at every launch until the user
 * ticks 不再提示 (again whenever it changes). Legal pages, licenses, logs and 服务管理 are NavDestinations.
 */
import { t } from '../common/I18n';
import { Store } from '../common/Store';
import { Server } from '../common/Server';
import { ActionButton } from '../components/Widgets';
import { AppBackdrop } from '../components/Backdrop';
import { StoreView, WebHolder } from '../views/StoreView';
import { LegalPage, LegalText, LicensesPage } from './MiscPages';
import { LogPage } from './LogPage';
import { ManagePage } from './ManagePage';
import { APP_NAME } from '../common/AppInfo';
import { DISCLAIMER_LINES, DISCLAIMER_LINES_EN } from '../common/LegalText';
import { isEn } from '../common/I18n';

@Entry
@ComponentV2
struct Index {
  private store: Store = Store.get();
  @Local srv: Server = Server.get();
  @Local mute: boolean = false;

  onBackPress(): boolean | void {
    if (this.store.nav.size() !== 0 || !this.store.consented) {
      return false;
    }
    // back inside the Sub-Store web UI first
    return WebHolder.back();
  }

  @Builder
  routes(name: string, param: Object) {
    if (name === 'manage') {
      ManagePage()
    } else if (name === 'legal') {
      LegalPage()
    } else if (name === 'logs') {
      LogPage()
    } else if (name === 'licenses') {
      LicensesPage()
    }
  }

  // ------------------------------------------------------------------ first launch

  @Builder
  link(text: string, doc: string) {
    Text(text).fontSize(13).fontColor(this.store.palette().accent)
      .onClick(() => {
        this.store.push('legal', doc);
      })
  }

  @Builder
  consent() {
    Column() {
      Scroll() {
        Column({ space: 18 }) {
          Image($r('app.media.startIcon')).width(88).height(88).borderRadius(22).margin({ top: 40 })
          Text(APP_NAME).fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.store.palette().text)
          Text(t('Sub-Store 第三方鸿蒙客户端（非官方）：后端和管理界面都运行在本机，可转换 Surge、Loon、QX、Stash、Clash、sing-box 等订阅格式。'))
            .fontSize(15)
            .lineHeight(23)
            .fontColor(this.store.palette().subtle)
            .textAlign(TextAlign.Center)
          Column({ space: 14 }) {
            this.point($r('sys.symbol.lock'), t('无需注册，数据只在本机'), t('没有账号，不含任何统计、广告或推送 SDK；订阅与设置只保存在这台设备上'))
            this.point($r('sys.symbol.dot_radiowaves_left_and_right'), t('默认仅本机访问'), t('服务只监听 127.0.0.1；开启局域网访问后，其他设备也只能下载订阅链接'))
            this.point($r('sys.symbol.checkmark_shield'), t('仅为本地工具，请合法使用'), t('本应用不提供任何代理、VPN 或节点服务；节点与订阅来源由你自行负责，请遵守中华人民共和国及所在地法律法规，不得用于任何违法用途'))
            this.point($r('sys.symbol.info_circle'), t('由 AI 开发的开源软件'), t('本应用由 AI（Hark Agent）开发，以 AGPL-3.0 开源，按“现状”提供、不作任何担保'))
          }
          .padding(16)
          .backgroundColor(this.store.palette().card)
          .borderRadius(12)

          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
            Text(t('请阅读并同意')).fontSize(13).fontColor(this.store.palette().tertiary)
            this.link(t('《免责声明与隐私说明》'), 'disclaimer')
            this.link(t('《隐私政策》'), 'privacy')
            Text(t('与')).fontSize(13).fontColor(this.store.palette().tertiary)
            this.link(t('《用户协议》'), 'terms')
          }
          .width('100%')
        }
        .padding({ left: 24, right: 24 })
        .constraintSize({ maxWidth: 520 })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })

      Row({ space: 12 }) {
        ActionButton({
          text: t('不同意'), filled: false, fullWidth: true, onTap: () => {
            this.store.ctx?.terminateSelf();
          }
        }).layoutWeight(1)
        ActionButton({
          text: t('同意并继续'), fullWidth: true, onTap: () => {
            this.store.acceptPrivacy();
            if (this.store.autoStart && !this.srv.running && this.store.coreProblem !== 'missing') {
              this.srv.start();
            }
          }
        }).layoutWeight(1)
      }
      .padding({ left: 24, right: 24, top: 12, bottom: this.store.safeBottom + 16 })
      .constraintSize({ maxWidth: 520 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.store.backdropOn() ? '#00000000' : this.store.palette().bg)
    .padding({ top: this.store.safeTop })
  }

  @Builder
  point(icon: Resource, title: string, desc: string) {
    Row({ space: 12 }) {
      SymbolGlyph(icon).fontSize(22).fontColor([this.store.palette().accentUi])
      Column({ space: 2 }) {
        Text(title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.store.palette().text)
        Text(desc).fontSize(12).lineHeight(18).fontColor(this.store.palette().tertiary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
  }

  // ------------------------------------------------------------------ startup disclaimer

  @Builder
  disclaimer() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
      Column({ space: 14 }) {
        Text(t('免责声明与隐私说明')).fontSize(19).fontWeight(FontWeight.Bold).fontColor(this.store.palette().text)
        Scroll() {
          LegalText({ lines: (isEn() ? DISCLAIMER_LINES_EN : DISCLAIMER_LINES).slice(1) })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Auto)
        Row({ space: 8 }) {
          Checkbox()
            .select(this.mute)
            .selectedColor(this.store.palette().primary)
            .width(20)
            .height(20)
            .onChange((v: boolean) => {
              this.mute = v;
            })
          Text(t('不再提示（声明更新后会再次提示）'))
            .fontSize(13)
            .fontColor(this.store.palette().subtle)
            .layoutWeight(1)
            .onClick(() => {
              this.mute = !this.mute;
            })
        }
        .width('100%')
        Row({ space: 12 }) {
          ActionButton({
            text: t('退出'), filled: false, fullWidth: true, onTap: () => {
              this.store.ctx?.terminateSelf();
            }
          }).layoutWeight(1)
          ActionButton({
            text: t('我已阅读并同意'), fullWidth: true, onTap: () => {
              this.store.closeDisclaimer(this.mute);
            }
          }).layoutWeight(1)
        }
        .width('100%')
      }
      .width('88%')
      .height('76%')
      .constraintSize({ maxWidth: 520 })
      .padding(20)
      .backgroundColor(this.store.palette().card)
      .borderRadius(16)
    }
    .width('100%')
    .height('100%')
    .transition(TransitionEffect.OPACITY)
  }

  // ------------------------------------------------------------------ main

  /** Floating button above the web UI's own tab bar: opens 服务管理. The dot shows whether the service runs. */
  @Builder
  fab() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Stack() {
        // transparent, same grey as the Sub-Store web UI's inactive tab-bar icons (--lowest-text-color)
        SymbolGlyph($r('sys.symbol.gearshape')).fontSize(26).fontColor([this.store.palette().disabled])
      }
      .width(48)
      .height(48)
      .borderRadius(24)
      .backgroundColor(Color.Transparent)
      Row()
        .width(8)
        .height(8)
        .borderRadius(4)
        .margin({ top: 8, right: 8 })
        .backgroundColor(this.srv.running ? this.store.palette().good : this.store.palette().tertiary)
    }
    .width(48)
    .height(48)
    .accessibilityText(t('服务管理'))
    .position({ right: 14, bottom: this.store.safeBottom + 80 })
    .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.9 })
    .onClick(() => {
      this.store.push('manage', null);
    })
  }

  @Builder
  main() {
    Stack() {
      ForEach([this.store.epoch], (e: number) => {
        StoreView()
      }, (e: number) => 'epoch' + e)
      this.fab()
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Stack() {
      AppBackdrop()
      Navigation(this.store.nav) {
        Column() {
          if (!this.store.consented) {
            this.consent()
          } else {
            this.main()
          }
        }
        .width('100%')
        .height('100%')
      }
      .navDestination(this.routes)
      .hideTitleBar(true)
      .hideToolBar(true)
      .mode(NavigationMode.Stack)
      .width('100%')
      .height('100%')
      .backgroundColor(this.store.backdropOn() ? '#00000000' : this.store.palette().bg)
      .onAreaChange((o: Area, n: Area) => {
        const w = Number(n.width);
        if (!isNaN(w) && w > 0) {
          this.store.setWidth(w);
        }
      })
      if (this.store.consented && this.store.disclaimerOpen) {
        this.disclaimer()
      }
    }
    .width('100%')
    .height('100%')
  }
}
