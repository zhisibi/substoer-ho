/**
 * App access lock UI:
 *  - LockScreen: full-screen overlay on start / after the background timeout. With fingerprint on and usable it
 *    opens in fingerprint mode (one big button, system prompt shown once) with a 使用密码解锁 switch; password mode has
 *    the field + 解锁 + 忘记密码 (+ 使用指纹解锁). Lockout / not enrolled falls back to password only.
 *    忘记密码 → answer every security question → set a new password. Wrong attempts cool down (AppLock).
 *  - LockIntro: the one-time question after privacy consent (设置访问密码 / 跳过).
 *  - LockSetupPage (route 'lockSetup'): mode 'set' / 'first' (password + security questions), 'change' (current
 *    password → new password), 'questions' (current password → new questions).
 */
import { t, tf } from '../common/I18n';
import { Store } from '../common/Store';
import { AppLock, CHECK_BROKEN, CHECK_OK, CHECK_WAIT } from '../common/AppLock';
import { Bio, BioResult } from '../common/Biometric';
import {
  PRESET_QUESTIONS, QUESTION_COUNT, fmtWait, passwordProblem, questionsProblem
} from '../common/LockLogic';
import { ActionButton, Field, PageHeader } from '../components/Widgets';
import { pageBackdrop } from '../components/Backdrop';

@ComponentV2
export struct LockScreen {
  private store: Store = Store.get();
  private lock: AppLock = AppLock.get();
  /** pw | answers | newpw */
  @Local stage: string = 'pw';
  @Local pw: string = '';
  @Local pw2: string = '';
  @Local error: string = '';
  @Local busy: boolean = false;
  @Local questions: string[] = [];
  @Local answers: string[] = [];
  @Local now: number = Date.now();
  /** fp: only the big fingerprint button | pw: password field (only 'pw' when fingerprint is off / unusable) */
  @Local mode: string = 'pw';
  /** fingerprint is on and usable right now: offer the 指纹 / 密码 switch */
  @Local fpReady: boolean = false;
  /** short line under the fingerprint button / switch (failed, cancelled, locked out) */
  @Local bioHint: string = '';
  @Local bioBusy: boolean = false;
  @Local fpPressed: boolean = false;
  private timer: number = -1;
  private bioTried: boolean = false;

  aboutToAppear(): void {
    this.timer = setInterval(() => {
      this.now = Date.now();
    }, 1000);
    this.fpReady = this.lock.bioOn && Bio.available();
    this.mode = this.fpReady ? 'fp' : 'pw';
    if (this.lock.bioOn && !this.fpReady) {
      this.bioHint = Bio.unavailableText();
    }
    if (this.fpReady && !this.bioTried) {
      this.bioTried = true;
      setTimeout(() => {
        this.bio();
      }, 400);
    }
  }

  /** Switches between the fingerprint and password modes with a short fade; focuses the field in password mode. */
  switchMode(m: string): void {
    if (this.mode === m) {
      return;
    }
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
      this.mode = m;
    });
    this.error = '';
    if (m === 'pw') {
      setTimeout(() => {
        try {
          this.getUIContext().getFocusController().requestFocus('lockPw');
        } catch (e) {
          // field not laid out yet: the user can tap it
        }
      }, 260);
    } else {
      this.bioHint = '';
      setTimeout(() => {
        this.bio();
      }, 260);
    }
  }

  aboutToDisappear(): void {
    clearInterval(this.timer);
  }

  waitText(): string {
    const left = Math.max(0, this.lock.lockUntil - this.now);
    return left > 0 ? tf('尝试次数过多，请 {0} 后再试', fmtWait(left)) : '';
  }

  async unlock(): Promise<void> {
    if (this.busy || this.pw.length === 0) {
      return;
    }
    this.busy = true;
    try {
      const r = await this.lock.check(this.pw);
      if (r === CHECK_OK) {
        this.pw = '';
        this.error = '';
        this.lock.unlock();
      } else if (r === CHECK_WAIT) {
        this.error = this.waitText();
      } else if (r === CHECK_BROKEN) {
        this.error = t('无法读取密码记录，请使用“忘记密码”重新设置');
      } else {
        this.error = t('密码不正确');
      }
    } finally {
      this.busy = false;
    }
  }

  async bio(): Promise<void> {
    if (this.bioBusy) {
      return;
    }
    this.bioBusy = true;
    // Bio.authenticate always resolves
    const r: BioResult = await Bio.authenticate(t('解锁咪咪SubStore'));
    this.bioBusy = false;
    if (r.ok) {
      this.bioHint = '';
      this.lock.unlock();
    } else if (r.unusable) {
      // locked out / not enrolled: the password is the only way now
      this.fpReady = false;
      this.bioHint = r.message;
      this.switchMode('pw');
    } else if (r.toPassword) {
      this.bioHint = '';
      this.switchMode('pw');
    } else if (r.cancelled) {
      this.bioHint = this.mode === 'fp' ? t('已取消，轻触指纹图标重试') : '';
    } else {
      this.bioHint = r.message.length > 0 ? r.message : t('指纹验证失败，请重试');
    }
  }

  async forgot(): Promise<void> {
    const qs = await this.lock.questions();
    if (qs.length === 0) {
      this.error = t('没有设置密保问题，无法找回密码');
      return;
    }
    this.questions = qs;
    this.answers = qs.map(() => '');
    this.error = '';
    this.stage = 'answers';
  }

  async submitAnswers(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const r = await this.lock.checkAnswers(this.answers);
      if (r === CHECK_OK) {
        this.error = '';
        this.pw = '';
        this.pw2 = '';
        this.stage = 'newpw';
      } else if (r === CHECK_WAIT) {
        this.error = this.waitText();
      } else {
        this.error = t('密保答案不正确');
      }
    } finally {
      this.busy = false;
    }
  }

  async submitNew(): Promise<void> {
    const p = passwordProblem(this.pw, this.pw2);
    if (p.length > 0) {
      this.error = t(p);
      return;
    }
    this.busy = true;
    try {
      if (await this.lock.resetPassword(this.pw)) {
        this.store.toast(t('已重设访问密码'));
        this.pw = '';
        this.pw2 = '';
        this.stage = 'pw';
        this.lock.unlock();
      } else {
        this.error = t('保存失败');
      }
    } finally {
      this.busy = false;
    }
  }

  @Builder
  fpStage() {
    Column({ space: 14 }) {
      Stack() {
        Image($r('app.media.ic_fingerprint'))
          .width(48)
          .height(48)
          .fillColor(this.store.palette().accentUi)
          .draggable(false)
      }
      .width(88)
      .height(88)
      .borderRadius(44)
      .backgroundColor(this.fpPressed ? this.store.palette().accentSoft : this.store.palette().card)
      .border({ width: 2, color: this.store.palette().accentUi })
      .shadow({ radius: 16, color: this.store.palette().accentSoft, offsetY: 4 })
      .scale({ x: this.fpPressed ? 0.94 : 1, y: this.fpPressed ? 0.94 : 1 })
      .animation({ duration: 120, curve: Curve.EaseOut })
      .opacity(this.bioBusy ? 0.7 : 1)
      .accessibilityText(t('轻触使用指纹解锁'))
      .onTouch((e: TouchEvent) => {
        if (e.type === TouchType.Down) {
          this.fpPressed = true;
        } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
          this.fpPressed = false;
        }
      })
      .onClick(() => {
        this.bioHint = '';
        this.bio();
      })
      Text(t('轻触使用指纹解锁'))
        .fontSize(15)
        .fontColor(this.store.palette().text)
        .textAlign(TextAlign.Center)
      if (this.bioHint.length > 0) {
        Text(this.bioHint)
          .fontSize(12)
          .fontColor(this.store.palette().subtle)
          .textAlign(TextAlign.Center)
          .maxLines(3)
      }
      Text(t('使用密码解锁'))
        .fontSize(14)
        .fontColor(this.store.palette().accent)
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .margin({ top: 18 })
        .onClick(() => {
          this.switchMode('pw');
        })
    }
    .width('100%')
    .padding({ top: 24 })
    .alignItems(HorizontalAlign.Center)
    .transition(TransitionEffect.OPACITY.animation({ duration: 220 }))
  }

  @Builder
  pwStage() {
    Column({ space: 16 }) {
      Field({
        value: this.pw, placeholder: t('访问密码'), password: true, inputId: 'lockPw', error: this.error,
        onChange: (v: string) => {
          this.pw = v;
          this.error = '';
        }
      })
      if (this.waitText().length > 0) {
        Text(this.waitText()).fontSize(12).fontColor(this.store.palette().warn)
      }
      ActionButton({
        text: t('解锁'), busy: this.busy, fullWidth: true, onTap: () => {
          this.unlock();
        }
      })
      if (this.bioHint.length > 0) {
        Text(this.bioHint)
          .fontSize(12)
          .fontColor(this.store.palette().subtle)
          .textAlign(TextAlign.Center)
          .width('100%')
      }
      Row({ space: 8 }) {
        if (this.fpReady) {
          Row({ space: 6 }) {
            Image($r('app.media.ic_fingerprint'))
              .width(18)
              .height(18)
              .fillColor(this.store.palette().accentUi)
              .draggable(false)
            Text(t('使用指纹解锁')).fontSize(14).fontColor(this.store.palette().accent)
          }
          .padding(10)
          .accessibilityText(t('使用指纹解锁'))
          .onClick(() => {
            this.switchMode('fp');
          })
          Divider().vertical(true).height(14).color(this.store.palette().tertiary)
        }
        Text(t('忘记密码'))
          .fontSize(14)
          .fontColor(this.store.palette().accent)
          .padding(10)
          .onClick(() => {
            this.forgot();
          })
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .width('100%')
    }
    .width('100%')
    .transition(TransitionEffect.OPACITY.animation({ duration: 220 }))
  }

  @Builder
  answerStage() {
    Text(t('回答密保问题后可以重新设置访问密码。')).fontSize(13).fontColor(this.store.palette().subtle)
    ForEach(this.questions, (q: string, i: number) => {
      Field({
        label: q, value: this.answers[i] ?? '', placeholder: t('答案'), onChange: (v: string) => {
          const a = this.answers.slice();
          a[i] = v;
          this.answers = a;
          this.error = '';
        }
      })
    }, (q: string, i: number) => i + q)
    if (this.error.length > 0) {
      Text(this.error).fontSize(12).fontColor(this.store.palette().bad)
    }
    ActionButton({
      text: t('下一步'), busy: this.busy, fullWidth: true, onTap: () => {
        this.submitAnswers();
      }
    })
    Text(t('返回')).fontSize(14).fontColor(this.store.palette().accent).padding(10)
      .onClick(() => {
        this.stage = 'pw';
        this.error = '';
      })
  }

  @Builder
  newStage() {
    Field({
      label: t('新密码'), value: this.pw, password: true, hint: t('至少 4 个字符'), onChange: (v: string) => {
        this.pw = v;
        this.error = '';
      }
    })
    Field({
      label: t('再次输入'), value: this.pw2, password: true, error: this.error, onChange: (v: string) => {
        this.pw2 = v;
        this.error = '';
      }
    })
    ActionButton({
      text: t('保存并解锁'), busy: this.busy, fullWidth: true, onTap: () => {
        this.submitNew();
      }
    })
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Image($r('app.media.startIcon')).width(80).height(80).borderRadius(20).margin({ top: 72 })
        Text(this.stage === 'pw' ? t('咪咪SubStore 已锁定') : (this.stage === 'answers' ? t('忘记密码') : t('设置新密码')))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.store.palette().text)
        if (this.stage === 'pw' && this.mode === 'fp') {
          this.fpStage()
        } else if (this.stage === 'pw') {
          this.pwStage()
        } else if (this.stage === 'answers') {
          this.answerStage()
        } else {
          this.newStage()
        }
      }
      .width('100%')
      .padding({ left: 28, right: 28, bottom: this.store.safeBottom + 24 })
      .constraintSize({ maxWidth: 440 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .padding({ top: this.store.safeTop })
    .backgroundColor(this.store.palette().bg)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }
}

/** One-time question after privacy consent. */
@ComponentV2
export struct LockIntro {
  private store: Store = Store.get();

  build() {
    Column({ space: 18 }) {
      Image($r('app.media.ic_fingerprint')).width(64).height(64).fillColor(this.store.palette().accentUi)
        .margin({ top: 96 }).draggable(false)
      Text(t('设置访问密码？')).fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.store.palette().text)
      Text(t('打开咪咪SubStore 时需要输入密码，可以再开启指纹解锁。忘记密码时可通过密保问题重设。也可以跳过，之后在“设置 › 安全”中开启。'))
        .fontSize(14)
        .lineHeight(21)
        .fontColor(this.store.palette().subtle)
        .textAlign(TextAlign.Center)
      ActionButton({
        text: t('设置访问密码'), fullWidth: true, onTap: () => {
          this.store.push('lockSetup', 'first');
        }
      })
      ActionButton({
        text: t('跳过'), filled: false, fullWidth: true, onTap: () => {
          AppLock.get().skipSetup();
        }
      })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 28, right: 28, top: this.store.safeTop })
    .constraintSize({ maxWidth: 440 })
  }
}

/** Password / security question editor. */
@ComponentV2
export struct LockSetupPage {
  private store: Store = Store.get();
  private lock: AppLock = AppLock.get();
  /** first | set | change | questions */
  @Param mode: string = 'set';
  @Local cur: string = '';
  @Local pw: string = '';
  @Local pw2: string = '';
  /** per question: index into PRESET_QUESTIONS, or -1 = custom */
  @Local qIdx: number[] = [0, 1];
  @Local custom: string[] = ['', ''];
  @Local answers: string[] = ['', ''];
  @Local error: string = '';
  @Local busy: boolean = false;

  needCurrent(): boolean {
    return this.mode === 'change' || this.mode === 'questions';
  }

  needPassword(): boolean {
    return this.mode !== 'questions';
  }

  needQuestions(): boolean {
    return this.mode !== 'change';
  }

  questionText(i: number): string {
    const k = this.qIdx[i] ?? 0;
    return k >= 0 ? t(PRESET_QUESTIONS[k]) : (this.custom[i] ?? '').trim();
  }

  title(): string {
    if (this.mode === 'change') {
      return t('修改访问密码');
    }
    if (this.mode === 'questions') {
      return t('修改密保问题');
    }
    return t('设置访问密码');
  }

  async save(): Promise<void> {
    if (this.busy) {
      return;
    }
    if (this.needPassword()) {
      const p = passwordProblem(this.pw, this.pw2);
      if (p.length > 0) {
        this.error = t(p);
        return;
      }
    }
    const qs: string[] = [];
    for (let i = 0; i < QUESTION_COUNT; i++) {
      qs.push(this.questionText(i));
    }
    if (this.needQuestions()) {
      const p = questionsProblem(qs, this.answers);
      if (p.length > 0) {
        this.error = t(p);
        return;
      }
    }
    this.busy = true;
    try {
      if (this.needCurrent()) {
        const r = await this.lock.check(this.cur);
        if (r !== CHECK_OK) {
          this.error = r === CHECK_WAIT ? tf('尝试次数过多，请 {0} 后再试', fmtWait(this.lock.cooldownLeft())) :
          t('当前密码不正确');
          return;
        }
      }
      let ok = false;
      if (this.mode === 'change') {
        ok = await this.lock.changePassword(this.pw);
      } else if (this.mode === 'questions') {
        ok = await this.lock.changeQuestions(qs, this.answers);
      } else {
        ok = await this.lock.enable(this.pw, qs, this.answers);
      }
      if (!ok) {
        this.error = t('保存失败');
        return;
      }
      this.store.toast(this.mode === 'questions' ? t('已更新密保问题') : t('已设置访问密码'));
      this.store.pop();
    } finally {
      this.busy = false;
    }
  }

  @Builder
  questionMenu(i: number) {
    Menu() {
      ForEach(PRESET_QUESTIONS, (q: string, k: number) => {
        MenuItem({ content: t(q) })
          .onClick(() => {
            const a = this.qIdx.slice();
            a[i] = k;
            this.qIdx = a;
            this.error = '';
          })
      }, (q: string, k: number) => k + q)
      MenuItem({ content: t('自定义问题') })
        .onClick(() => {
          const a = this.qIdx.slice();
          a[i] = -1;
          this.qIdx = a;
          this.error = '';
        })
    }
  }

  @Builder
  questionBlock(i: number) {
    Column({ space: 8 }) {
      Text(tf('密保问题 {0}', i + 1)).fontSize(13).fontColor(this.store.palette().subtle).fontWeight(FontWeight.Medium)
      Row({ space: 8 }) {
        Text((this.qIdx[i] ?? 0) >= 0 ? this.questionText(i) : t('自定义问题'))
          .fontSize(15)
          .fontColor(this.store.palette().text)
          .layoutWeight(1)
          .maxLines(2)
        SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(16).fontColor([this.store.palette().subtle])
      }
      .width('100%')
      .height(44)
      .padding({ left: 12, right: 10 })
      .backgroundColor(this.store.palette().chip)
      .borderRadius(10)
      .bindMenu(this.questionMenu(i))
      if ((this.qIdx[i] ?? 0) < 0) {
        Field({
          value: this.custom[i] ?? '', placeholder: t('输入你的问题'), onChange: (v: string) => {
            const c = this.custom.slice();
            c[i] = v;
            this.custom = c;
            this.error = '';
          }
        })
      }
      Field({
        value: this.answers[i] ?? '', placeholder: t('答案'), onChange: (v: string) => {
          const a = this.answers.slice();
          a[i] = v;
          this.answers = a;
          this.error = '';
        }
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({
          title: this.title(), showBack: true, onBack: () => {
            this.store.pop();
          }
        })
        Scroll() {
          Column({ space: 16 }) {
            if (this.needCurrent()) {
              Field({
                label: t('当前密码'), value: this.cur, password: true, onChange: (v: string) => {
                  this.cur = v;
                  this.error = '';
                }
              })
            }
            if (this.needPassword()) {
              Field({
                label: this.mode === 'change' ? t('新密码') : t('访问密码'), value: this.pw, password: true,
                hint: t('至少 4 个字符'), onChange: (v: string) => {
                  this.pw = v;
                  this.error = '';
                }
              })
              Field({
                label: t('再次输入'), value: this.pw2, password: true, onChange: (v: string) => {
                  this.pw2 = v;
                  this.error = '';
                }
              })
            }
            if (this.needQuestions()) {
              Text(t('忘记密码时，回答全部密保问题即可重设密码。答案不区分大小写和首尾空格，只保存加盐哈希。'))
                .fontSize(12)
                .lineHeight(18)
                .fontColor(this.store.palette().subtle)
              ForEach([0, 1], (i: number) => {
                this.questionBlock(i)
              }, (i: number) => String(i) + (this.qIdx[i] ?? 0))
            }
            if (this.error.length > 0) {
              Text(this.error).fontSize(13).fontColor(this.store.palette().bad)
            }
            ActionButton({
              text: t('保存'), busy: this.busy, fullWidth: true, onTap: () => {
                this.save();
              }
            })
          }
          .padding(16)
          .margin({ left: 12, right: 12 })
          .backgroundColor(this.store.palette().card)
          .borderRadius(16)
          .constraintSize({ maxWidth: 600 })
        }
        .layoutWeight(1)
        .align(Alignment.Top)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
    }
    .hideTitleBar(true)
    .background(pageBackdrop)
  }
}
