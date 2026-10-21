/**
 * Biometric.ets — fingerprint unlock of the app access lock (@kit.UserAuthenticationKit, ACCESS_BIOMETRIC).
 * FINGERPRINT at ATL3 (ATL2 when the device only reaches that) with a random challenge. It only opens the lock: the
 * access password always works as the fallback and is required before fingerprint can be turned on.
 * (Same approach as 咪咪账本 Security.ets.)
 */
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { userAuth } from '@kit.UserAuthenticationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Log } from './Log';
import { t, tf } from './I18n';

function errCode(e: Object): number {
  const c = (e as BusinessError).code;
  return typeof c === 'number' ? c as number : -1;
}

function availCode(level: userAuth.AuthTrustLevel): number {
  try {
    userAuth.getAvailableStatus(userAuth.UserAuthType.FINGERPRINT, level);
    return 0;
  } catch (e) {
    return errCode(e as Object);
  }
}

/** Result of a fingerprint prompt. */
export class BioResult {
  ok: boolean = false;
  /** the user cancelled / chose the password: no message needed */
  cancelled: boolean = false;
  /** the user tapped 使用密码 in the system prompt */
  toPassword: boolean = false;
  /** fingerprint cannot be used now (locked out / not enrolled / unsupported): fall back to the password */
  unusable: boolean = false;
  message: string = '';
}

export class Bio {
  private static current: userAuth.UserAuthInstance | null = null;

  /** ATL3 when available, else ATL2, else null. */
  private static level(): userAuth.AuthTrustLevel | null {
    if (availCode(userAuth.AuthTrustLevel.ATL3) === 0) {
      return userAuth.AuthTrustLevel.ATL3;
    }
    if (availCode(userAuth.AuthTrustLevel.ATL2) === 0) {
      return userAuth.AuthTrustLevel.ATL2;
    }
    return null;
  }

  static available(): boolean {
    return Bio.level() !== null;
  }

  /** Why fingerprint cannot be used right now. */
  static unavailableText(): string {
    const c = availCode(userAuth.AuthTrustLevel.ATL2);
    if (c === userAuth.UserAuthResultCode.NOT_ENROLLED) {
      return t('还没有录入指纹，请先在系统设置中添加指纹');
    }
    if (c === 201) {
      return tf('没有使用指纹的权限（{0}）', c);
    }
    return tf('这台设备没有可用的指纹（{0}）', c);
  }

  /** Shows the system fingerprint prompt. Always resolves. */
  static authenticate(title: string): Promise<BioResult> {
    return new Promise<BioResult>((resolve: (r: BioResult) => void) => {
      const res = new BioResult();
      const level = Bio.level();
      if (level === null) {
        res.message = Bio.unavailableText();
        res.unusable = true;
        resolve(res);
        return;
      }
      let done = false;
      let timer = -1;
      let inst: userAuth.UserAuthInstance | null = null;
      const finish = (code: number) => {
        if (done) {
          return;
        }
        done = true;
        if (timer >= 0) {
          clearTimeout(timer);
        }
        if (inst !== null) {
          try {
            inst.off('result');
          } catch (e) {
            // ignore
          }
        }
        Bio.current = null;
        if (code === userAuth.UserAuthResultCode.SUCCESS) {
          res.ok = true;
        } else if (code === userAuth.UserAuthResultCode.CANCELED_FROM_WIDGET) {
          res.cancelled = true;
          res.toPassword = true;
        } else if (code === userAuth.UserAuthResultCode.CANCELED) {
          res.cancelled = true;
        } else if (code === userAuth.UserAuthResultCode.LOCKED) {
          res.unusable = true;
          res.message = t('尝试次数过多，指纹已暂时锁定，请使用访问密码');
        } else if (code === userAuth.UserAuthResultCode.NOT_ENROLLED ||
          code === userAuth.UserAuthResultCode.TYPE_NOT_SUPPORT ||
          code === userAuth.UserAuthResultCode.TRUST_LEVEL_NOT_SUPPORT) {
          res.unusable = true;
          res.message = Bio.unavailableText();
        } else {
          res.message = tf('指纹验证失败（{0}）', code);
        }
        resolve(res);
      };
      try {
        const param: userAuth.AuthParam = {
          challenge: cryptoFramework.createRandom().generateRandomSync(32).data,
          authType: [userAuth.UserAuthType.FINGERPRINT],
          authTrustLevel: level
        };
        const widget: userAuth.WidgetParam = { title: title, navigationButtonText: t('使用密码') };
        inst = userAuth.getUserAuthInstance(param, widget);
        Bio.current = inst;
        inst.on('result', {
          onResult: (r: userAuth.UserAuthResult) => {
            finish(r.result);
          }
        });
        timer = setTimeout(() => {
          try {
            inst?.cancel();
          } catch (e) {
            // ignore
          }
          finish(userAuth.UserAuthResultCode.TIMEOUT);
        }, 90000);
        inst.start();
      } catch (e) {
        Log.w('Bio', 'auth start failed ' + errCode(e as Object));
        finish(errCode(e as Object));
      }
    });
  }
}
