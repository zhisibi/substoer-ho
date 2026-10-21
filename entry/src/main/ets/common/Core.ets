/**
 * Core.ets — thin wrapper over libmimisubstore.so (Go core: embedded Sub-Store backend + HTTP server, + NAPI).
 * Every op is a JSON request {op, …} answered with JSON (see core/msc/api.go). A HAP built without the .so
 * (local build that skipped core/build-core.sh) still runs: calls return {"error":"core missing"}.
 */
import core from 'libmimisubstore.so';
import { JObj, jStr, parseJsonObj } from './Json';
import { Log } from './Log';

export class CoreApi {
  private static ver: JObj | null = null;

  private static versionObj(): JObj {
    if (CoreApi.ver === null) {
      let o: JObj | undefined = undefined;
      try {
        o = parseJsonObj(core.version());
      } catch (e) {
        Log.e('Core', 'libmimisubstore.so not loadable', e as Object);
      }
      CoreApi.ver = o !== undefined ? o : {};
    }
    return CoreApi.ver;
  }

  /** Core version ('' = core missing), e.g. 1.0.0 */
  static version(): string {
    return jStr(CoreApi.versionObj(), 'core');
  }

  static backendVersion(): string {
    return jStr(CoreApi.versionObj(), 'backend');
  }

  static frontendVersion(): string {
    return jStr(CoreApi.versionObj(), 'frontend');
  }

  static call(req: JObj): JObj {
    try {
      const o = parseJsonObj(core.call(JSON.stringify(req)));
      if (o !== undefined) {
        return o;
      }
    } catch (e) {
      Log.e('Core', 'call failed', e as Object);
    }
    const err: JObj = {};
    err['error'] = 'core missing';
    return err;
  }

  /** Same as call but returns arrays too (status list). */
  static callRaw(req: JObj): string {
    try {
      return core.call(JSON.stringify(req));
    } catch (e) {
      return '';
    }
  }

  static async callAsync(req: JObj): Promise<JObj> {
    try {
      const o = parseJsonObj(await core.callAsync(JSON.stringify(req)));
      if (o !== undefined) {
        return o;
      }
    } catch (e) {
      Log.e('Core', 'callAsync failed', e as Object);
    }
    const err: JObj = {};
    err['error'] = 'core missing';
    return err;
  }
}

export function req(op: string): JObj {
  const o: JObj = {};
  o['op'] = op;
  return o;
}
