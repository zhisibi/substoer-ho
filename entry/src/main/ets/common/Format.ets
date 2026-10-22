/**
 * 文件说明：Format.ets —— 各类显示格式化工具。
 *
 * 职责：短日期时间、时长、文件大小的格式化。
 * 主要导出：fmtShort、fmtDuration、fmtBytes。
 * 与其他模块的关系：依赖 I18n 的 t/tf 输出中英文单位；被服务管理与日志页面使用。
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

