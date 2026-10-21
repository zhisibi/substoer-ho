/**
 * AppLock.ets — the optional app access lock.
 *
 *  - Password and security-question answers are never stored: only PBKDF2-HMAC-SHA256 (random 16-byte salt each,
 *    PW_ITER iterations) digests, kept in the system Asset Store through SecretStore (HUKS-encrypted file fallback)
 *    under "lock.v1" as JSON {v, iter, pw:{salt,hash}, qs:[{q,salt,hash}]}. Answers are normalised before hashing
 *    (LockLogic.normalizeAnswer). Preferences only hold flags: lockOn, lockAsked, bioOn, lockDelay, lockFails,
 *    lockUntil.
 *  - The lock shows on app start and after lockDelay seconds in the background. Wrong passwords / answers share one
 *    counter with a growing cool-down (LockLogic.lockoutMs) that survives restarts.
 *  - 忘记密码: all security questions answered → a new password (the questions stay).
 *  - Fingerprint (Biometric.ets) can be turned on once a password is set; it only opens the lock.
 */
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { Prefs } from './Prefs';
import { SecretStore } from './SecretStore';
import { Log } from './Log';
import { LOCK_DELAYS, LOCK_DELAY_DEFAULT, lockoutMs, normalizeAnswer, sameHex, shouldRelock } from './LockLogic';
import { JRec, parseRec } from './Json';

const KEY: string = 'lock.v1';
export const PW_ITER: number = 100000;

function hex(b: Uint8Array): string {
  let s = '';
  for (let i = 0; i < b.length; i++) {
    const h = b[i].toString(16);
    s += h.length < 2 ? '0' + h : h;
  }
  return s;
}

class Digest {
  salt: string = '';
  hash: string = '';
}

/** What a check answered. */
export const CHECK_OK: string = 'ok';
export const CHECK_WRONG: string = 'wrong';
/** cooling down after too many wrong attempts */
export const CHECK_WAIT: string = 'wait';
/** the stored record is missing / unreadable */
export const CHECK_BROKEN: string = 'broken';

@ObservedV2
export class AppLock {
  private static inst: AppLock | null = null;

  static get(): AppLock {
    if (AppLock.inst === null) {
      AppLock.inst = new AppLock();
    }
    return AppLock.inst;
  }

  /** a password is set */
  @Trace enabled: boolean = false;
  @Trace locked: boolean = false;
  /** first-run question (after privacy consent) not answered yet */
  @Trace needSetup: boolean = false;
  @Trace bioOn: boolean = false;
  @Trace delay: number = LOCK_DELAY_DEFAULT;
  @Trace lockUntil: number = 0;
  private failCount: number = 0;
  private backgroundAt: number = 0;
  private prefs: Prefs | null = null;
  /** set after the security questions were answered: allows one password reset */
  private resetAllowed: boolean = false;

  init(prefs: Prefs, filesDir: string): void {
    this.prefs = prefs;
    SecretStore.init(filesDir);
    this.enabled = prefs.bool('lockOn', false);
    this.bioOn = this.enabled && prefs.bool('bioOn', false);
    const d = prefs.num('lockDelay', LOCK_DELAY_DEFAULT);
    this.delay = LOCK_DELAYS.indexOf(d) >= 0 ? d : LOCK_DELAY_DEFAULT;
    this.failCount = prefs.num('lockFails', 0);
    this.lockUntil = prefs.num('lockUntil', 0);
    this.locked = this.enabled;
  }

  /** Called when privacy consent is (re)given: ask once whether to set a password. */
  afterConsent(): void {
    this.needSetup = !this.enabled && !(this.prefs?.bool('lockAsked', false) ?? false);
  }

  skipSetup(): void {
    this.prefs?.put('lockAsked', true);
    this.needSetup = false;
  }

  // ------------------------------------------------------------------ hashing / storage

  private static async derive(secret: string, saltB64: string, iter: number): Promise<string> {
    const kdf = cryptoFramework.createKdf('PBKDF2|SHA256');
    const spec: cryptoFramework.PBKDF2Spec = {
      algName: 'PBKDF2',
      password: secret,
      salt: new util.Base64Helper().decodeSync(saltB64),
      iterations: iter,
      keySize: 32
    };
    const out = await kdf.generateSecret(spec);
    return hex(out.data);
  }

  private static async digest(secret: string, iter: number): Promise<Digest> {
    const d = new Digest();
    d.salt = new util.Base64Helper().encodeToStringSync(cryptoFramework.createRandom().generateRandomSync(16).data);
    d.hash = await AppLock.derive(secret, d.salt, iter);
    return d;
  }

  private async record(): Promise<JRec | undefined> {
    await SecretStore.ready();
    const raw = SecretStore.get(KEY);
    return raw.length > 0 ? parseRec(raw) : undefined;
  }

  private static digestOf(o: Object | undefined): Digest {
    const d = new Digest();
    if (o !== undefined && o !== null && typeof o === 'object') {
      const r = o as JRec;
      d.salt = typeof r['salt'] === 'string' ? r['salt'] as string : '';
      d.hash = typeof r['hash'] === 'string' ? r['hash'] as string : '';
    }
    return d;
  }

  private static async matches(secret: string, d: Digest, iter: number): Promise<boolean> {
    if (d.salt.length === 0 || d.hash.length === 0) {
      return false;
    }
    try {
      return sameHex(await AppLock.derive(secret, d.salt, iter), d.hash);
    } catch (e) {
      Log.e('Lock', 'derive failed', e as Object);
      return false;
    }
  }

  /** The security questions currently set (text only). */
  async questions(): Promise<string[]> {
    const r = await this.record();
    const qs: Object | undefined = r !== undefined ? r['qs'] : undefined;
    if (!Array.isArray(qs)) {
      return [];
    }
    return (qs as Object[]).map((x: Object) => {
      const q: Object | undefined = (x as JRec)['q'];
      return typeof q === 'string' ? q as string : '';
    });
  }

  /** Builds and saves the record. pw '' keeps the current password digest; questions [] keeps the questions. */
  private async save(pw: string, questions: string[], answers: string[]): Promise<boolean> {
    const old = await this.record();
    const o: JRec = {};
    o['v'] = 1;
    o['iter'] = PW_ITER;
    if (pw.length > 0) {
      const d = await AppLock.digest(pw, PW_ITER);
      o['pw'] = { 'salt': d.salt, 'hash': d.hash } as JRec;
    } else if (old !== undefined && old['pw'] !== undefined) {
      o['pw'] = old['pw'];
      o['iter'] = old['iter'] ?? PW_ITER;
    } else {
      return false;
    }
    if (questions.length > 0) {
      const qs: JRec[] = [];
      for (let i = 0; i < questions.length; i++) {
        const d = await AppLock.digest(normalizeAnswer(answers[i] ?? ''), PW_ITER);
        qs.push({ 'q': questions[i].trim(), 'salt': d.salt, 'hash': d.hash, 'iter': PW_ITER });
      }
      o['qs'] = qs;
    } else if (old !== undefined && old['qs'] !== undefined) {
      o['qs'] = old['qs'];
    } else {
      return false;
    }
    const r = await SecretStore.put(KEY, JSON.stringify(o));
    if (!r.ok) {
      Log.e('Lock', 'save failed ' + r.detail);
    }
    return r.ok;
  }

  // ------------------------------------------------------------------ attempts

  /** Remaining cool-down in ms (0 = may try). */
  cooldownLeft(): number {
    return Math.max(0, this.lockUntil - Date.now());
  }

  private resetFails(): void {
    this.failCount = 0;
    this.lockUntil = 0;
    this.prefs?.put('lockFails', 0);
    this.prefs?.put('lockUntil', 0);
  }

  private fail(): void {
    this.failCount++;
    const wait = lockoutMs(this.failCount);
    this.lockUntil = wait > 0 ? Date.now() + wait : 0;
    this.prefs?.put('lockFails', this.failCount);
    this.prefs?.put('lockUntil', this.lockUntil);
  }

  /** Checks the password (counts failures). */
  async check(pw: string): Promise<string> {
    if (this.cooldownLeft() > 0) {
      return CHECK_WAIT;
    }
    const r = await this.record();
    if (r === undefined) {
      return CHECK_BROKEN;
    }
    const iter = typeof r['iter'] === 'number' ? r['iter'] as number : PW_ITER;
    if (await AppLock.matches(pw, AppLock.digestOf(r['pw']), iter)) {
      this.resetFails();
      return CHECK_OK;
    }
    this.fail();
    return this.cooldownLeft() > 0 ? CHECK_WAIT : CHECK_WRONG;
  }

  /** Checks every security answer (counts failures like the password); success allows one resetPassword(). */
  async checkAnswers(answers: string[]): Promise<string> {
    if (this.cooldownLeft() > 0) {
      return CHECK_WAIT;
    }
    const r = await this.record();
    const qs: Object | undefined = r !== undefined ? r['qs'] : undefined;
    if (!Array.isArray(qs) || (qs as Object[]).length === 0) {
      return CHECK_BROKEN;
    }
    const list = qs as Object[];
    let ok = answers.length === list.length;
    for (let i = 0; i < list.length && ok; i++) {
      const it = list[i] as JRec;
      const iter = typeof it['iter'] === 'number' ? it['iter'] as number : PW_ITER;
      ok = await AppLock.matches(normalizeAnswer(answers[i] ?? ''), AppLock.digestOf(it), iter);
    }
    if (ok) {
      this.resetFails();
      this.resetAllowed = true;
      return CHECK_OK;
    }
    this.fail();
    return this.cooldownLeft() > 0 ? CHECK_WAIT : CHECK_WRONG;
  }

  // ------------------------------------------------------------------ changes

  /** First password: password + questions. */
  async enable(pw: string, questions: string[], answers: string[]): Promise<boolean> {
    // a fresh record: drop anything left over
    SecretStore.remove(KEY);
    const o: JRec = {};
    o['v'] = 1;
    o['iter'] = PW_ITER;
    const d = await AppLock.digest(pw, PW_ITER);
    o['pw'] = { 'salt': d.salt, 'hash': d.hash } as JRec;
    const qs: JRec[] = [];
    for (let i = 0; i < questions.length; i++) {
      const a = await AppLock.digest(normalizeAnswer(answers[i] ?? ''), PW_ITER);
      qs.push({ 'q': questions[i].trim(), 'salt': a.salt, 'hash': a.hash, 'iter': PW_ITER });
    }
    o['qs'] = qs;
    const r = await SecretStore.put(KEY, JSON.stringify(o));
    if (!r.ok) {
      Log.e('Lock', 'enable failed ' + r.detail);
      return false;
    }
    this.enabled = true;
    this.locked = false;
    this.needSetup = false;
    this.prefs?.put('lockOn', true);
    this.prefs?.put('lockAsked', true);
    this.resetFails();
    return true;
  }

  /** New password after the current one was checked by the caller. */
  async changePassword(pw: string): Promise<boolean> {
    return this.save(pw, [], []);
  }

  /** New password after 忘记密码 (security answers checked just before). */
  async resetPassword(pw: string): Promise<boolean> {
    if (!this.resetAllowed) {
      return false;
    }
    const ok = await this.save(pw, [], []);
    if (ok) {
      this.resetAllowed = false;
      this.resetFails();
    }
    return ok;
  }

  async changeQuestions(questions: string[], answers: string[]): Promise<boolean> {
    return this.save('', questions, answers);
  }

  /** Removes the lock (caller checked the current password). */
  disable(): void {
    SecretStore.remove(KEY);
    this.prefs?.put('lockOn', false);
    this.prefs?.put('bioOn', false);
    this.enabled = false;
    this.bioOn = false;
    this.locked = false;
    this.resetFails();
  }

  setBio(on: boolean): void {
    this.bioOn = on && this.enabled;
    this.prefs?.put('bioOn', this.bioOn);
  }

  setDelay(sec: number): void {
    this.delay = LOCK_DELAYS.indexOf(sec) >= 0 ? sec : LOCK_DELAY_DEFAULT;
    this.prefs?.put('lockDelay', this.delay);
  }

  unlock(): void {
    this.locked = false;
    this.backgroundAt = 0;
    this.resetAllowed = false;
  }

  onBackground(): void {
    this.backgroundAt = Date.now();
  }

  onForeground(): void {
    if (this.enabled && !this.locked && shouldRelock(this.backgroundAt, Date.now(), this.delay)) {
      this.locked = true;
    }
    this.backgroundAt = 0;
  }
}
