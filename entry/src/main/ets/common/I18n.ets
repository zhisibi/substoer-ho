/**
 * 文件说明：I18n.ets —— 极简运行时国际化（中/英）。
 *
 * 职责：以简体中文原文作为翻译键，在界面语言为英文时从 LangEn.ets 的词典中查找英文译文。
 * 主要导出：LangState（可观察的当前语言单例）、LangPref 类型、resolveLang()、isEn()、t()、tf()、plural()。
 * 与其他模块的关系：
 *  - 词典 EN_PAIRS 来自自动生成的 LangEn.ets（不要手改）；
 *  - Store 负责读取用户语言偏好并写入 LangState.lang；
 *  - 几乎所有界面与提示文案都通过 t()/tf() 输出。
 */
import { i18n } from '@kit.LocalizationKit';
import { EN_PAIRS } from './LangEn';

/**
 * Minimal runtime i18n.
 *
 * Source strings are written in Simplified Chinese and act as their own keys: `t('设置')` returns the
 * English text from LangEn.ets when the UI language is English, and the Chinese text otherwise.
 * A string missing from the dictionary falls back to Chinese (scripts/check-i18n.py reports those).
 *
 * `LangState.lang` is @Trace, so text built inside `build()` re-renders when the language changes; the
 * settings page also reloads the window so values cached outside of build pick up the new language.
 */
/**
 * 当前生效界面语言的全局可观察状态（单例）。
 *
 * 使用 @ObservedV2 + @Trace：build() 中读取 t() 的组件会因 lang 变化自动刷新。
 */
@ObservedV2
export class LangState {
  private static inst: LangState | null = null;

  /**
   * 获取单例（懒创建）。
   * @returns 全局唯一的 LangState
   */
  static get(): LangState {
    if (LangState.inst === null) {
      LangState.inst = new LangState();
    }
    return LangState.inst;
  }

  /** Effective UI language: 'zh' | 'en' */
  @Trace lang: string = 'zh';
}

/** User choice: 'system' | 'zh' | 'en' */
export type LangPref = string;

// 英文词典缓存：首次调用时才构建，避免应用启动时就解析数百条词条
let dict: Map<string, string> | null = null;

/**
 * 构建（或返回已缓存的）中文 -> 英文映射表。
 * EN_PAIRS 是扁平数组 [中文0, 英文0, 中文1, 英文1, ...]，按两两一组装入 Map。
 * @returns 中文原文到英文译文的 Map
 */
function enDict(): Map<string, string> {
  if (dict === null) {
    const m = new Map<string, string>();
    for (let i = 0; i + 1 < EN_PAIRS.length; i += 2) {
      m.set(EN_PAIRS[i], EN_PAIRS[i + 1]);
    }
    dict = m;
  }
  return dict;
}

/** Resolves 'system' to the device language */
/**
 * 把用户语言偏好解析为实际语言。
 * @param pref 'system' | 'zh' | 'en'
 * @returns 'zh' 或 'en'；'system' 时按设备系统语言判断（以 zh 开头即中文，含繁体），读取失败回退中文
 */
export function resolveLang(pref: LangPref): string {
  if (pref === 'zh' || pref === 'en') {
    return pref;
  }
  try {
    const sys = i18n.System.getSystemLanguage();
    return sys.toLowerCase().startsWith('zh') ? 'zh' : 'en';
  } catch (e) {
    return 'zh';
  }
}

/**
 * 当前界面是否为英文。
 * @returns true 表示英文
 */
export function isEn(): boolean {
  return LangState.get().lang === 'en';
}

/** Translates a Chinese source string */
/**
 * 翻译一个中文原文字符串。
 * @param zh 中文原文（同时也是词典键）
 * @returns 中文界面直接返回原文；英文界面返回译文，缺词条时回退中文
 */
export function t(zh: string): string {
  if (LangState.get().lang !== 'en') {
    return zh;
  }
  const v = enDict().get(zh);
  return v !== undefined ? v : zh;
}

/** Translates a template and fills {0}, {1}, … with the arguments */
/**
 * 翻译带占位符的模板，并用参数依次替换 {0}、{1}……
 * @param zh 含占位符的中文模板
 * @param args 填充值
 * @returns 翻译并填充后的字符串
 * 注意：先翻译再替换，所以英文译文中也必须保留相同的占位符；用 split/join 是为了替换全部出现位置。
 */
export function tf(zh: string, ...args: (string | number)[]): string {
  let s = t(zh);
  for (let i = 0; i < args.length; i++) {
    s = s.split('{' + i + '}').join(String(args[i]));
  }
  return s;
}

/** Picks the right plural form for English ("1 task" / "3 tasks"); Chinese has none */
/**
 * 英文单复数选择（中文无单复数，调用方在中文下通常传入相同文本）。
 * @param n 数量
 * @param one 单数形式
 * @param many 复数形式
 * @returns n 为 1 时返回 one，否则 many
 */
export function plural(n: number, one: string, many: string): string {
  return n === 1 ? one : many;
}
