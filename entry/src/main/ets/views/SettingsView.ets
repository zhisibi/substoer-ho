/**
 * Settings: where Sub-Store's own backup lives, app lock, appearance (theme, accent, background, glow, glass),
 * language, data & privacy (wipe Sub-Store data, withdraw consent) and About (version, core, Sub-Store versions,
 * update check, developer, legal, licenses).
 * Server options live on the 服务 page.
 */
import { t, tf } from '../common/I18n';
import { Store } from '../common/Store';
import { AccentDef, BackdropDef, onColor } from '../common/Theme';
import { CardGroup, NavRow, PageHeader, Segmented, SwitchRow } from '../components/Widgets';
import { FileUtil } from '../common/FileUtil';
import { Log } from '../common/Log';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { CONTACT_EMAIL, DEVELOPER, versionName } from '../common/AppInfo';
import { Updater } from '../common/Updater';
import { CoreApi } from '../common/Core';
import { promptText } from '../components/InputDialog';
import { Server } from '../common/Server';
import { AppLock, CHECK_OK, CHECK_WAIT } from '../common/AppLock';
import { Bio, BioResult } from '../common/Biometric';
import { LOCK_DELAYS, fmtWait } from '../common/LockLogic';

const THEME_KEYS: string[] = ['system', 'light', 'dark'];
const THEME_NAMES: string[] = ['跟随系统', '浅色', '深色'];
const LANG_KEYS: string[] = ['system', 'zh', 'en'];
const GLASS_NAMES: string[] = ['轻薄', '标准', '浓厚'];

@ComponentV2
export struct SettingsView {
  // 全局 Store 单例：服务器列表、主题、语言、日志等设置都在这里
  private store: Store = Store.get();
  @Local srv: Server = Server.get();
  // 是否作为独立页面显示：影响返回按钮和底部留白
  @Param asPage: boolean = false;
  @Local backupBusy: boolean = false;

  /**
   * 删除一台已保存的服务器（确认后执行），保存的密码和令牌会一并删除。
   * @param s 要删除的服务器
   */
  async revoke(): Promise<void> {
    if (!await this.store.confirm(t('撤回隐私政策同意'),
      t('撤回后会停止服务并退出应用，下次打开时需要重新同意才能使用。Sub-Store 中的数据不会被删除，如需删除请使用“清除全部数据”或卸载应用。确定撤回吗？'), t('撤回'), true)) {
      return;
    }
    Server.get().shutdown();
    this.store.revokePrivacy();
  }

  /**
   * 服务器列表的一行：当前服务器显示实心对勾；副标题为地址 + 登录方式（Open API 或用户名）。
   * @param s 服务器
   * 点整行切换到该服务器；编辑按钮传 s.copy() 副本给编辑页，避免未保存的修改影响原对象。
   */
  @Builder
  accentSwatch(a: AccentDef) {
    Column({ space: 4 }) {
      Stack() {
        Column().width(34).height(34).borderRadius(17).backgroundColor(a.swatch)
        if (a.key === this.store.accentKey) {
          SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([onColor(a.swatch)])
        }
      }
      .width(44)
      .height(44)
      .borderRadius(22)
      .border({ width: a.key === this.store.accentKey ? 2 : 0, color: a.swatch })

      Text(t(a.name))
        .fontSize(11)
        .fontWeight(a.key === this.store.accentKey ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(a.key === this.store.accentKey ? this.store.palette().accent : this.store.palette().subtle)
    }
    .accessibilityText(t(a.name) + (a.key === this.store.accentKey ? t('，已选择') : ''))
    .onClick(() => {
      this.store.setAccent(a.key);
    })
  }

  /**
   * 从相册选一张图片作为自定义背景：复制到应用沙箱 filesDir/backdrop 下，再设为背景，
   * 成功后删除旧的背景图片文件，避免沙箱里堆积图片。读取失败时提示并记录错误日志。
   */
  /** Picks a picture from the gallery and copies it into the sandbox as the background */
  async pickImage(): Promise<void> {
    const ctx = this.store.ctx;
    if (ctx === null) {
      return;
    }
    try {
      const opts = new photoAccessHelper.PhotoSelectOptions();
      opts.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      opts.maxSelectNumber = 1;
      const res = await new photoAccessHelper.PhotoViewPicker().select(opts);
      if (res.photoUris.length === 0) {
        return;
      }
      const dir = ctx.filesDir + '/backdrop';
      FileUtil.ensureDir(dir);
      // A new name each time so the Image component does not show a cached picture
      const dest = dir + '/bg_' + Date.now() + '.img';
      FileUtil.copyUriTo(res.photoUris[0], dest);
      const old = this.store.bgImage;
      this.store.setBackdropImage(dest);
      if (old.length > 0 && old !== dest) {
        FileUtil.remove(old);
      }
      this.store.toast(t('已设置背景图片'));
    } catch (e) {
      Log.e('Settings', 'pick background failed', e as Object);
      this.store.toast(t('无法读取所选图片'));
    }
  }

  /**
   * 背景选择小卡片。
   * @param key 'none'（纯色）、'image'（自定义图片）或渐变背景的 key
   * @param name 显示名
   * @param colors 渐变的三个颜色节点（纯色/图片时传空数组）
   * 点「自定义图片」会打开相册选图；其它直接切换背景。
   */
  @Builder
  backdropTile(key: string, name: string, colors: string[]) {
    Column({ space: 4 }) {
      Stack() {
        if (key === 'none') {
          Column().width('100%').height('100%').backgroundColor(this.store.isDark() ? '#0F1417' : '#F3F6F8')
        } else if (key === 'image') {
          if (this.store.bgImage.length > 0) {
            Image('file://' + this.store.bgImage).width('100%').height('100%').objectFit(ImageFit.Cover)
          } else {
            Column().width('100%').height('100%').backgroundColor(this.store.palette().chip)
          }
          SymbolGlyph($r('sys.symbol.ohos_photo')).fontSize(20).fontColor([this.store.palette().subtle])
        } else {
          Column().width('100%').height('100%')
            .linearGradient({ angle: 160, colors: [[colors[0], 0], [colors[1], 0.55], [colors[2], 1]] })
        }
        if (this.store.bgKey === key) {
          SymbolGlyph($r('sys.symbol.checkmark_circle_fill')).fontSize(20).fontColor([this.store.palette().accentUi])
        }
      }
      .width(56)
      .height(76)
      .borderRadius(12)
      .clip(true)
      .border({
        width: this.store.bgKey === key ? 2 : 1,
        color: this.store.bgKey === key ? this.store.palette().accentUi : this.store.palette().outline
      })

      Text(name).fontSize(11).fontColor(this.store.palette().subtle).maxLines(1)
    }
    .margin({ right: 10, bottom: 8 })
    .accessibilityText(name + (this.store.bgKey === key ? t('，已选择') : ''))
    .onClick(() => {
      if (key === 'image') {
        this.pickImage();
      } else {
        this.store.setBackdrop(key);
      }
    })
  }

  // 外观分组折叠时的摘要：「主题模式 · 主题色名称」
  appearanceSummary(): string {
    const mode = t(THEME_NAMES[Math.max(0, THEME_KEYS.indexOf(this.store.themeMode))]);
    const accent = this.store.accents().find((a: AccentDef) => a.key === this.store.accentKey);
    return accent === undefined ? mode : mode + t(' · ') + t(accent.name);
  }

  // 语言分组折叠时的摘要：跟随系统 / 简体中文 / English
  langSummary(): string {
    const i = Math.max(0, LANG_KEYS.indexOf(this.store.langPref));
    return i === 0 ? t('跟随系统') : (i === 1 ? '简体中文' : 'English');
  }

  /**
   * 分组内的小标题。
   * @param text 标题文字
   */
  @Builder
  label(text: string) {
    Text(text).fontSize(14).fontColor(this.store.palette().text).width('100%')
  }

  /** 开关任务失败提醒；开启时请求通知权限，用户拒绝则保持关闭 */
  async wipe(): Promise<void> {
    if (!await this.store.confirm(t('清除全部数据'),
      t('将删除 Sub-Store 中的全部订阅、组合订阅、文件、同步配置和设置，订阅链接随之失效。此操作无法撤销，建议先在 Sub-Store 的“我的 → 手动管理”中备份。'), t('全部清除'), true)) {
      return;
    }
    await Server.get().wipe();
    this.store.toast(t('已清除'));
  }

  delayName(sec: number): string {
    return sec < 60 ? tf('{0} 秒', sec) : tf('{0} 分钟', sec / 60);
  }

  /** Asks for the current password; true when it matches. */
  async confirmPassword(title: string): Promise<boolean> {
    const lock = AppLock.get();
    const v = await promptText(title, t('当前密码'), '', t('请输入当前访问密码'), false, true);
    if (v === null) {
      return false;
    }
    const r = await lock.check(v);
    if (r === CHECK_OK) {
      return true;
    }
    this.store.toast(r === CHECK_WAIT ? tf('尝试次数过多，请 {0} 后再试', fmtWait(lock.cooldownLeft())) : t('密码不正确'));
    return false;
  }

  async removeLock(): Promise<void> {
    if (!await this.confirmPassword(t('关闭访问密码'))) {
      return;
    }
    AppLock.get().disable();
    this.store.toast(t('已关闭访问密码'));
  }

  async toggleBio(on: boolean): Promise<void> {
    const lock = AppLock.get();
    if (!on) {
      lock.setBio(false);
      return;
    }
    if (!Bio.available()) {
      this.store.toast(Bio.unavailableText());
      return;
    }
    const r: BioResult = await Bio.authenticate(t('开启指纹解锁'));
    if (r.ok) {
      lock.setBio(true);
      this.store.toast(t('已开启指纹解锁'));
    } else if (!r.cancelled && r.message.length > 0) {
      this.store.toast(r.message);
    }
  }

  build() {
    Column() {
      PageHeader({
        title: t('设置'), showBack: this.asPage, onBack: () => {
          this.store.pop();
        }
      })
      Scroll() {
        Column({ space: 16 }) {
          CardGroup({
            title: t('备份与恢复'), collapsible: true, icon: $r('sys.symbol.arrow_2_circlepath')
          }) {
            Text(t('Sub-Store 自带备份：在 Sub-Store 的“我的”页面，“手动管理”可备份到文件或从文件恢复，也可以配置 GitHub Gist 同步。'))
              .fontSize(13)
              .lineHeight(19)
              .fontColor(this.store.palette().subtle)
              .padding({ left: 16, right: 16, top: 14, bottom: 14 })
          }

          CardGroup({
            title: t('安全'), collapsible: true, icon: $r('sys.symbol.lock'),
            summary: AppLock.get().enabled ? (AppLock.get().bioOn ? t('密码 + 指纹') : t('已设置访问密码')) : t('未设置访问密码')
          }) {
            Text(t('打开应用时需要输入访问密码；忘记密码可回答密保问题重设。密码和答案只保存加盐哈希（PBKDF2），存放在系统 Asset Store 中。'))
              .fontSize(13)
              .lineHeight(19)
              .fontColor(this.store.palette().subtle)
              .padding({ left: 16, right: 16, top: 14, bottom: 6 })
            if (!AppLock.get().enabled) {
              NavRow({
                icon: $r('sys.symbol.lock'), title: t('设置访问密码'), onTap: () => {
                  this.store.push('lockSetup', 'set');
                }
              })
            } else {
              NavRow({
                icon: $r('sys.symbol.key'), title: t('修改访问密码'), onTap: () => {
                  this.store.push('lockSetup', 'change');
                }
              })
              NavRow({
                icon: $r('sys.symbol.questionmark_circle'), title: t('修改密保问题'), onTap: () => {
                  this.store.push('lockSetup', 'questions');
                }
              })
              SwitchRow({
                title: t('指纹解锁'), desc: t('锁屏时可用指纹解锁，密码始终可用'), on: AppLock.get().bioOn,
                onToggle: (v: boolean) => {
                  this.toggleBio(v);
                }
              })
              Column({ space: 10 }) {
                this.label(t('切到后台多久后重新锁定'))
                Segmented({
                  options: LOCK_DELAYS.map((s: number) => this.delayName(s)),
                  selected: Math.max(0, LOCK_DELAYS.indexOf(AppLock.get().delay)),
                  onPick: (i: number) => {
                    AppLock.get().setDelay(LOCK_DELAYS[i]);
                  }
                })
              }
              .padding({ left: 16, right: 16, top: 4, bottom: 14 })
              NavRow({
                icon: $r('sys.symbol.lock_open'), title: t('关闭访问密码'), danger: true, chevron: false, onTap: () => {
                  this.removeLock();
                }
              })
            }
          }

          CardGroup({
            title: t('外观'), collapsible: true, icon: $r('sys.symbol.paintpalette'), summary: this.appearanceSummary()
          }) {
            Column({ space: 14 }) {
              this.label(t('主题'))
              Segmented({
                options: THEME_NAMES.map((n: string) => t(n)),
                selected: Math.max(0, THEME_KEYS.indexOf(this.store.themeMode)),
                onPick: (i: number) => {
                  this.store.setThemeMode(THEME_KEYS[i]);
                }
              })
              this.label(t('主题色'))
              Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceAround }) {
                ForEach(this.store.accents(), (a: AccentDef) => {
                  this.accentSwatch(a)
                }, (a: AccentDef) => a.key)
              }
              .width('100%')

              this.label(t('背景'))
              Scroll() {
                Row() {
                  this.backdropTile('none', t('纯色'), [])
                  ForEach(this.store.backdrops(), (b: BackdropDef) => {
                    this.backdropTile(b.key, t(b.name), b.stops(this.store.isDark()))
                  }, (b: BackdropDef) => b.key + this.store.isDark())
                  this.backdropTile('image', t('自定义图片'), [])
                }
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .width('100%')
              .align(Alignment.Start)
            }
            .padding(16)

            SwitchRow({
              title: t('沉浸光感'), desc: t('页面顶部随主题色泛起柔和光晕，导航栏与卡片通透融入背景'), on: this.store.glow,
              onToggle: (v: boolean) => {
                this.store.setGlow(v);
              }
            })
            SwitchRow({
              title: t('毛玻璃效果'), desc: this.store.hasBackdrop() ? t('导航栏、侧边栏和卡片使用半透明模糊材质') : t('导航栏、侧边栏和卡片使用半透明模糊材质；搭配背景图片、渐变背景或沉浸光感效果更明显'), on: this.store.glass,
              onToggle: (v: boolean) => {
                this.store.setGlass(v);
              }
            })
            // 只有开启毛玻璃时才显示模糊强度选择
            if (this.store.glass) {
              Column({ space: 10 }) {
                this.label(t('模糊强度'))
                Segmented({
                  options: GLASS_NAMES.map((n: string) => t(n)),
                  selected: this.store.glassLevel,
                  onPick: (i: number) => {
                    this.store.setGlassLevel(i);
                  }
                })
              }
              .padding({ left: 16, right: 16, top: 4, bottom: 14 })
            }
          }

          CardGroup({
            title: t('语言 / Language'), collapsible: true, icon: $r('sys.symbol.translate'), summary: this.langSummary()
          }) {
            Column() {
              Segmented({
                options: [t('跟随系统'), '简体中文', 'English'],
                selected: Math.max(0, LANG_KEYS.indexOf(this.store.langPref)),
                onPick: (i: number) => {
                  this.store.setLang(LANG_KEYS[i]);
                }
              })
            }
            .padding(16)
          }

          CardGroup({
            title: t('数据与隐私'), collapsible: true, icon: $r('sys.symbol.shield_checkered'),
            summary: t('仅保存在本机')
          }) {
            Text(t('Sub-Store 的数据只保存在这台设备的应用沙箱里（系统对应用数据加密存储）。本应用没有账号，不收集任何数据；只有 Sub-Store 拉取你添加的远程订阅、脚本或你配置的同步服务时才会联网。'))
              .fontSize(13)
              .lineHeight(19)
              .fontColor(this.store.palette().subtle)
              .padding({ left: 16, right: 16, top: 14, bottom: 6 })
            NavRow({
              icon: $r('sys.symbol.trash'), title: t('清除全部数据'), danger: true, chevron: false, onTap: () => {
                this.wipe();
              }
            })
            NavRow({
              icon: $r('sys.symbol.xmark_circle'), title: t('撤回隐私政策同意'), danger: true, chevron: false, onTap: () => {
                this.revoke();
              }
            })
          }

          CardGroup({
            title: t('关于'), collapsible: true, icon: $r('sys.symbol.info_circle'), summary: versionName()
          }) {
            Row({ space: 14 }) {
              Image($r('app.media.startIcon')).width(52).height(52).borderRadius(14)
              Column({ space: 2 }) {
                Text(t('咪咪SubStore')).fontSize(17).fontWeight(FontWeight.Bold).fontColor(this.store.palette().text)
                Text(t('Sub-Store 鸿蒙客户端 · 本地运行')).fontSize(12).fontColor(this.store.palette().subtle)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 10 })
            NavRow({ icon: $r('sys.symbol.info_circle'), title: t('版本'), value: versionName(), chevron: false })
            NavRow({
              icon: $r('sys.symbol.wrench_and_screwdriver'), title: t('内核'),
              value: this.store.coreProblem === 'missing' ? t('内核缺失') : 'core ' + CoreApi.version(), danger: this.store.coreProblem.length > 0,
              chevron: this.store.coreProblem.length > 0, onTap: () => {
                this.store.warnCore();
              }
            })
            NavRow({
              icon: $r('sys.symbol.rectangle_stack'), title: 'Sub-Store',
              value: tf('后端 {0} · 前端 {1}', this.srv.backendVer.length > 0 ? this.srv.backendVer : CoreApi.backendVersion(),
                this.srv.frontendVer.length > 0 ? this.srv.frontendVer : CoreApi.frontendVersion()), onTap: () => {
                this.store.push('ssUpdate', null);
              }
            })
            NavRow({
              icon: $r('sys.symbol.arrow_clockwise'), title: t('Sub-Store 更新'), onTap: () => {
                this.store.push('ssUpdate', null);
              }
            })
            NavRow({
              icon: $r('sys.symbol.arrow_down_circle'), title: t('检查更新'), onTap: () => {
                Updater.check(this.store);
              }
            })
            NavRow({ icon: $r('sys.symbol.person'), title: t('开发者'), value: t(DEVELOPER), chevron: false })
            NavRow({
              icon: $r('sys.symbol.envelope'), title: t('联系邮箱'), value: CONTACT_EMAIL, onTap: () => {
                FileUtil.copyText(CONTACT_EMAIL);
                this.store.toast(t('已复制邮箱'));
              }
            })
            NavRow({
              icon: $r('sys.symbol.shield_checkered'), title: t('隐私政策'), onTap: () => {
                this.store.push('legal', 'privacy');
              }
            })
            NavRow({
              icon: $r('sys.symbol.doc_text'), title: t('用户协议'), onTap: () => {
                this.store.push('legal', 'agreement');
              }
            })
            NavRow({
              icon: $r('sys.symbol.list_bullet'), title: t('开源许可'), onTap: () => {
                this.store.push('licenses', null);
              }
            })
          }

          Text(t('本应用基于开源项目 Sub-Store（AGPL-3.0 / GPL-3.0），只在本机管理你自己的订阅，不提供任何代理服务器或节点。请遵守当地法律法规。'))
            .fontSize(12)
            .lineHeight(18)
            .fontColor(this.store.palette().subtle)
            .padding({ left: 8, right: 8 })
        }
        .padding({ left: 12, right: 12, top: 4, bottom: this.store.bottomPad(this.asPage) })
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
}
