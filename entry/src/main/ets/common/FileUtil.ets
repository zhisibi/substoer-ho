/**
 * 文件说明：FileUtil.ets —— 文件、剪贴板与系统分享的工具函数。
 *
 * 职责：封装 @kit.CoreFileKit 的同步文件操作（存在判断、建目录、读写、删除、列目录、复制 URI），
 *       系统“另存为”文件选择器、剪贴板复制以及系统分享面板。
 * 主要类型：FileUtil（只含静态方法）。
 * 与其他模块的关系：CrashLog 用它读写崩溃日志；日志查看、脚本、背景图片等页面用它导出/分享/复制。
 * 约定：除 writeText / copyUriTo / saveTextAs / shareText 外，其余方法都吞掉异常并返回安全的默认值。
 */
import { t } from './I18n';
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { wantConstant } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';
import { pasteboard, BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';

/** File, clipboard and share helpers */
/**
 * 文件相关静态工具集合。
 */
export class FileUtil {
  /** Decodes standard base64 to UTF-8 text ('' for empty input). */
  /** Atomic replace (temp file → final name). */
  static rename(from: string, to: string): void {
    fileIo.renameSync(from, to);
  }

  static b64DecodeText(s: string): string {
    if (s.length === 0) {
      return '';
    }
    const b = new util.Base64Helper().decodeSync(s);
    return util.TextDecoder.create('utf-8').decodeToString(b);
  }

  /**
   * 判断路径是否存在。
   * @param path 沙箱内绝对路径
   * @returns 存在返回 true；出错时返回 false
   */
  static exists(path: string): boolean {
    try {
      return fileIo.accessSync(path);
    } catch (e) {
      return false;
    }
  }

  /**
   * 确保目录存在（递归创建），失败静默忽略。
   * @param path 目录绝对路径
   */
  static ensureDir(path: string): void {
    try {
      if (!fileIo.accessSync(path)) {
        fileIo.mkdirSync(path, true);
      }
    } catch (e) {
      // ignore
    }
  }

  /**
   * 以覆盖方式写入文本文件（不存在则创建，存在则截断）。
   * @param path 文件绝对路径
   * @param text 要写入的文本
   * 异常：打开或写入失败会抛出，由调用方处理；无论成功与否都会关闭文件描述符。
   */
  static writeText(path: string, text: string): void {
    const f = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(f.fd, text);
    } finally {
      fileIo.closeSync(f);
    }
  }

  /**
   * 读取整个文本文件。
   * @param path 文件绝对路径
   * @returns 文件内容；不存在或读取失败返回 ''
   */
  static readText(path: string): string {
    try {
      return fileIo.readTextSync(path);
    } catch (e) {
      return '';
    }
  }

  /**
   * 删除文件（存在时才删），失败静默忽略。
   * @param path 文件绝对路径
   */
  static remove(path: string): void {
    try {
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path);
      }
    } catch (e) {
      // ignore
    }
  }

  /**
   * 列出目录下的文件名（不递归）。
   * @param dir 目录绝对路径
   * @returns 文件名数组；目录不存在时返回空数组
   */
  static list(dir: string): string[] {
    try {
      return fileIo.listFileSync(dir);
    } catch (e) {
      return [];
    }
  }

  /** Copies a uri returned by a system picker into the sandbox */
  /**
   * 把系统选择器返回的 URI（如相册图片）复制到应用沙箱，例如自定义背景图片。
   * @param uri 选择器返回的文件 URI
   * @param dest 沙箱内目标路径
   * 异常：打开或复制失败会抛出。
   * 注意：选择器授予的 URI 权限是临时的，因此需要复制一份到沙箱才能长期使用。
   */
  static copyUriTo(uri: string, dest: string): void {
    const src = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    try {
      fileIo.copyFileSync(src.fd, dest);
    } finally {
      fileIo.closeSync(src);
    }
  }

  /** "Save as" through the system picker; returns the saved file name, or '' when cancelled */
  /**
   * 通过系统“另存为”选择器保存文本（如导出日志）。
   * @param ctx 上下文（用于创建 DocumentViewPicker）
   * @param name 建议的文件名
   * @param text 文件内容
   * @returns 保存成功返回文件名；用户取消返回 ''
   * 异常：选择器或写入失败会抛出。
   */
  static async saveTextAs(ctx: common.Context, name: string, text: string): Promise<string> {
    const opts = new picker.DocumentSaveOptions();
    opts.newFileNames = [name];
    // 只有日志 / 文本文件才限定后缀，其它（如导出的 envs.json）保持原文件名
    if (name.endsWith('.txt') || name.endsWith('.log')) {
      opts.fileSuffixChoices = [t('文本文件(.txt,.log)|.txt,.log')];
    }
    const p = new picker.DocumentViewPicker(ctx);
    const uris = await p.save(opts);
    if (uris === undefined || uris.length === 0) {
      return '';
    }
    const f = fileIo.openSync(uris[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(f.fd, text);
    } finally {
      fileIo.closeSync(f);
    }
    return name;
  }

  /**
   * 通过系统文件选择器选一个文本文件并读出内容（导入环境变量等）。
   * @param ctx 上下文
   * @returns 文件内容；用户取消返回 null
   * 异常：读取失败会抛出。
   */
  static async pickText(ctx: common.Context): Promise<string | null> {
    const opts = new picker.DocumentSelectOptions();
    opts.maxSelectNumber = 1;
    const p = new picker.DocumentViewPicker(ctx);
    const uris = await p.select(opts);
    if (uris === undefined || uris.length === 0) {
      return null;
    }
    // 选择器返回的是 file:// URI，readTextSync 不能直接读，需要先 open 再按大小读出
    const f = fileIo.openSync(uris[0], fileIo.OpenMode.READ_ONLY);
    try {
      const size = fileIo.statSync(f.fd).size;
      const buf = new ArrayBuffer(size);
      fileIo.readSync(f.fd, buf);
      return util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf));
    } finally {
      fileIo.closeSync(f);
    }
  }

  /**
   * 通过系统“另存为”选择器保存二进制数据（如面板数据备份）。
   * @param ctx 上下文
   * @param name 建议的文件名
   * @param data 文件内容
   * @returns 保存成功返回文件名；用户取消返回 ''
   */
  static async saveBytesAs(ctx: common.Context, name: string, data: ArrayBuffer): Promise<string> {
    const opts = new picker.DocumentSaveOptions();
    opts.newFileNames = [name];
    const p = new picker.DocumentViewPicker(ctx);
    const uris = await p.save(opts);
    if (uris === undefined || uris.length === 0) {
      return '';
    }
    const f = fileIo.openSync(uris[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(f.fd, data);
    } finally {
      fileIo.closeSync(f);
    }
    return name;
  }

  /**
   * 把纯文本复制到系统剪贴板。
   * @param text 要复制的文本
   * 注意：setData 是异步的，失败只打印错误，不提示用户。
   */
  static copyText(text: string): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).catch((e: BusinessError) => {
      console.error('pasteboard failed ' + e.code);
    });
  }

  /**
   * 调起系统分享面板分享一段纯文本。
   * @param ctx UIAbility 上下文（分享面板需要依附在 Ability 上）
   * @param title 分享标题
   * @param text 分享内容
   * 异常：分享面板拉起失败时 Promise 会 reject。
   */
  static async shareText(ctx: common.UIAbilityContext, title: string, text: string): Promise<void> {
    const rec: systemShare.SharedRecord = {
      utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
      content: text,
      title: title
    };
    const data = new systemShare.SharedData(rec);
    const controller = new systemShare.ShareController(data);
    await controller.show(ctx, {
      previewMode: systemShare.SharePreviewMode.DEFAULT,
      selectionMode: systemShare.SelectionMode.SINGLE
    });
  }

  /** Copies a local file into a document URI (from a save picker) in 1 MiB chunks. */
  static copyFileToUri(src: string, uri: string): void {
    const inF = fileIo.openSync(src, fileIo.OpenMode.READ_ONLY);
    const outF = fileIo.openSync(uri, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      const buf = new ArrayBuffer(1 << 20);
      let n = fileIo.readSync(inF.fd, buf);
      while (n > 0) {
        fileIo.writeSync(outF.fd, buf, { length: n });
        n = fileIo.readSync(inF.fd, buf);
      }
    } finally {
      fileIo.closeSync(inF);
      fileIo.closeSync(outF);
    }
  }

  /** Last path segment of a document URI, decoded */
  static nameFromUri(uri: string): string {
    const i = uri.lastIndexOf('/');
    const raw = i >= 0 ? uri.substring(i + 1) : uri;
    try {
      return decodeURIComponent(raw);
    } catch (e) {
      return raw;
    }
  }

  static async pickSaveUri(ctx: common.Context, name: string): Promise<string> {
    const opts = new picker.DocumentSaveOptions();
    opts.newFileNames = [name];
    const uris = await new picker.DocumentViewPicker(ctx).save(opts);
    return uris !== undefined && uris.length > 0 ? uris[0] : '';
  }

  static async pickAnyUri(ctx: common.Context): Promise<string> {
    const opts = new picker.DocumentSelectOptions();
    opts.maxSelectNumber = 1;
    const uris = await new picker.DocumentViewPicker(ctx).select(opts);
    return uris !== undefined && uris.length > 0 ? uris[0] : '';
  }

  static async pickUris(ctx: common.Context, max: number): Promise<string[]> {
    const opts = new picker.DocumentSelectOptions();
    opts.maxSelectNumber = max;
    const uris = await new picker.DocumentViewPicker(ctx).select(opts);
    return uris !== undefined ? uris : [];
  }

  /** Async copy of a picker uri into the sandbox (keeps the UI thread free for big files). */
  static async copyUriToAsync(uri: string, dest: string): Promise<void> {
    const src = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    try {
      await fileIo.copyFile(src.fd, dest);
    } finally {
      await fileIo.close(src);
    }
  }

  /** Async copy of a sandbox file into a document uri (save picker result), 1 MiB at a time. */
  static async copyFileToUriAsync(src: string, uri: string): Promise<void> {
    const inF = await fileIo.open(src, fileIo.OpenMode.READ_ONLY);
    const outF = await fileIo.open(uri, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      const buf = new ArrayBuffer(1 << 20);
      let n = await fileIo.read(inF.fd, buf);
      while (n > 0) {
        await fileIo.write(outF.fd, buf, { length: n });
        n = await fileIo.read(inF.fd, buf);
      }
    } finally {
      await fileIo.close(inF);
      await fileIo.close(outF);
    }
  }

  /** Picks a folder with the system file manager; returns its uri ('' when cancelled). */
  static async pickFolder(ctx: common.Context): Promise<string> {
    const opts = new picker.DocumentSelectOptions();
    opts.selectMode = picker.DocumentSelectMode.FOLDER;
    const uris = await new picker.DocumentViewPicker(ctx).select(opts);
    return uris !== undefined && uris.length > 0 ? uris[0] : '';
  }

  /** File-system path behind a document uri (file://docs/storage/... → /storage/...). */
  static uriToPath(uri: string): string {
    try {
      return new fileUri.FileUri(uri).path;
    } catch (e) {
      return '';
    }
  }

  static pathToUri(path: string): string {
    return fileUri.getUriFromPath(path);
  }

  /** Lets the user open a sandbox file with another app (system "open with"). */
  static async openWith(ctx: common.UIAbilityContext, path: string): Promise<void> {
    await ctx.startAbility({
      action: 'ohos.want.action.viewData',
      uri: fileUri.getUriFromPath(path),
      flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION
    });
  }

  /** System share sheet for sandbox files. */
  static async shareFiles(ctx: common.UIAbilityContext, paths: string[]): Promise<void> {
    if (paths.length === 0) {
      return;
    }
    const first: systemShare.SharedRecord = {
      utd: uniformTypeDescriptor.UniformDataType.FILE,
      uri: fileUri.getUriFromPath(paths[0])
    };
    const data = new systemShare.SharedData(first);
    for (let i = 1; i < paths.length; i++) {
      data.addRecord({ utd: uniformTypeDescriptor.UniformDataType.FILE, uri: fileUri.getUriFromPath(paths[i]) });
    }
    const controller = new systemShare.ShareController(data);
    await controller.show(ctx, {
      previewMode: systemShare.SharePreviewMode.DEFAULT,
      selectionMode: systemShare.SelectionMode.BATCH
    });
  }

  /** Copies a sandbox file into a new document chosen with the save dialog; returns false when cancelled. */
  static async exportFile(ctx: common.Context, path: string, name: string): Promise<boolean> {
    const uri = await FileUtil.pickSaveUri(ctx, name);
    if (uri.length === 0) {
      return false;
    }
    await FileUtil.copyFileToUriAsync(path, uri);
    return true;
  }

  /** Copies picked documents into a sandbox folder (import into the library). */
  static async importUris(uris: string[], dir: string, taken: string[]): Promise<number> {
    let n = 0;
    for (const u of uris) {
      let name = FileUtil.nameFromUri(u);
      let i = 2;
      const dot = name.lastIndexOf('.');
      const stem = dot > 0 ? name.substring(0, dot) : name;
      const ext = dot > 0 ? name.substring(dot) : '';
      while (taken.indexOf(name) >= 0 || FileUtil.exists(dir + '/' + name)) {
        name = stem + ' (' + i + ')' + ext;
        i++;
      }
      await FileUtil.copyUriToAsync(u, dir + '/' + name);
      taken.push(name);
      n++;
    }
    return n;
  }

  static stat(path: string): fileIo.Stat | null {
    try {
      return fileIo.statSync(path);
    } catch (e) {
      return null;
    }
  }
}
