/**
 * InviteGate （特别版）: shown on first run until a valid invite code is entered. Explains the deal in the
 * developer's own words, offers the MimiSSH store link and the developer QQ (tap to copy), shows this
 * install's 申请码 and verifies the returned 邀请码 offline (common/Invite).
 */
import { t } from '../common/I18n';
import { Store } from '../common/Store';
import { DEV_QQ, MIMISSH_STORE_URL } from '../common/AppInfo';
import { requestCode, verifyInvite } from '../common/Invite';
import { FileUtil } from '../common/FileUtil';
import { ActionButton } from '../components/Widgets';
import { AppBackdrop } from '../components/Backdrop';

@ComponentV2
export struct InviteGate {
  private store: Store = Store.get();
  @Local code: string = '';

  private openStore(): void {
    const ctx = this.store.ctx;
    if (ctx === null) {
      return;
    }
    ctx.openLink(MIMISSH_STORE_URL, { appLinkingOnly: false }).catch((): void => {
      FileUtil.copyText(MIMISSH_STORE_URL);
      this.store.toast(t('已复制咪咪SSH下载链接'));
    });
  }

  private submit(): void {
    if (verifyInvite(this.code, this.store.installId)) {
      this.store.toast(t('验证成功，感谢您的支持！'));
      this.store.unlock();
    } else {
      this.store.toast(t('邀请码不正确，请确认后重试'));
    }
  }

  build() {
    Stack() {
      AppBackdrop()
      Scroll() {
        Column({ space: 18 }) {
          Image($r('app.media.startIcon')).width(84).height(84).borderRadius(22).margin({ top: 28 })
          Text(t('咪咪SubStore 特别版')).fontSize(24).fontWeight(FontWeight.Bold)
            .fontColor(this.store.palette().text)
          Column({ space: 12 }) {
            Text(t('你好，我是本软件的开发者，一名残疾人开发者。开发和维护这款软件不易，需要您的支持：'))
              .fontSize(15).lineHeight(24).fontColor(this.store.palette().text).width('100%')
            Text(t('请点击下方按钮，下载安装并好评我的另一款作品《咪咪SSH》；然后联系开发者 QQ，把下面的本机申请码发给他，即可获得邀请码。把邀请码填入下方输入框，即可正常使用本软件。'))
              .fontSize(15).lineHeight(24).fontColor(this.store.palette().text).width('100%')
            Text(t('感谢您的理解与支持！')).fontSize(15).lineHeight(24)
              .fontColor(this.store.palette().text).width('100%')
          }
          .width('100%')
          .padding(18)
          .backgroundColor(this.store.palette().card)
          .borderRadius(18)
          .alignItems(HorizontalAlign.Start)

          ActionButton({
            text: t('去下载并好评咪咪SSH'), fullWidth: true, onTap: () => {
              this.openStore();
            }
          })

          Row({ space: 10 }) {
            Text(t('本机申请码')).fontSize(14).fontColor(this.store.palette().subtle)
            Text(requestCode(this.store.installId)).fontSize(19).fontWeight(FontWeight.Bold)
              .fontColor(this.store.palette().text)
              .fontFamily('monospace')
            Blank()
            Text(t('复制')).fontSize(14).fontColor(this.store.palette().accent)
              .onClick(() => {
                FileUtil.copyText(requestCode(this.store.installId));
                this.store.toast(t('已复制'));
              })
          }
          .width('100%')
          .padding({ left: 18, right: 18, top: 14, bottom: 14 })
          .backgroundColor(this.store.palette().card)
          .borderRadius(14)

          Row({ space: 10 }) {
            Text(t('开发者 QQ')).fontSize(14).fontColor(this.store.palette().subtle)
            Text(DEV_QQ).fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.store.palette().text)
            Blank()
            Text(t('复制')).fontSize(14).fontColor(this.store.palette().accent)
              .onClick(() => {
                FileUtil.copyText(DEV_QQ);
                this.store.toast(t('已复制'));
              })
          }
          .width('100%')
          .padding({ left: 18, right: 18, top: 14, bottom: 14 })
          .backgroundColor(this.store.palette().card)
          .borderRadius(14)

          TextInput({ placeholder: t('请输入邀请码（如 ABCD-1234）'), text: this.code })
            .height(54)
            .fontSize(17)
            .backgroundColor(this.store.palette().card)
            .borderRadius(14)
            .onChange((v: string) => {
              this.code = v;
            })
            .onSubmit(() => {
              this.submit();
            })
          ActionButton({
            text: t('验证并进入'), filled: this.code.trim().length > 0, fullWidth: true, onTap: () => {
              this.submit();
            }
          })
        }
        .padding({ left: 22, right: 22, top: this.store.safeTop + 12, bottom: this.store.safeBottom + 28 })
        .constraintSize({ maxWidth: 560 })
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.store.backdropOn() ? '#00000000' : this.store.palette().bg)
  }
}
