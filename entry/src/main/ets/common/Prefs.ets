/** Plain (non-secret) settings and lists, stored with @kit.ArkData preferences. */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Log } from './Log';

export class Prefs {
  private sp: preferences.Preferences;

  constructor(ctx: common.Context) {
    const opts: preferences.Options = { name: 'substore-ho' };
    this.sp = preferences.getPreferencesSync(ctx, opts);
  }

  private raw(key: string, def: preferences.ValueType): preferences.ValueType {
    try {
      return this.sp.getSync(key, def);
    } catch (e) {
      Log.w('Prefs', 'get ' + key + ' failed');
      return def;
    }
  }

  str(key: string, def: string): string {
    const v = this.raw(key, def);
    return typeof v === 'string' ? v as string : def;
  }

  num(key: string, def: number): number {
    const v = this.raw(key, def);
    return typeof v === 'number' ? v as number : def;
  }

  bool(key: string, def: boolean): boolean {
    const v = this.raw(key, def);
    return typeof v === 'boolean' ? v as boolean : def;
  }

  put(key: string, v: string | number | boolean): void {
    try {
      this.sp.putSync(key, v);
      this.sp.flush().catch((e: Error) => {
        Log.w('Prefs', 'flush failed: ' + e.message);
      });
    } catch (e) {
      Log.e('Prefs', 'put ' + key + ' failed', e as Object);
    }
  }

  remove(key: string): void {
    try {
      this.sp.deleteSync(key);
      this.sp.flush().catch(() => {
      });
    } catch (e) {
      Log.w('Prefs', 'delete ' + key + ' failed');
    }
  }
}
