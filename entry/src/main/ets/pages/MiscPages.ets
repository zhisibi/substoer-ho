/** Legal pages (privacy policy, user agreement) and open-source licenses. */
import { isEn, t, tf } from '../common/I18n';
import { Store } from '../common/Store';
import {
  AGREEMENT_LINES, AGREEMENT_LINES_EN, LICENSES, LicenseInfo, PRIVACY_LINES, PRIVACY_LINES_EN
} from '../common/LegalText';
import { IconBtn, PageHeader } from '../components/Widgets';
import { pageBackdrop } from '../components/Backdrop';
import { PRIVACY_URL, PRIVACY_URL_EN, TERMS_URL, TERMS_URL_EN } from '../common/AppInfo';
import { FileUtil } from '../common/FileUtil';

function cells(l: string): string[] {
  return l.split('|').map((c: string) => c.trim()).filter((c: string) => c.length > 0);
}

/** Renders the small markdown subset used by docs/*.md: #, ##, -, | tables, paragraphs. */
@ComponentV2
export struct LegalText {
  private store: Store = Store.get();
  @Param lines: string[] = [];

  build() {
    Column() {
      ForEach(this.lines, (l: string) => {
        if (l.startsWith('# ')) {
          Text(l.substring(2))
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.store.palette().text)
            .margin({ bottom: 6 })
        } else if (l.startsWith('## ')) {
          Text(l.substring(3))
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.store.palette().text)
            .margin({ top: 12, bottom: 4 })
        } else if (l.startsWith('- ')) {
          Row() {
            Text('•').fontSize(14).fontColor(this.store.palette().subtle).width(14)
            Text(l.substring(2)).fontSize(14).lineHeight(22).fontColor(this.store.palette().text).layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
          .margin({ top: 2, bottom: 2 })
        } else if (l.startsWith('|')) {
          if (l.indexOf('---') < 0) {
            Row({ space: 8 }) {
              ForEach(cells(l), (c: string, i: number) => {
                Text(c)
                  .fontSize(13)
                  .lineHeight(19)
                  .fontColor(i === 0 ? this.store.palette().text : this.store.palette().subtle)
                  .layoutWeight(i === 0 ? 3 : 2)
              }, (c: string, i: number) => i + c)
            }
            .width('100%')
            .padding({ top: 6, bottom: 6, left: 10, right: 10 })
            .backgroundColor(this.store.palette().chip)
            .alignItems(VerticalAlign.Top)
          }
        } else if (l.length === 0) {
          Blank().height(6)
        } else {
          Text(l).fontSize(14).lineHeight(22).fontColor(this.store.palette().text).width('100%')
        }
      }, (l: string, i: number) => i + ':' + l)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

@ComponentV2
export struct LegalPage {
  private store: Store = Store.get();
  @Param doc: string = 'privacy';

  docUrl(): string {
    if (this.doc === 'agreement') {
      return isEn() ? TERMS_URL_EN : TERMS_URL;
    }
    return isEn() ? PRIVACY_URL_EN : PRIVACY_URL;
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({
          title: this.doc === 'agreement' ? t('用户协议') : t('隐私政策'), showBack: true, onBack: () => {
            this.store.pop();
          }
        })
        Scroll() {
          Column() {
            LegalText({
              lines: this.doc === 'agreement' ? (isEn() ? AGREEMENT_LINES_EN : AGREEMENT_LINES) :
                (isEn() ? PRIVACY_LINES_EN : PRIVACY_LINES)
            })
            Text(this.docUrl())
              .fontSize(12)
              .fontColor(this.store.palette().accent)
              .margin({ top: 16 })
              .onClick(() => {
                FileUtil.copyText(this.docUrl());
                this.store.toast(t('已复制链接'));
              })
          }
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 20, right: 20, top: 4, bottom: this.store.safeBottom + 24 })
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

@ComponentV2
export struct LicensesPage {
  private store: Store = Store.get();
  @Local open: string = '';

  @Builder
  item(l: LicenseInfo) {
    Column({ space: 6 }) {
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text(l.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.store.palette().text)
          Text(l.version + ' · ' + t(l.purpose)).fontSize(12).fontColor(this.store.palette().subtle)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text(l.license)
          .fontSize(11)
          .fontColor(this.store.palette().accent)
          .backgroundColor(this.store.palette().accentSoft)
          .borderRadius(6)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(16)
          .fontColor([this.store.palette().subtle])
          .rotate({ angle: this.open === l.name ? 180 : 0 })
      }
      .width('100%')

      if (this.open === l.name) {
        Text(l.text)
          .fontSize(12)
          .lineHeight(18)
          .fontFamily('monospace')
          .fontColor(this.store.palette().codeText)
          .backgroundColor(this.store.palette().codeBg)
          .borderRadius(10)
          .padding(12)
          .width('100%')
          .copyOption(CopyOptions.LocalDevice)
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.store.palette().card)
    .backdropBlur(this.store.blurPx())
    .borderRadius(16)
    .onClick(() => {
      this.open = this.open === l.name ? '' : l.name;
    })
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({
          title: t('开源许可'), showBack: true, onBack: () => {
            this.store.pop();
          }
        })
        Scroll() {
          Column({ space: 10 }) {
            Text(t('咪咪SubStore 使用了以下开源软件，在此向其作者致谢。点按查看许可证全文。'))
              .fontSize(13)
              .lineHeight(20)
              .fontColor(this.store.palette().subtle)
              .width('100%')
              .padding({ left: 4, right: 4 })
            ForEach(LICENSES, (l: LicenseInfo) => {
              this.item(l)
            }, (l: LicenseInfo) => l.name)
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
