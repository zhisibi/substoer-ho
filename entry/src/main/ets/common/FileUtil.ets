/**
 * 文件说明：FileUtil.ets —— 文件与剪贴板工具函数。
 *
 * 职责：建目录、删除、系统“另存为”与文件选择器、URI 与沙箱文件互相复制、剪贴板复制。
 * 主要类型：FileUtil（只含静态方法）。
 * 与其他模块的关系：日志页、Sub-Store 网页的文件选择与下载用它读写、导出和复制。
 * 约定：同步方法吞掉异常；异步方法把异常抛给调用方。
 */
import { t } from './I18n';
import { fileIo, picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { pasteboard, BusinessError } from '@kit.BasicServicesKit';

/** File and clipboard helpers */
/**
 * 文件相关静态工具集合。
 */
export class FileUtil {
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

  /** Copies a sandbox file into a new document chosen with the save dialog; returns false when cancelled. */
  static async exportFile(ctx: common.Context, path: string, name: string): Promise<boolean> {
    const uri = await FileUtil.pickSaveUri(ctx, name);
    if (uri.length === 0) {
      return false;
    }
    await FileUtil.copyFileToUriAsync(path, uri);
    return true;
  }

}
