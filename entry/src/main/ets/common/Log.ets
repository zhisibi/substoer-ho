/**
 * 文件说明：Log.ets —— 全局统一日志工具。
 *
 * 职责：在 hilog 之上封装 d/i/w/e 四个级别的日志输出，并提供异常描述与敏感信息脱敏工具。
 * 主要类型：Log（只含静态方法）。
 * 与其他模块的关系：几乎所有模块（QlApi、Store、SecretStore、Prefs、CrashLog、Updater 等）都通过它写日志。
 * 安全约定：任何密码、令牌（token）、Client Secret 都不允许原样写入日志，必要时用 Log.mask() 脱敏。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * Unified logging on top of hilog.
 *
 * - Domain 0x4C4C ("LL"), tag "MimiSubStore"; filter with `hdc hilog -T MimiSubStore`.
 * - Never pass passwords, tokens or client secrets here. Use Log.mask() for anything that might contain one.
 * - Debug lines are dropped in release builds by hilog itself (DEBUG level is off by default on user devices).
 */
// hilog 业务域 0x4C4C，即 ASCII 的 "LL"（历史值），便于在系统日志中过滤
const DOMAIN: number = 0x4C4C;
const TAG: string = 'MimiSubStore';

/**
 * 日志门面类。所有方法都是静态的，直接 Log.i('Scope', 'msg') 调用即可。
 *
 * 格式统一为 "[scope] msg"，并使用 %{public}s：hilog 默认会把参数当作隐私信息打码为 <private>，
 * 标成 public 才能在 release 包里看到内容——这也是为什么调用方必须自行保证不传入敏感数据。
 */
export class Log {
  /**
   * 调试日志（DEBUG）。用户设备上默认不输出，适合高频、细节型信息（如每个请求的耗时）。
   * @param scope 日志所属模块/作用域名称，如 'Api'
   * @param msg 日志内容（不得包含敏感信息）
   */
  static d(scope: string, msg: string): void {
    hilog.debug(DOMAIN, TAG, '[%{public}s] %{public}s', scope, msg);
  }

  /**
   * 普通信息日志（INFO），记录关键流程节点，如登录成功、连接成功。
   * @param scope 模块名
   * @param msg 日志内容
   */
  static i(scope: string, msg: string): void {
    hilog.info(DOMAIN, TAG, '[%{public}s] %{public}s', scope, msg);
  }

  /**
   * 警告日志（WARN），记录可恢复的失败，如某个请求失败但已降级处理。
   * @param scope 模块名
   * @param msg 日志内容
   */
  static w(scope: string, msg: string): void {
    hilog.warn(DOMAIN, TAG, '[%{public}s] %{public}s', scope, msg);
  }

  /**
   * 错误日志（ERROR）。
   * @param scope 模块名
   * @param msg 日志内容
   * @param err 可选，捕获到的异常对象；会通过 describe() 转为简短安全的描述追加在末尾
   */
  static e(scope: string, msg: string, err?: Object): void {
    const detail = err !== undefined ? ' :: ' + Log.describe(err) : '';
    hilog.error(DOMAIN, TAG, '[%{public}s] %{public}s%{public}s', scope, msg, detail);
  }

  /** Short, safe description of any thrown value */
  /**
   * 把任意被 throw 的值转成简短字符串。
   * @param err 异常对象（Error 或任意值）
   * @returns Error 返回 "name: message"；其他值尝试 JSON 序列化，失败则 String()
   * 注意：不输出调用栈，避免日志过长；JSON.stringify 可能因循环引用抛错，所以包了 try。
   */
  static describe(err: Object): string {
    if (err instanceof Error) {
      const e = err as Error;
      return e.name + ': ' + e.message;
    }
    try {
      return JSON.stringify(err);
    } catch (e) {
      return String(err);
    }
  }

  /** Masks a secret for logs: keeps the first 3 characters only */
  /**
   * 敏感字符串脱敏：只保留前 3 个字符，并附上原长度，便于排查“是不是同一个值”而不泄露内容。
   * @param s 原始字符串（用户名、Client ID 等）
   * @returns 例如 "adm***(5)"；长度不超过 3 时直接返回 "***"
   */
  static mask(s: string): string {
    if (s.length <= 3) {
      return '***';
    }
    return s.substring(0, 3) + '***(' + s.length + ')';
  }
}
