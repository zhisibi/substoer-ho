/**
 * Secrets readable only by this app (咪咪SubStore: the access-lock record — salted password and answer hashes).
 * Key used: "lock.v1". (Copied from 咪咪SSH SecretStore.)
 *
 * Where a value lives (checked in this order on read; every save is read back and verified):
 *  1. memory  - this run's cache of every value read or saved (and secrets typed for this run only, putTemp)
 *  2. file    - <filesDir>/secrets/<key>.sec, AES-256-GCM with a non-exportable key generated in HUKS
 *               (alias mimisub_secret_aes_v1). Used only when the Asset Store refuses or loses a value.
 *  3. asset   - HarmonyOS Asset Store Kit. One SECRET holds at most 1024 bytes, so longer values (RSA keys are
 *               1.8-3.4 KB) are split into chunks "ms.<key>#0..n-1" with a small header in "ms.<key>".
 * Older single-alias Asset values ("ms.<key>", <= 1024 bytes) are read as before, so nothing has to migrate.
 */
import { asset } from '@kit.AssetStoreKit';
import { huks } from '@kit.UniversalKeystoreKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { Log } from './Log';

const ERR_NOT_FOUND: number = 24000002;
const ERR_DUPLICATED: number = 24000003;
/** Asset Store limit for one SECRET */
const ASSET_MAX: number = 1024;
const CHUNK: number = 960;
/** header of a chunked value: NUL + "MSCHUNK1:" + count + ":" + total bytes */
const CHUNK_MAGIC: string = '\u0000MSCHUNK1:';
const HUKS_ALIAS: string = 'mimisub_secret_aes_v1';
const FILE_MAGIC: string = 'MSF1';
/** own error codes (not from the system) */
export const ERR_VERIFY: number = -2;
export const ERR_NO_DIR: number = -3;
export const ERR_FORMAT: number = -4;

/** Outcome of a save. where: memory | asset | asset-chunks | file | removed | '' (failed). */
export class SecretResult {
  ok: boolean = true;
  code: number = 0;
  where: string = '';
  /** e.g. "Asset 24000009 · File 12000006" */
  detail: string = '';

  static okAt(where: string): SecretResult {
    const r = new SecretResult();
    r.where = where;
    return r;
  }

  static fail(code: number, detail: string): SecretResult {
    const r = new SecretResult();
    r.ok = false;
    r.code = code;
    r.detail = detail;
    return r;
  }
}

/** One line of the secure storage self-test. */
export class SelfTestLine {
  name: string = '';
  ok: boolean = false;
  code: number = 0;
  info: string = '';
}

function errCode(e: Object): number {
  const c = (e as BusinessError).code;
  return typeof c === 'number' ? c as number : -1;
}

export class SecretStore {
  private static enc: util.TextEncoder = new util.TextEncoder();
  private static memory: Map<string, string> = new Map<string, string>();
  private static dir: string = '';
  private static readyP: Promise<void> = Promise.resolve();
  private static huksOk: boolean = false;

  // ------------------------------------------------------------------ helpers

  private static bytes(s: string): Uint8Array {
    return SecretStore.enc.encodeInto(s);
  }

  private static text(b: Uint8Array): string {
    return util.TextDecoder.create('utf-8').decodeToString(b);
  }

  private static aliasMap(alias: string): asset.AssetMap {
    const q: asset.AssetMap = new Map();
    q.set(asset.Tag.ALIAS, SecretStore.bytes(alias));
    return q;
  }

  private static fileOf(key: string): string {
    return SecretStore.dir + '/' + key.replace(/[^A-Za-z0-9._-]/g, '_') + '.sec';
  }

  /** Call once at startup: loads the encrypted-file secrets into memory (get() stays synchronous). */
  static init(filesDir: string): void {
    SecretStore.dir = filesDir + '/secrets';
    SecretStore.readyP = SecretStore.loadFiles();
  }

  /** Resolves once file-backed secrets are loaded. Await before reading a secret right after launch. */
  static ready(): Promise<void> {
    return SecretStore.readyP;
  }

  private static async loadFiles(): Promise<void> {
    try {
      if (!fs.accessSync(SecretStore.dir)) {
        return;
      }
      for (const name of fs.listFileSync(SecretStore.dir)) {
        if (!name.endsWith('.sec')) {
          continue;
        }
        const key = name.substring(0, name.length - 4);
        try {
          const v = await SecretStore.fileRead(key);
          if (v.length > 0) {
            SecretStore.memory.set(key, v);
          }
        } catch (e) {
          Log.w('Secret', 'file secret unreadable: ' + key + ' code=' + errCode(e as Object));
        }
      }
    } catch (e) {
      Log.w('Secret', 'loadFiles failed code=' + errCode(e as Object));
    }
  }

  // ------------------------------------------------------------------ Asset Store

  /** Writes one alias (add, or update when it exists). Returns 0 or the error code. */
  private static assetWrite(alias: string, data: Uint8Array): number {
    const attr: asset.AssetMap = SecretStore.aliasMap(alias);
    attr.set(asset.Tag.SECRET, data);
    attr.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    try {
      asset.addSync(attr);
      return 0;
    } catch (e) {
      const code = errCode(e as Object);
      if (code !== ERR_DUPLICATED) {
        return code;
      }
    }
    try {
      const upd: asset.AssetMap = new Map();
      upd.set(asset.Tag.SECRET, data);
      asset.updateSync(SecretStore.aliasMap(alias), upd);
      return 0;
    } catch (e2) {
      return errCode(e2 as Object);
    }
  }

  /** Raw bytes of one alias; null when absent. Throws other errors. */
  private static assetReadRaw(alias: string): Uint8Array | null {
    const q = SecretStore.aliasMap(alias);
    q.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const res: asset.AssetMap[] = asset.querySync(q);
      if (res.length === 0) {
        return null;
      }
      const v = res[0].get(asset.Tag.SECRET);
      return v instanceof Uint8Array ? v as Uint8Array : null;
    } catch (e) {
      if (errCode(e as Object) === ERR_NOT_FOUND) {
        return null;
      }
      throw e as Error;
    }
  }

  private static assetRemoveRaw(alias: string): void {
    try {
      asset.removeSync(SecretStore.aliasMap(alias));
    } catch (e) {
      const code = errCode(e as Object);
      if (code !== ERR_NOT_FOUND) {
        Log.w('Secret', 'remove failed for ' + alias + ' code=' + code);
      }
    }
  }

  /** Number of chunks when "ms.<key>" holds a chunk header, else 0. */
  private static chunkCount(head: Uint8Array | null): number {
    if (head === null || head.length < CHUNK_MAGIC.length || head[0] !== 0) {
      return 0;
    }
    const s = SecretStore.text(head);
    if (!s.startsWith(CHUNK_MAGIC)) {
      return 0;
    }
    const n = Number(s.substring(CHUNK_MAGIC.length).split(':')[0]);
    return Number.isInteger(n) && n > 0 && n < 1000 ? n : 0;
  }

  /** Reads a value from the Asset Store (single alias or chunks); '' when absent. Throws on service errors. */
  private static assetRead(key: string): string {
    const head = SecretStore.assetReadRaw('ms.' + key);
    if (head === null) {
      return '';
    }
    const n = SecretStore.chunkCount(head);
    if (n === 0) {
      return SecretStore.text(head);
    }
    const parts: Uint8Array[] = [];
    let total = 0;
    for (let i = 0; i < n; i++) {
      const p = SecretStore.assetReadRaw('ms.' + key + '#' + i);
      if (p === null) {
        Log.w('Secret', 'missing chunk ' + i + ' of ' + key);
        return '';
      }
      parts.push(p);
      total += p.length;
    }
    const all = new Uint8Array(total);
    let off = 0;
    for (const p of parts) {
      all.set(p, off);
      off += p.length;
    }
    return SecretStore.text(all);
  }

  private static assetRemove(key: string): void {
    let n = 0;
    try {
      n = SecretStore.chunkCount(SecretStore.assetReadRaw('ms.' + key));
    } catch (e) {
      n = 0;
    }
    SecretStore.assetRemoveRaw('ms.' + key);
    for (let i = 0; i < n; i++) {
      SecretStore.assetRemoveRaw('ms.' + key + '#' + i);
    }
  }

  /** Saves into the Asset Store and reads it back. Returns 0 or an error code. */
  private static assetPut(key: string, value: string): number {
    const data = SecretStore.bytes(value);
    let oldN = 0;
    try {
      oldN = SecretStore.chunkCount(SecretStore.assetReadRaw('ms.' + key));
    } catch (e) {
      oldN = 0;
    }
    let newN = 0;
    if (data.length <= ASSET_MAX) {
      const c = SecretStore.assetWrite('ms.' + key, data);
      if (c !== 0) {
        return c;
      }
    } else {
      newN = Math.ceil(data.length / CHUNK);
      for (let i = 0; i < newN; i++) {
        const c = SecretStore.assetWrite('ms.' + key + '#' + i, data.slice(i * CHUNK, Math.min(data.length, (i + 1) * CHUNK)));
        if (c !== 0) {
          return c;
        }
      }
      const c = SecretStore.assetWrite('ms.' + key, SecretStore.bytes(CHUNK_MAGIC + newN + ':' + data.length));
      if (c !== 0) {
        return c;
      }
    }
    for (let i = newN; i < oldN; i++) {
      SecretStore.assetRemoveRaw('ms.' + key + '#' + i);
    }
    try {
      if (SecretStore.assetRead(key) !== value) {
        return ERR_VERIFY;
      }
    } catch (e) {
      return errCode(e as Object);
    }
    return 0;
  }

  // ------------------------------------------------------------------ encrypted file (HUKS AES-256-GCM)

  private static huksProps(purpose: number): huks.HuksParam[] {
    return [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: purpose },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
      { tag: huks.HuksTag.HUKS_TAG_DIGEST, value: huks.HuksKeyDigest.HUKS_DIGEST_NONE }
    ];
  }

  private static async ensureHuksKey(): Promise<void> {
    if (SecretStore.huksOk) {
      return;
    }
    let exists = false;
    try {
      exists = await huks.isKeyItemExist(HUKS_ALIAS, { properties: [] });
    } catch (e) {
      exists = false;
    }
    if (!exists) {
      const opts: huks.HuksOptions = {
        properties: SecretStore.huksProps(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT |
        huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT)
      };
      await huks.generateKeyItem(HUKS_ALIAS, opts);
    }
    SecretStore.huksOk = true;
  }

  private static async huksRun(props: huks.HuksParam[], data: Uint8Array): Promise<Uint8Array> {
    const opts: huks.HuksOptions = { properties: props, inData: data };
    const h: huks.HuksSessionHandle = await huks.initSession(HUKS_ALIAS, opts);
    try {
      const r: huks.HuksReturnResult = await huks.finishSession(h.handle, opts);
      return r.outData ?? new Uint8Array(0);
    } catch (e) {
      try {
        await huks.abortSession(h.handle, opts);
      } catch (e2) {
        // ignore
      }
      throw e as Error;
    }
  }

  private static async encrypt(key: string, plain: Uint8Array): Promise<Uint8Array> {
    await SecretStore.ensureHuksKey();
    const nonce = cryptoFramework.createRandom().generateRandomSync(12).data;
    const props = SecretStore.huksProps(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT);
    props.push({ tag: huks.HuksTag.HUKS_TAG_NONCE, value: nonce });
    props.push({ tag: huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA, value: SecretStore.bytes(key) });
    const ct = await SecretStore.huksRun(props, plain); // ciphertext || 16-byte tag
    const magic = SecretStore.bytes(FILE_MAGIC);
    const out = new Uint8Array(magic.length + nonce.length + ct.length);
    out.set(magic, 0);
    out.set(nonce, magic.length);
    out.set(ct, magic.length + nonce.length);
    return out;
  }

  private static async decrypt(key: string, blob: Uint8Array): Promise<Uint8Array> {
    const m = FILE_MAGIC.length;
    if (blob.length < m + 12 + 16 || SecretStore.text(blob.slice(0, m)) !== FILE_MAGIC) {
      throw Error('bad secret file');
    }
    await SecretStore.ensureHuksKey();
    const nonce = blob.slice(m, m + 12);
    const ct = blob.slice(m + 12);
    const props = SecretStore.huksProps(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT);
    props.push({ tag: huks.HuksTag.HUKS_TAG_NONCE, value: nonce });
    props.push({ tag: huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA, value: SecretStore.bytes(key) });
    props.push({ tag: huks.HuksTag.HUKS_TAG_AE_TAG, value: ct.slice(ct.length - 16) });
    return await SecretStore.huksRun(props, ct.slice(0, ct.length - 16));
  }

  private static async fileRead(key: string): Promise<string> {
    const p = SecretStore.fileOf(key);
    if (SecretStore.dir.length === 0 || !fs.accessSync(p)) {
      return '';
    }
    const f = fs.openSync(p, fs.OpenMode.READ_ONLY);
    let blob: Uint8Array;
    try {
      const size = fs.statSync(p).size;
      const buf = new ArrayBuffer(size);
      const n = fs.readSync(f.fd, buf);
      blob = new Uint8Array(buf, 0, n);
    } finally {
      fs.closeSync(f);
    }
    return SecretStore.text(await SecretStore.decrypt(key, blob));
  }

  /** Encrypts into a file and reads it back. Returns 0 or an error code. */
  private static async filePut(key: string, value: string): Promise<number> {
    if (SecretStore.dir.length === 0) {
      return ERR_NO_DIR;
    }
    try {
      if (!fs.accessSync(SecretStore.dir)) {
        fs.mkdirSync(SecretStore.dir);
      }
      const blob = await SecretStore.encrypt(key, SecretStore.bytes(value));
      const p = SecretStore.fileOf(key);
      const tmp = p + '.tmp';
      const f = fs.openSync(tmp, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(f.fd, blob.buffer.slice(blob.byteOffset, blob.byteOffset + blob.length));
        fs.fsyncSync(f.fd);
      } finally {
        fs.closeSync(f);
      }
      fs.renameSync(tmp, p);
      return (await SecretStore.fileRead(key)) === value ? 0 : ERR_VERIFY;
    } catch (e) {
      const c = errCode(e as Object);
      Log.w('Secret', 'file save failed for ' + key + ' code=' + c + ' ' + Log.describe(e as Object));
      return c === -1 ? ERR_FORMAT : c;
    }
  }

  private static fileRemove(key: string): void {
    try {
      const p = SecretStore.fileOf(key);
      if (SecretStore.dir.length > 0 && fs.accessSync(p)) {
        fs.unlinkSync(p);
      }
    } catch (e) {
      Log.w('Secret', 'file remove failed for ' + key + ' code=' + errCode(e as Object));
    }
  }

  // ------------------------------------------------------------------ public API

  /** Keep a secret in memory only, for this app run. */
  static putTemp(key: string, value: string): void {
    SecretStore.memory.set(key, value);
  }

  /**
   * Saves a secret: Asset Store first (chunked when > 1024 bytes), encrypted file when the Asset Store fails.
   * Every save is read back. An empty value removes the secret. Never throws.
   */
  static async put(key: string, value: string): Promise<SecretResult> {
    if (value.length === 0) {
      SecretStore.remove(key);
      return SecretResult.okAt('removed');
    }
    await SecretStore.readyP;
    const ac = SecretStore.assetPut(key, value);
    if (ac === 0) {
      SecretStore.fileRemove(key);
      SecretStore.memory.set(key, value);
      return SecretResult.okAt(SecretStore.bytes(value).length > ASSET_MAX ? 'asset-chunks' : 'asset');
    }
    Log.w('Secret', 'asset save failed for ' + key + ' code=' + ac + ', trying encrypted file');
    const fc = await SecretStore.filePut(key, value);
    if (fc === 0) {
      SecretStore.assetRemove(key);
      SecretStore.memory.set(key, value);
      return SecretResult.okAt('file');
    }
    Log.e('Secret', 'save failed for ' + key + ' asset=' + ac + ' file=' + fc);
    return SecretResult.fail(ac, 'Asset ' + ac + ' · File ' + fc);
  }

  static get(key: string): string {
    const m: string | undefined = SecretStore.memory.get(key);
    if (m !== undefined) {
      return m;
    }
    try {
      const v = SecretStore.assetRead(key);
      if (v.length > 0) {
        SecretStore.memory.set(key, v);
      }
      return v;
    } catch (e) {
      Log.w('Secret', 'query failed for ' + key + ' code=' + errCode(e as Object));
      return '';
    }
  }

  /** Reads straight from storage (file, then Asset Store), bypassing the memory cache. */
  static async getStored(key: string): Promise<string> {
    await SecretStore.readyP;
    try {
      const f = await SecretStore.fileRead(key);
      if (f.length > 0) {
        return f;
      }
    } catch (e) {
      Log.w('Secret', 'file read failed for ' + key + ' code=' + errCode(e as Object));
    }
    try {
      return SecretStore.assetRead(key);
    } catch (e) {
      return '';
    }
  }

  static has(key: string): boolean {
    return SecretStore.get(key).length > 0;
  }

  static remove(key: string): void {
    SecretStore.memory.delete(key);
    SecretStore.assetRemove(key);
    SecretStore.fileRemove(key);
  }

  /** Remove every secret this app saved (withdrawing consent / reset). */
  static removeAll(): void {
    SecretStore.memory.clear();
    try {
      const q: asset.AssetMap = new Map();
      asset.removeSync(q);
    } catch (e) {
      const code = errCode(e as Object);
      if (code !== ERR_NOT_FOUND) {
        Log.w('Secret', 'removeAll failed code=' + code);
      }
    }
    try {
      if (SecretStore.dir.length > 0 && fs.accessSync(SecretStore.dir)) {
        fs.rmdirSync(SecretStore.dir);
      }
    } catch (e) {
      Log.w('Secret', 'removeAll files failed code=' + errCode(e as Object));
    }
  }

  // ------------------------------------------------------------------ self-test

  private static testValue(len: number): string {
    const abc = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    const rnd = cryptoFramework.createRandom().generateRandomSync(len).data;
    let s = '';
    for (let i = 0; i < len; i++) {
      s += abc.charAt(rnd[i] % 64);
    }
    return s;
  }

  /**
   * Writes, reads back and deletes test secrets: a small Asset value, a ~3 KB chunked Asset value, a ~3 KB
   * encrypted-file value, and a ~3 KB value through the normal save path. Never touches real secrets.
   */
  static async selfTest(): Promise<SelfTestLine[]> {
    await SecretStore.readyP;
    const out: SelfTestLine[] = [];
    const stamp = String(Date.now());
    const line = (name: string, code: number, info: string): void => {
      const l = new SelfTestLine();
      l.name = name;
      l.code = code;
      l.ok = code === 0;
      l.info = info;
      out.push(l);
    };
    // 1. Asset Store, small
    const k1 = 'selftest.' + stamp + '.small';
    const v1 = SecretStore.testValue(200);
    let c = SecretStore.assetPut(k1, v1);
    SecretStore.assetRemove(k1);
    line('asset', c, '200 B');
    // 2. Asset Store, ~3 KB in chunks
    const k2 = 'selftest.' + stamp + '.chunks';
    const v2 = SecretStore.testValue(3000);
    c = SecretStore.assetPut(k2, v2);
    SecretStore.assetRemove(k2);
    line('asset-chunks', c, '3000 B');
    // 3. Encrypted file, ~3 KB
    const k3 = 'selftest.' + stamp + '.file';
    c = await SecretStore.filePut(k3, v2);
    SecretStore.fileRemove(k3);
    line('file', c, '3000 B');
    // 4. Normal save path, ~3 KB, read back uncached, then deleted
    const k4 = 'selftest.' + stamp + '.put';
    const r = await SecretStore.put(k4, v2);
    let back = '';
    if (r.ok) {
      SecretStore.memory.delete(k4);
      back = await SecretStore.getStored(k4);
    }
    SecretStore.remove(k4);
    const ok = r.ok && back === v2;
    line('put', ok ? 0 : (r.ok ? ERR_VERIFY : r.code), r.ok ? r.where : r.detail);
    return out;
  }
}
