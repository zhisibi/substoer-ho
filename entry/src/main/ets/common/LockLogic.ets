/**
 * LockLogic.ets — pure rules of the app access lock (no system APIs; unit-tested by scripts/test-logic.mjs).
 *
 *  - password rules, security-question presets and answer normalisation (answers are hashed after normalising, so
 *    "Beijing ", "beijing" and "ＢＥＩＪＩＮＧ" are the same answer);
 *  - wrong-attempt cool-down and the relock-after-background rule;
 *  - constant-time comparison of hex digests.
 */

/** Minimum password length. */
export const PW_MIN: number = 4;
export const PW_MAX: number = 64;

/** Seconds in the background before the lock comes back. */
export const LOCK_DELAYS: number[] = [30, 60, 300, 900];
export const LOCK_DELAY_DEFAULT: number = 60;

/** How many security questions are set (each answer can reset the password; all of them must be answered). */
export const QUESTION_COUNT: number = 2;

/** Preset security questions (Chinese source; render with t()). '' at the end = 自定义问题. */
export const PRESET_QUESTIONS: string[] = [
  '你出生的城市是？',
  '你小学的名字是？',
  '你第一只宠物的名字是？',
  '你母亲的名字是？',
  '你最喜欢的一本书是？',
  '你第一份工作所在的公司是？',
  '你最好的童年朋友叫什么？',
  '你最难忘的旅行目的地是？'
];

/** Problem with a new password ('' = ok); Chinese source strings, render with t(). */
export function passwordProblem(pw: string, confirm: string): string {
  if (pw.length < PW_MIN) {
    return '密码至少 4 个字符';
  }
  if (pw.length > PW_MAX) {
    return '密码最多 64 个字符';
  }
  if (pw.trim().length === 0) {
    return '密码不能只包含空格';
  }
  if (pw !== confirm) {
    return '两次输入的密码不一致';
  }
  return '';
}

/** Full-width ASCII → half-width, lower case, trimmed, inner whitespace collapsed. */
export function normalizeAnswer(s: string): string {
  let out = '';
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c >= 0xFF01 && c <= 0xFF5E) {
      out += String.fromCharCode(c - 0xFEE0);
    } else if (c === 0x3000) {
      out += ' ';
    } else {
      out += s.charAt(i);
    }
  }
  return out.trim().toLowerCase().replace(/\s+/g, ' ');
}

/** Problem with the questions + answers ('' = ok). */
export function questionsProblem(questions: string[], answers: string[]): string {
  if (questions.length < QUESTION_COUNT || answers.length < QUESTION_COUNT) {
    return '请设置全部密保问题';
  }
  for (let i = 0; i < questions.length; i++) {
    if (questions[i].trim().length === 0) {
      return '请填写密保问题';
    }
    if (normalizeAnswer(answers[i] ?? '').length < 2) {
      return '密保答案至少 2 个字符';
    }
    for (let j = 0; j < i; j++) {
      if (questions[j].trim() === questions[i].trim()) {
        return '请选择不同的密保问题';
      }
    }
  }
  return '';
}

/** Wrong password cool-down: none for the first 4 failures, then 30 s doubling per failure, at most 15 minutes. */
export function lockoutMs(failures: number): number {
  if (failures < 5) {
    return 0;
  }
  return Math.min(15 * 60000, 30000 * Math.pow(2, failures - 5));
}

/** After a stay in the background of at least delaySec seconds the app locks again. */
export function shouldRelock(backgroundAt: number, now: number, delaySec: number): boolean {
  if (backgroundAt <= 0) {
    return false;
  }
  return now - backgroundAt >= delaySec * 1000;
}

/** Constant-time comparison of two hex strings. */
export function sameHex(a: string, b: string): boolean {
  if (a.length !== b.length || a.length === 0) {
    return false;
  }
  let d = 0;
  for (let i = 0; i < a.length; i++) {
    d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return d === 0;
}

/** "m:ss" of a remaining cool-down. */
export function fmtWait(ms: number): string {
  const s = Math.ceil(ms / 1000);
  const m = Math.floor(s / 60);
  const r = s % 60;
  return m + ':' + (r < 10 ? '0' : '') + r;
}
