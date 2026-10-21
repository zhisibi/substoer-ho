/**
 * 文件说明：Format.ets —— 各类显示格式化工具。
 *
 * 职责：日期时间、相对时间（多久之前/之后）、时长、文件大小的格式化；脚本日志中 ANSI 控制序列的清理；
 *       长日志尾部截取；密钥值打码显示；单行摘要；依赖名称拆分等。
 * 主要导出：fmtDateTime、fmtShort、fmtStamp、parseTime、fmtAgo、fmtIn、fmtDuration、fmtBytes、
 *           stripAnsi、keepTail、maskValue、oneLine、splitNames。
 * 与其他模块的关系：依赖 I18n 的 t/tf 输出中英文单位；被 CrashLog、各列表与日志页面广泛使用。
 * 注意：所有时间均按设备本地时区显示。
 */
import { t, tf } from './I18n';
/** Formatting helpers (dates, durations, sizes, log text) */

/**
 * 数字补零到两位。
 * @param n 0~99 的数字
 * @returns 两位字符串，如 5 -> "05"
 */
function pad2(n: number): string {
  return n < 10 ? '0' + n : String(n);
}

/** ms -> 2026-10-10 12:34:56 */
/**
 * 毫秒时间戳转完整日期时间。
 * @param ms 毫秒时间戳
 * @returns "YYYY-MM-DD HH:mm:ss"；无效值（<=0 或 NaN）返回 "-"
 */
export function fmtDateTime(ms: number): string {
  if (ms <= 0 || isNaN(ms)) {
    return '-';
  }
  const d = new Date(ms);
  return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()) + ' ' +
    pad2(d.getHours()) + ':' + pad2(d.getMinutes()) + ':' + pad2(d.getSeconds());
}

/** ms -> 10-10 12:34 (current year) or 2025-10-10 12:34 */
/**
 * 毫秒时间戳转短格式：今年省略年份。
 * @param ms 毫秒时间戳
 * @returns "MM-DD HH:mm" 或 "YYYY-MM-DD HH:mm"；无效值返回 "-"
 */
export function fmtShort(ms: number): string {
  if (ms <= 0 || isNaN(ms)) {
    return '-';
  }
  const d = new Date(ms);
  const now = new Date();
  const md = pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()) + ' ' + pad2(d.getHours()) + ':' + pad2(d.getMinutes());
  return d.getFullYear() === now.getFullYear() ? md : d.getFullYear() + '-' + md;
}

/** ms -> 20261010-123456 (file names) */
/**
 * 毫秒时间戳转紧凑的文件名时间戳。
 * @param ms 毫秒时间戳
 * @returns "YYYYMMDD-HHmmss"，字典序与时间顺序一致（CrashLog 依赖这一点排序）
 */
export function fmtStamp(ms: number): string {
  const d = new Date(ms);
  return d.getFullYear() + pad2(d.getMonth() + 1) + pad2(d.getDate()) + '-' +
    pad2(d.getHours()) + pad2(d.getMinutes()) + pad2(d.getSeconds());
}

/** Parses an ISO / Date.toString() timestamp; 0 when invalid */
/**
 * 解析 ISO 或 Date.toString() 格式的时间字符串（青龙的 updatedAt 等字段）。
 * @param s 时间字符串
 * @returns 毫秒时间戳；为空或无法解析返回 0
 */
export function parseTime(s: string): number {
  if (s.length === 0) {
    return 0;
  }
  const t = Date.parse(s);
  return isNaN(t) ? 0 : t;
}

/** "刚刚", "5 分钟前", "3 小时前", "2 天前", or the short date */
/**
 * 相对过去时间：“刚刚”、“N 分钟前”、“N 小时前”、“N 天前”，超过 7 天显示短日期。
 * @param ms 毫秒时间戳；<=0 表示从未运行
 * @returns 本地化文本
 * 注意：时间在未来（服务器与手机时钟不同步）时直接显示短日期，避免出现负数。
 */
export function fmtAgo(ms: number): string {
  if (ms <= 0) {
    return t('从未运行');
  }
  const diff = Math.floor((Date.now() - ms) / 1000);
  if (diff < 0) {
    return fmtShort(ms);
  }
  if (diff < 60) {
    return t('刚刚');
  }
  if (diff < 3600) {
    return tf('{0} 分钟前', Math.floor(diff / 60));
  }
  if (diff < 86400) {
    return tf('{0} 小时前', Math.floor(diff / 3600));
  }
  if (diff < 86400 * 7) {
    return tf('{0} 天前', Math.floor(diff / 86400));
  }
  return fmtShort(ms);
}

/** Time until a future moment: "3 分钟后", "2 小时 5 分后" */
/**
 * 距离未来某时刻还有多久：“N 秒后”、“N 分钟后”、“N 小时 M 分后”、“N 天后”。
 * @param ms 目标时刻的毫秒时间戳；已过去则按 0 秒处理
 * @returns 本地化文本（用于 cron 下次运行预览）
 */
export function fmtIn(ms: number): string {
  const diff = Math.max(0, Math.floor((ms - Date.now()) / 1000));
  if (diff < 60) {
    return tf('{0} 秒后', diff);
  }
  if (diff < 3600) {
    return tf('{0} 分钟后', Math.floor(diff / 60));
  }
  if (diff < 86400) {
    const h = Math.floor(diff / 3600);
    const m = Math.floor((diff % 3600) / 60);
    return (m > 0 ? tf('{0} 小时 {1} 分后', h, m) : tf('{0} 小时后', h));
  }
  return tf('{0} 天后', Math.floor(diff / 86400));
}

/** Seconds -> "1 分 23 秒", "2 时 5 分" */
/**
 * 秒数转可读时长（如任务上次运行耗时）。
 * @param sec 秒数（可为小数，会四舍五入）
 * @returns “N 秒”、“N 分 M 秒”、“N 时 M 分”、“N 天 M 时”；无效值返回“0 秒”
 */
export function fmtDuration(sec: number): string {
  if (sec <= 0 || isNaN(sec)) {
    return tf('{0} 秒', 0);
  }
  const s = Math.round(sec);
  if (s < 60) {
    return tf('{0} 秒', s);
  }
  if (s < 3600) {
    return tf('{0} 分 {1} 秒', Math.floor(s / 60), s % 60);
  }
  if (s < 86400) {
    return tf('{0} 时 {1} 分', Math.floor(s / 3600), Math.floor((s % 3600) / 60));
  }
  return tf('{0} 天 {1} 时', Math.floor(s / 86400), Math.floor((s % 86400) / 3600));
}

/**
 * 字节数转可读大小（1024 进制）。
 * @param n 字节数
 * @returns 如 "512 B"、"1.5 KB"、"120 MB"；>=100 时不保留小数，避免数字过长
 */
export function fmtBytes(n: number): string {
  if (n <= 0 || isNaN(n)) {
    return '0 B';
  }
  const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB'];
  let v = n;
  let i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return (i === 0 ? String(Math.round(v)) : v.toFixed(v >= 100 ? 0 : 1)) + ' ' + units[i];
}

/** Removes ANSI color / cursor escape sequences that scripts print */
/**
 * 去除脚本输出中的 ANSI 转义序列（颜色、光标移动、OSC 标题），并把孤立的 \r 转为换行。
 * @param s 原始日志文本
 * @returns 适合在 Text 组件中显示的纯文本
 * 注意：进度条类输出用 \r 覆盖同一行，转为 \n 后至少能看到每次刷新的内容，而不是被拼成一长行。
 */
export function stripAnsi(s: string): string {
  // eslint-disable-next-line no-control-regex
  return s.replace(/\u001b\[[0-9;?]*[ -\/]*[@-~]/g, '').replace(/\u001b\][^\u0007]*\u0007/g, '').replace(/\r(?!\n)/g, '\n');
}

/** Keeps the last `maxChars` characters of a growing log, cutting at a line break */
/**
 * 只保留不断增长的日志的最后 maxChars 个字符，用于限制轮询日志时的内存占用。
 * @param s 当前完整日志
 * @param maxChars 最多保留的字符数
 * @returns 截取后的文本；尽量从截断点之后的第一个换行处开始，避免首行残缺
 * 注意：若 2000 个字符内找不到换行（超长单行），则直接硬截断。
 */
export function keepTail(s: string, maxChars: number): string {
  if (s.length <= maxChars) {
    return s;
  }
  const cut = s.length - maxChars;
  const nl = s.indexOf('\n', cut);
  return nl >= 0 && nl - cut < 2000 ? s.substring(nl + 1) : s.substring(cut);
}

/** Masks a secret value for list display: abc••••xyz */
/**
 * 列表中打码显示密钥类变量值：保留首尾各 3 个字符。
 * @param v 原始值
 * @returns 如 "abc••••••xyz"；长度 <=6 时完全打码；空值返回 ''
 */
export function maskValue(v: string): string {
  if (v.length === 0) {
    return '';
  }
  if (v.length <= 6) {
    return '••••••';
  }
  return v.substring(0, 3) + '••••••' + v.substring(v.length - 3);
}

/** First line of a multi-line text, shortened */
/**
 * 取多行文本的第一行，并截断到 max 个字符（超出加省略号）。
 * @param s 原始文本
 * @param max 最大字符数
 */
export function oneLine(s: string, max: number): string {
  const nl = s.indexOf('\n');
  const line = nl >= 0 ? s.substring(0, nl) : s;
  return line.length > max ? line.substring(0, max) + t('…') : line;
}

/** Splits user input like "a b\nc,d" into a clean list (for dependency names) */
/**
 * 把用户输入的依赖名称拆分为列表：支持空格、换行、英文逗号和中文逗号分隔。
 * @param s 用户输入，如 "axios got\nrequests,pyyaml"
 * @returns 去空白后的非空名称数组
 */
export function splitNames(s: string): string[] {
  return s.split(/[\s,，]+/).map((x: string) => x.trim()).filter((x: string) => x.length > 0);
}

/** "HH:mm:ss" (run log) */
export function fmtClock(ms: number): string {
  const d = new Date(ms);
  return pad2(d.getHours()) + ':' + pad2(d.getMinutes()) + ':' + pad2(d.getSeconds());
}
