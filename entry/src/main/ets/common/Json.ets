/**
 * 文件说明：Json.ets —— 类型安全的 JSON 读取工具。
 *
 * 职责：ArkTS 禁止使用 any，因此把 JSON.parse 的结果统一视为 Record<string, Object>（JObj），
 *       并通过 jStr/jNum/jBool/jObj/jArr 等带默认值的访问器读取字段，避免类型错误与空指针。
 * 主要导出：JObj 类型；jGet/jHas；asStr/jStr；asNum/jNum/jNumOr；jBool；asObj/jObj；asArr/jArr/jStrArr；
 *           parseJson/parseJsonObj。
 * 与其他模块的关系：Models 的 fromJson()、QlApi 的响应解析、Prefs 的服务器列表都依赖这里。
 * 设计取舍：青龙不同版本字段类型并不稳定（数字有时是字符串、布尔有时是 0/1），所以访问器都做宽松转换。
 */
/**
 * JSON helpers. ArkTS has no `any`, so parsed JSON objects are handled as Record<string, Object>
 * and every field is read through a typed accessor with a default value.
 */
/** 解析后的 JSON 对象类型（键为字符串，值为任意非空 Object） */
export type JObj = Record<string, Object>;

/**
 * 读取对象字段，把 null 与 undefined 统一成 undefined。
 * @param o 对象（可为空）
 * @param k 字段名
 * @returns 字段值；对象为空、字段缺失或为 null 时返回 undefined
 */
export function jGet(o: JObj | undefined | null, k: string): Object | undefined {
  if (o === undefined || o === null) {
    return undefined;
  }
  const v: Object | undefined = o[k];
  if (v === undefined || v === null) {
    return undefined;
  }
  return v;
}

/**
 * 字段是否存在且非 null。
 * @param o 对象
 * @param k 字段名
 */
export function jHas(o: JObj | undefined | null, k: string): boolean {
  return jGet(o, k) !== undefined;
}

/**
 * 把任意值宽松转换为字符串。
 * @param v 任意值
 * @returns 字符串原样返回；数字/布尔转为字符串；其他（对象、数组、空值）返回 ''
 */
export function asStr(v: Object | undefined | null): string {
  if (v === undefined || v === null) {
    return '';
  }
  if (typeof v === 'string') {
    return v as string;
  }
  if (typeof v === 'number' || typeof v === 'boolean') {
    return String(v);
  }
  return '';
}

/**
 * 读取字符串字段，缺失时返回 ''。
 * @param o 对象
 * @param k 字段名
 */
export function jStr(o: JObj | undefined | null, k: string): string {
  return asStr(jGet(o, k));
}

/**
 * 把任意值宽松转换为数字。
 * @param v 任意值
 * @returns 数字原样；布尔 true/false 转 1/0；数字字符串解析；无法转换返回 0
 */
export function asNum(v: Object | undefined | null): number {
  if (v === undefined || v === null) {
    return 0;
  }
  if (typeof v === 'number') {
    return v as number;
  }
  if (typeof v === 'boolean') {
    return (v as boolean) ? 1 : 0;
  }
  if (typeof v === 'string') {
    const n = Number(v as string);
    return isNaN(n) ? 0 : n;
  }
  return 0;
}

/**
 * 读取数字字段，缺失或无法转换时返回 0。
 * @param o 对象
 * @param k 字段名
 */
export function jNum(o: JObj | undefined | null, k: string): number {
  return asNum(jGet(o, k));
}

/** Number field that may be missing: returns `def` when absent */
/**
 * 读取可能缺失的数字字段（区分“缺失”与“值为 0”）。
 * @param o 对象
 * @param k 字段名
 * @param def 字段缺失时的默认值
 */
export function jNumOr(o: JObj | undefined | null, k: string, def: number): number {
  const v = jGet(o, k);
  return v === undefined ? def : asNum(v);
}

/**
 * 读取布尔字段，兼容 true/false、非 0 数字、'true'/'1' 字符串。
 * @param o 对象
 * @param k 字段名
 * @param def 缺失或类型无法识别时的默认值
 */
export function jBool(o: JObj | undefined | null, k: string, def: boolean): boolean {
  const v = jGet(o, k);
  if (v === undefined) {
    return def;
  }
  if (typeof v === 'boolean') {
    return v as boolean;
  }
  if (typeof v === 'number') {
    return (v as number) !== 0;
  }
  if (typeof v === 'string') {
    return (v as string) === 'true' || (v as string) === '1';
  }
  return def;
}

/**
 * 把值转换为 JObj（排除数组和基础类型）。
 * @param v 任意值
 * @returns 普通对象时返回 JObj，否则 undefined
 */
export function asObj(v: Object | undefined | null): JObj | undefined {
  if (v === undefined || v === null) {
    return undefined;
  }
  if (typeof v === 'object' && !Array.isArray(v)) {
    return v as JObj;
  }
  return undefined;
}

/**
 * 读取子对象字段。
 * @param o 对象
 * @param k 字段名
 * @returns 子对象或 undefined
 */
export function jObj(o: JObj | undefined | null, k: string): JObj | undefined {
  return asObj(jGet(o, k));
}

/**
 * 把值转换为数组。
 * @param v 任意值
 * @returns 是数组则返回，否则返回空数组（方便直接 for-of）
 */
export function asArr(v: Object | undefined | null): Object[] {
  if (v === undefined || v === null) {
    return [];
  }
  if (Array.isArray(v)) {
    return v as Object[];
  }
  return [];
}

/**
 * 读取数组字段，缺失时返回空数组。
 * @param o 对象
 * @param k 字段名
 */
export function jArr(o: JObj | undefined | null, k: string): Object[] {
  return asArr(jGet(o, k));
}

/** Array of strings (non-string entries are skipped) */
/**
 * 读取字符串数组字段（如 labels），自动跳过非字符串元素。
 * @param o 对象
 * @param k 字段名
 */
export function jStrArr(o: JObj | undefined | null, k: string): string[] {
  const out: string[] = [];
  for (const e of jArr(o, k)) {
    if (typeof e === 'string') {
      out.push(e as string);
    }
  }
  return out;
}

/** Parses text; returns undefined instead of throwing */
/**
 * 安全解析 JSON 文本。
 * @param text JSON 文本
 * @returns 解析结果；空文本、语法错误或结果为 null 时返回 undefined，绝不抛异常
 */
export function parseJson(text: string): Object | undefined {
  if (text.length === 0) {
    return undefined;
  }
  try {
    const v = JSON.parse(text) as Object;
    return v === null ? undefined : v;
  } catch (e) {
    return undefined;
  }
}

/**
 * 解析 JSON 文本并要求结果是对象。
 * @param text JSON 文本
 * @returns JObj；不是对象（如数组、HTML 错误页）时返回 undefined
 */
export function parseJsonObj(text: string): JObj | undefined {
  return asObj(parseJson(text));
}

/** Plain record (AppLock persistence). */
export type JRec = Record<string, Object>;

export function parseRec(text: string): JRec | undefined {
  try {
    const v = JSON.parse(text) as Object;
    if (v !== null && typeof v === 'object' && !Array.isArray(v)) {
      return v as JRec;
    }
  } catch (e) {
    return undefined;
  }
  return undefined;
}
