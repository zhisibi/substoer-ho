/**
 * Root page: privacy consent on first launch, then straight to the main UI.
 * Phone: Sub-Store (the bundled web UI, landing tab) / 服务 / 设置. On the Sub-Store tab the web UI has its own
 * bottom bar, so ours shrinks to a small floating button above it; on the other tabs the floating pill bar shows.
 * Tablet / 2in1: side rail. Legal pages, licenses and the lock setup are NavDestinations.
 */
import { t, tf } from '../common/I18n';
import { BAR_GAP, BAR_H, BAR_PILL_H, BAR_TAB_W, PHONE_TABS, SECTIONS, SectionDef, Store, sectionOf } from '../common/Store';
import { Server } from '../common/Server';
import { AppBackdrop } from '../components/Backdrop';
import { ActionButton, HEADER_H } from '../components/Widgets';
import { StoreView, WebHolder } from '../views/StoreView';
import { ServerView } from '../views/ServerView';
import { SettingsView } from '../views/SettingsView';
import { LegalPage, LicensesPage } from './MiscPages';
import { LogPage } from './LogPage';
import { UpdatePage } from './UpdatePage';
import { LockIntro, LockScreen, LockSetupPage } from './LockPages';
import { AppLock } from '../common/AppLock';

@Entry
@ComponentV2
struct Index {
  private store: Store = Store.get();

  private srv: Server = Server.get();
  private lock: AppLock = AppLock.get();

  onBackPress(): boolean | void {
    if (this.store.nav.size() !== 0 || !this.store.consented) {
      return false;
    }
    if (this.store.section === 'store') {
      // back inside the Sub-Store web UI first
      return WebHolder.back();
    }
    this.store.section = 'store';
    return true;
  }


  @Builder
  routes(name: string, param: Object) {
    if (name === 'legal') {
      LegalPage({ doc: typeof param === 'string' ? param as string : 'privacy' })
    } else if (name === 'ssUpdate') {
      UpdatePage()
    } else if (name === 'logs') {
      LogPage()
    } else if (name === 'licenses') {
      LicensesPage()
    } else if (name === 'lockSetup') {
      LockSetupPage({ mode: typeof param === 'string' ? param as string : 'set' })
    }
  }

  @Builder
  consent() {
    Column() {
      Scroll() {
        Column({ space: 18 }) {
          Image($r('app.media.startIcon')).width(96).height(96).borderRadius(24).margin({ top: 40 })
          Text(t('欢迎使用咪咪SubStore')).fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.store.palette().text)
          Text(t('开源订阅管理工具 Sub-Store 的鸿蒙客户端：后端和管理界面都运行在本机，可转换 Surge、Loon、QX、Stash、Clash、sing-box 等订阅格式。'))
            .fontSize(15)
            .lineHeight(23)
            .fontColor(this.store.palette().subtle)
            .textAlign(TextAlign.Center)
          Column({ space: 10 }) {
            this.point($r('sys.symbol.lock'), t('无需注册，数据只在本机'), t('没有账号，不含任何统计、广告或推送 SDK；订阅与设置只保存在这台设备上'))
            this.point($r('sys.symbol.arrow_down_circle'), t('只连接你添加的地址'), t('仅在拉取你添加的远程订阅、脚本或你配置的同步服务时联网，不经过开发者的服务器'))
            this.point($r('sys.symbol.dot_radiowaves_left_and_right'), t('默认仅本机访问'), t('服务只监听 127.0.0.1；开启局域网访问后，其他设备也只能下载订阅链接'))
            this.point($r('sys.symbol.checkmark_shield'), t('仅为本地工具，请合法使用'), t('本应用不提供任何代理、VPN 或节点服务；节点与订阅来源由你自行负责，请遵守中华人民共和国及所在地法律法规，不得用于任何违法用途'))
          }
          .padding(16)
          .backgroundColor(this.store.palette().card)
          .borderRadius(18)

          Row() {
            Text(t('请阅读并同意')).fontSize(13).fontColor(this.store.palette().subtle)
            Text(t('《用户协议》')).fontSize(13).fontColor(this.store.palette().accent)
              .onClick(() => {
                this.store.push('legal', 'agreement');
              })
            Text(t('和')).fontSize(13).fontColor(this.store.palette().subtle)
            Text(t('《隐私政策》')).fontSize(13).fontColor(this.store.palette().accent)
              .onClick(() => {
                this.store.push('legal', 'privacy');
              })
          }
          .justifyContent(FlexAlign.Center)
        }
        .padding({ left: 24, right: 24 })
        .constraintSize({ maxWidth: 520 })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })

      Row({ space: 12 }) {
        ActionButton({
          text: t('不同意'), filled: false, onTap: () => {
            this.store.ctx?.terminateSelf();
          }
        }).layoutWeight(1)
        ActionButton({
          text: t('同意并继续'), fullWidth: true, onTap: () => {
            this.store.acceptPrivacy();
          }
        }).layoutWeight(1)
      }
      .padding({ left: 24, right: 24, top: 12, bottom: this.store.safeBottom + 16 })
      .constraintSize({ maxWidth: 520 })
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.store.safeTop })
  }

  @Builder
  point(icon: Resource, title: string, desc: string) {
    Row({ space: 12 }) {
      SymbolGlyph(icon).fontSize(22).fontColor([this.store.palette().accentUi])
      Column({ space: 2 }) {
        Text(title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.store.palette().text)
        Text(desc).fontSize(12).lineHeight(18).fontColor(this.store.palette().subtle)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
  }


  @Builder
  sectionContent(key: string) {
    if (key === 'server') {
      ServerView()
    } else if (key === 'settings') {
      SettingsView()
    } else {
      StoreView()
    }
  }

  @Builder
  rail() {
    Column({ space: 4 }) {
      Row({ space: 10 }) {
        Image($r('app.media.startIcon')).width(34).height(34).borderRadius(10)
        if (this.store.bp === 'lg') {
          Column() {
            Text(t('咪咪SubStore')).fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.store.palette().text)
            Text(this.srv.running ? tf('服务运行中 · 端口 {0}', this.store.port) : t('服务未运行')).fontSize(11).fontColor(this.store.palette().subtle)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
      }
      .height(HEADER_H)
      .padding({ left: this.store.bp === 'lg' ? 14 : 0 })
      .justifyContent(this.store.bp === 'lg' ? FlexAlign.Start : FlexAlign.Center)
      .width('100%')
      .margin({ bottom: 6 })

      Scroll() {
        Column({ space: 2 }) {
          ForEach(SECTIONS, (s: SectionDef) => {
            this.railItem(s)
          }, (s: SectionDef) => s.key)
        }
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width(this.store.bp === 'lg' ? 200 : 76)
    .height('100%')
    .padding({ top: this.store.safeTop + 4, bottom: this.store.safeBottom + 8, left: 8, right: 8 })
    .backgroundColor(this.store.barColor())
    .backdropBlur(this.store.blurPx())
  }

  @Builder
  railItem(s: SectionDef) {
    if (this.store.bp === 'lg') {
      Row({ space: 12 }) {
        SymbolGlyph(s.icon)
          .fontSize(19)
          .fontColor([this.store.section === s.key ? this.store.palette().accentUi : this.store.palette().subtle])
        Text(t(s.title))
          .fontSize(15)
          .fontWeight(this.store.section === s.key ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.store.section === s.key ? this.store.palette().accent : this.store.palette().text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .height(42)
      .padding({ left: 14, right: 8 })
      .borderRadius(12)
      .backgroundColor(this.store.section === s.key ? this.store.palette().accentSoft : Color.Transparent)
      .onClick(() => {
        this.store.section = s.key;
      })
    } else {
      Column({ space: 2 }) {
        SymbolGlyph(s.icon)
          .fontSize(19)
          .fontColor([this.store.section === s.key ? this.store.palette().accentUi : this.store.palette().subtle])
        Text(t(s.short))
          .fontSize(10)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor(this.store.section === s.key ? this.store.palette().accent : this.store.palette().subtle)
      }
      .width('100%')
      .height(52)
      .justifyContent(FlexAlign.Center)
      .borderRadius(14)
      .backgroundColor(this.store.section === s.key ? this.store.palette().accentSoft : Color.Transparent)
      .accessibilityText(t(s.title))
      .onClick(() => {
        this.store.section = s.key;
      })
    }
  }

  tabTitle(key: string): string {
    return t(sectionOf(key).short);
  }

  tabIcon(key: string): Resource {
    return sectionOf(key).icon;
  }

  tabKeys(): string[] {
    return this.store.isWide() ? SECTIONS.map((s: SectionDef) => s.key) : PHONE_TABS;
  }

  currentTabIdx(): number {
    return Math.max(0, this.tabKeys().indexOf(this.store.section));
  }

  @Builder
  tabItem(k: string) {
    Column({ space: 2 }) {
      // no running badge on the 服务 tab (removed in 1.0.3 at the user's request; the power button shows the state)
      SymbolGlyph(this.tabIcon(k))
        .fontSize(20)
        .fontColor([this.store.section === k ? this.store.palette().accentUi : this.store.palette().subtle])
      Text(this.tabTitle(k))
        .fontSize(10)
        .maxLines(1)
        .fontWeight(this.store.section === k ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.store.section === k ? this.store.palette().accent : this.store.palette().subtle)
    }
    .layoutWeight(1)
    .height(BAR_PILL_H - 6)
    .justifyContent(FlexAlign.Center)
    .borderRadius((BAR_PILL_H - 6) / 2)
    .backgroundColor(this.store.section === k ? this.store.palette().accentSoft : Color.Transparent)
    .accessibilityText(this.tabTitle(k))
    .onClick(() => {
      this.store.section = k;
    })
  }

  /** Sub-Store tab: a small floating button above the web UI's own bottom bar opens 服务. */
  @Builder
  storeFab() {
    Stack() {
      SymbolGlyph($r('sys.symbol.dot_radiowaves_left_and_right')).fontSize(20).fontColor([this.store.palette().accentUi])
    }
    .width(44)
    .height(44)
    .borderRadius(22)
    .backgroundColor(this.store.barColor())
    .backdropBlur(this.store.blurPx())
    .border({ width: 0.5, color: this.store.palette().divider })
    .shadow({ radius: 12, color: this.store.isDark() ? '#66000000' : '#22000000', offsetY: 3 })
    .accessibilityText(t('服务与设置'))
    .position({ right: 14, bottom: this.store.safeBottom + 76 })
    .onClick(() => {
      this.store.section = 'server';
    })
  }

  @Builder
  bottomBar() {
    Stack({ alignContent: Alignment.BottomStart }) {
      if (this.store.barCollapsed) {
        Stack() {
          SymbolGlyph(this.tabIcon(this.store.section)).fontSize(22).fontColor([this.store.palette().accentUi])
        }
        .width(BAR_H)
        .height(BAR_H)
        .borderRadius(BAR_H / 2)
        .backgroundColor(this.store.barColor())
        .backdropBlur(this.store.blurPx())
        .border({ width: 0.5, color: this.store.palette().divider })
        .shadow({ radius: 16, color: this.store.isDark() ? '#66000000' : '#22000000', offsetY: 4 })
        .accessibilityText(t('展开导航栏'))
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.4, y: 0.4 })))
        .onClick(() => {
          this.store.setBarCollapsed(false);
        })
      } else {
        Row() {
        Row() {
          ForEach(PHONE_TABS, (k: string) => {
            this.tabItem(k)
          }, (k: string) => k)
        }
        .width(PHONE_TABS.length * BAR_TAB_W + 6)
        .height(BAR_PILL_H)
        .padding({ left: 3, right: 3 })
        .borderRadius(BAR_PILL_H / 2)
        .backgroundColor(this.store.barColor())
        .backdropBlur(this.store.blurPx())
        .border({ width: 0.5, color: this.store.palette().divider })
        .shadow({ radius: 18, color: this.store.isDark() ? '#66000000' : '#1F000000', offsetY: 4 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .hitTestBehavior(HitTestMode.Transparent)
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.15, y: 1, centerX: '0%' })))
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, bottom: this.store.safeBottom + BAR_GAP })
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  sectionTabs() {
    Tabs({ index: this.currentTabIdx() }) {
      ForEach(this.tabKeys(), (k: string) => {
        TabContent() {
          this.sectionContent(k)
        }
      }, (k: string) => k)
    }
    .barHeight(0)
    .scrollable(false)
    .animationDuration(260)
    .edgeEffect(EdgeEffect.None)
    .width('100%')
    .height('100%')
    .onChange((i: number) => {
      const keys = this.tabKeys();
      if (i >= 0 && i < keys.length && keys[i] !== this.store.section) {
        this.store.section = keys[i];
      }
      this.store.setBarCollapsed(false);
    })
  }

  @Builder
  main() {
    Row() {
      if (this.store.isWide()) {
        this.rail()
        Divider().vertical(true).color(this.store.palette().divider).strokeWidth(0.5)
      }
      Stack({ alignContent: Alignment.Bottom }) {
        ForEach([this.store.epoch], (e: number) => {
          Column() {
            this.sectionTabs()
          }
          .width('100%')
          .height('100%')
        }, (e: number) => 'epoch' + e + ':' + this.store.bp)
        if (!this.store.isWide()) {
          if (this.store.section === 'store') {
            this.storeFab()
          } else {
            this.bottomBar()
          }
        }
      }
      .layoutWeight(1)
      .height('100%')
      .parallelGesture(
        PanGesture({ direction: PanDirection.Vertical, distance: 8 })
          .onActionStart((ev: GestureEvent) => {
            this.store.onContentDrag(ev.offsetY, true);
          })
          .onActionUpdate((ev: GestureEvent) => {
            this.store.onContentDrag(ev.offsetY, false);
          })
      )
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Stack() {
      AppBackdrop()
      this.navigation()
      if (this.store.consented && this.lock.locked) {
        LockScreen()
          .width('100%')
          .height('100%')
          .transition(TransitionEffect.OPACITY)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  navigation() {
    Navigation(this.store.nav) {
      Column() {
        if (!this.store.consented) {
          this.consent()
        } else if (this.lock.needSetup && !this.lock.enabled) {
          LockIntro()
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
    .backgroundColor(Color.Transparent)
    .onAreaChange((o: Area, n: Area) => {
      const w = Number(n.width);
      if (!isNaN(w) && w > 0) {
        this.store.setWidth(w);
      }
    })
  }
}

