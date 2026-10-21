/**
 * 文件说明：Theme.ets —— 颜色主题、强调色、渐变背景与图标色块的计算。
 *
 * 职责：
 *  - Palette：一套完整的界面配色（浅色默认值 + darkPalette() 深色覆盖）；
 *  - AccentTone / AccentDef / ACCENTS：可选强调色，每种都有分别为浅色和深色调好的四个色值；
 *  - BackdropDef / BACKDROPS：页面背后可选的柔和渐变背景；
 *  - applyAccent / applyBackdrop：在基础调色板上叠加强调色与背景（半透明 / 毛玻璃）效果；
 *  - tileColor：根据强调色生成列表图标色块，保证白色图标的对比度。
 * 与其他模块的关系：Store.palette() 组合调用本文件函数得到最终调色板，所有组件从 Store 读取颜色。
 *                  毛玻璃的模糊半径由 Store.blurRadius() 提供，本文件只负责把卡片/栏位颜色调成半透明。
 * 约束：所有文字/图标色都经过 scripts/check-contrast.py 的 WCAG 对比度校验（文字 >= 4.5:1，图标 >= 3:1），
 *       修改色值后需重新运行该脚本，否则可能因对比度不足被应用市场自检拒绝。
 */
/**
 * Colors. Every text/icon token is checked against WCAG (text >= 4.5:1, icons >= 3:1) on bg, card and chip,
 * light and dark, by scripts/check-contrast.py — AppGallery's 上架自检 rejects low-contrast UI.
 */
/**
 * 界面调色板。字段默认值即浅色主题；深色主题由 darkPalette() 覆盖。
 * 颜色均为 '#RRGGBB' 或带透明度的 '#AARRGGBB' 字符串。
 */
export class Palette {
  dark: boolean = false;
  bg: string = '#F3F6F8';
  card: string = '#FFFFFF';
  chip: string = '#EDF1F4';
  sheet: string = '#F3F6F8';
  /** Primary text (titles, values) */
  text: string = '#161D23';
  /** Secondary text (descriptions, metadata) */
  subtle: string = '#525D67';
  /** Tertiary text (hints, timestamps, placeholders) — still >= 4.5:1 */
  tertiary: string = '#5E6872';
  /** Disabled text/icons (>= 3:1, decorative contrast only) */
  disabled: string = '#808992';
  outline: string = '#D3DAE0';
  divider: string = '#E6EBEF';
  good: string = '#1F6E44';
  warn: string = '#7A5410';
  bad: string = '#B3261E';
  info: string = '#0B5BB0';
  /** Accent for text (>= 4.5:1) */
  accent: string = '#B00826';
  /** Accent for icons and controls (>= 3:1) */
  accentUi: string = '#CF0A2C';
  /** Vivid accent for decoration only (gradients, swatches) */
  accentFill: string = '#CF0A2C';
  /** Filled button background and its text color */
  primary: string = '#CF0A2C';
  onPrimary: string = '#FFFFFF';
  /** Soft accent background (selected row, chips) */
  accentSoft: string = '#1FCF0A2C';
  /** Code / log viewer */
  codeBg: string = '#F7F9FA';
  codeText: string = '#1E2A32';
  /** Floating tab bar / side rail */
  bar: string = '#FFFFFF';
}

/**
 * 一种强调色在某个明暗模式下的四个色值。
 * ui：图标与控件（>= 3:1）；text：强调文字（>= 4.5:1）；fill：实心按钮背景；on：实心按钮上的文字颜色。
 */
export class AccentTone {
  ui: string;
  text: string;
  fill: string;
  on: string;

  constructor(ui: string, text: string, fill: string, on: string) {
    this.ui = ui;
    this.text = text;
    this.fill = fill;
    this.on = on;
  }
}

/**
 * 一种可选强调色的完整定义。
 * key 为持久化键；name 为中文显示名；swatch 为设置页色块与装饰色；lt/dk 分别是浅色/深色模式下的色值。
 */
export class AccentDef {
  key: string;
  name: string;
  /** Swatch color */
  swatch: string;
  lt: AccentTone;
  dk: AccentTone;

  constructor(key: string, name: string, swatch: string, lt: AccentTone, dk: AccentTone) {
    this.key = key;
    this.name = name;
    this.swatch = swatch;
    this.lt = lt;
    this.dk = dk;
  }
}

/**
 * 全部可选强调色。第一项“华为红”为默认值（findAccent 找不到时回退到它）。
 * 注意：琥珀橙的实心按钮使用深色文字（on 为深色），因为白字在亮橙底上对比度不足。
 */
export const ACCENTS: AccentDef[] = [
  // 华为红 (Huawei red #CF0A2C) is the default since 1.1.0. The key stays 'red' so a user who picked the old
  // 朱砂红 (same hue) keeps it; users who never changed the accent have no saved key and get this one.
  new AccentDef('red', '华为红', '#CF0A2C',
    new AccentTone('#CF0A2C', '#B00826', '#CF0A2C', '#FFFFFF'),
    new AccentTone('#FF5C70', '#FF8E9B', '#D91537', '#FFFFFF')),
  new AccentDef('indigo', '靛青', '#3F51B5',
    new AccentTone('#3F51B5', '#34449A', '#3F51B5', '#FFFFFF'),
    new AccentTone('#8C9BEA', '#B1BCF2', '#5C6BC0', '#FFFFFF')),
  new AccentDef('teal', '薄荷青', '#16AA9E',
    new AccentTone('#0E8A7C', '#0B6E63', '#0B7A6E', '#FFFFFF'),
    new AccentTone('#3CCBB8', '#6EDCCB', '#2BB3A1', '#0F1417')),
  new AccentDef('blue', '天空蓝', '#0A59F7',
    new AccentTone('#0A59F7', '#0646C8', '#0A59F7', '#FFFFFF'),
    new AccentTone('#588DFF', '#8EB2FF', '#246AFF', '#FFFFFF')),
  new AccentDef('purple', '优雅紫', '#8A5CD1',
    new AccentTone('#8A5CD1', '#6C37BF', '#8A5CD1', '#FFFFFF'),
    new AccentTone('#A885E1', '#C5AEEB', '#8B5CD7', '#FFFFFF')),
  new AccentDef('orange', '琥珀橙', '#F39A2B',
    new AccentTone('#B86B0A', '#915408', '#F39A2B', '#172026'),
    new AccentTone('#F7AE52', '#FACB8E', '#F7AE52', '#0F1417'))
];

/**
 * 按 key 查找强调色。
 * @param key 强调色键，如 'teal'
 * @returns 对应定义；找不到（如旧版本保存的已删除键）时返回默认的第一项
 */
export function findAccent(key: string): AccentDef {
  for (const a of ACCENTS) {
    if (a.key === key) {
      return a;
    }
  }
  return ACCENTS[0];
}

/** '#RRGGBB' + alpha(0..1) -> '#AARRGGBB' */
/**
 * 给颜色加上透明度。
 * @param hex '#RRGGBB'，或已带透明度的 '#AARRGGBB'（原透明度会被替换）
 * @param alpha 0~1 的不透明度
 * @returns ArkUI 使用的 '#AARRGGBB' 格式（注意透明度在前）
 */
export function withAlpha(hex: string, alpha: number): string {
  const a = Math.round(Math.max(0, Math.min(1, alpha)) * 255);
  const h = a.toString(16).toUpperCase();
  const aa = h.length < 2 ? '0' + h : h;
  const rgb = hex.length === 9 ? hex.substring(3) : hex.substring(1);
  return '#' + aa + rgb;
}

/**
 * Readable glyph/text color (white or near-black) for content drawn on an arbitrary solid color, e.g. a swatch.
 * 在任意纯色（如强调色色块）上绘制图标/文字时，按亮度选择白色或近黑色。
 */
export function onColor(bg: string): string {
  return relLum(bg.length === 9 ? '#' + bg.substring(3) : bg) > 0.3 ? '#172026' : '#FFFFFF';
}

/**
 * 生成浅色调色板。
 * @returns 新的 Palette 实例（默认字段值）
 */
export function lightPalette(): Palette {
  return new Palette();
}

/**
 * 生成深色调色板：在默认值基础上覆盖背景、文字、状态色等。
 * @returns 新的深色 Palette；强调色需再调用 applyAccent()
 */
export function darkPalette(): Palette {
  const p = new Palette();
  p.dark = true;
  p.bg = '#0F1417';
  p.card = '#1A2127';
  p.chip = '#242D34';
  p.sheet = '#151B20';
  p.text = '#E8EDF1';
  p.subtle = '#A8B3BC';
  p.tertiary = '#909CA6';
  p.disabled = '#6C7882';
  p.outline = '#36414A';
  p.divider = '#283138';
  p.good = '#5CC98E';
  p.warn = '#F0B544';
  p.bad = '#F4938C';
  p.info = '#5FB0FF';
  p.codeBg = '#12181C';
  p.codeText = '#D5DEE4';
  p.bar = p.card;
  return p;
}

/**
 * 把强调色应用到调色板（按调色板的明暗选择 lt 或 dk 色值）。
 * @param p 基础调色板（会被原地修改）
 * @param a 强调色定义
 * @returns 同一个 p，便于链式调用
 * 注意：accentSoft 是半透明的强调色底，深色模式下透明度更高才看得出来。
 */
export function applyAccent(p: Palette, a: AccentDef): Palette {
  const tone = p.dark ? a.dk : a.lt;
  p.accent = tone.text;
  p.accentUi = tone.ui;
  p.accentFill = a.swatch;
  p.primary = tone.fill;
  p.onPrimary = tone.on;
  p.accentSoft = withAlpha(tone.ui, p.dark ? 0.22 : 0.12);
  return p;
}

// ------------------------------------------------------------------ backgrounds

/**
 * A gradient background preset. Every stop is a soft tint close to the plain page color, so the text tokens
 * keep their contrast (scripts/check-contrast.py checks them on each stop, like on `bg`).
 */
/**
 * 渐变背景预设。
 * key 为持久化键；light/dark 分别为浅色/深色模式下的渐变色标数组。
 */
export class BackdropDef {
  key: string;
  /** Chinese source name; render with t() */
  name: string;
  light: string[];
  dark: string[];

  constructor(key: string, name: string, light: string[], dark: string[]) {
    this.key = key;
    this.name = name;
    this.light = light;
    this.dark = dark;
  }

  /**
   * 取当前明暗模式的渐变色标。
   * @param dark 是否深色模式
   * @returns 色标数组
   */
  stops(dark: boolean): string[] {
    return dark ? this.dark : this.light;
  }
}

/** 全部渐变背景预设（第一项“极光”为默认回退值） */
export const BACKDROPS: BackdropDef[] = [
  new BackdropDef('aurora', '极光', ['#DDF5EF', '#E4ECFB', '#F1E9FA'], ['#0C1F1D', '#0F1A2E', '#1B1430']),
  new BackdropDef('ocean', '深海', ['#DCEBFA', '#DDF2F3', '#E9F0FB'], ['#08182A', '#0A2230', '#0D162E']),
  new BackdropDef('dusk', '暮霞', ['#FCE8DE', '#F9E4EC', '#ECE6F5'], ['#25150F', '#241520', '#1A1528']),
  new BackdropDef('forest', '林间', ['#E3F2E2', '#EDF4E0', '#E0EFEA'], ['#0E1A10', '#141C10', '#0C1A17']),
  new BackdropDef('mist', '晨雾', ['#EDF2F6', '#E3E9EF', '#F4F0EA'], ['#11171B', '#182027', '#1B1A17']),
  new BackdropDef('sakura', '樱粉', ['#FBE9EF', '#F6EAF6', '#EAEFFB'], ['#24121A', '#21142A', '#141830'])
];

/**
 * 按 key 查找背景预设。
 * @param key 背景键
 * @returns 对应定义；找不到时返回第一项
 */
export function findBackdrop(key: string): BackdropDef {
  for (const b of BACKDROPS) {
    if (b.key === key) {
      return b;
    }
  }
  return BACKDROPS[0];
}

/**
 * With a background drawn behind the pages, cards and bars become translucent so it shows through.
 * Frosted glass adds a blur material underneath (Store.blurStyle()), so those surfaces can be lighter still.
 */
/**
 * 根据背景/毛玻璃设置调整卡片与栏位的透明度。
 * @param p 调色板（原地修改）
 * @param backdrop 页面后是否绘制了背景（图片、渐变或光晕）
 * @param glass 是否开启毛玻璃
 * @returns 同一个 p
 * 注意：毛玻璃模式下卡片透明度更低（更透），因为组件上会再叠加 backdropBlur 模糊背景，
 *       仅半透明、无模糊时则需更不透明，以保证文字可读。
 */
export function applyBackdrop(p: Palette, backdrop: boolean, glass: boolean): Palette {
  if (glass) {
    p.card = withAlpha(p.card, p.dark ? 0.42 : 0.5);
    p.bar = withAlpha(p.bar, p.dark ? 0.45 : 0.55);
  } else if (backdrop) {
    p.card = withAlpha(p.card, p.dark ? 0.86 : 0.88);
    p.bar = withAlpha(p.bar, p.dark ? 0.92 : 0.94);
  }
  return p;
}

// ------------------------------------------------------------------ icon tiles

/**
 * 十六进制颜色转 HSL。
 * @param hex '#RRGGBB' 或 '#AARRGGBB'（忽略透明度）
 * @returns [色相 0~360, 饱和度 0~1, 亮度 0~1]
 */
function hexToHsl(hex: string): number[] {
  const h = hex.length === 9 ? hex.substring(3) : hex.substring(1);
  const r = parseInt(h.substring(0, 2), 16) / 255;
  const g = parseInt(h.substring(2, 4), 16) / 255;
  const b = parseInt(h.substring(4, 6), 16) / 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const l = (max + min) / 2;
  let hue = 0;
  let s = 0;
  if (max !== min) {
    const d = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    if (max === r) {
      hue = (g - b) / d + (g < b ? 6 : 0);
    } else if (max === g) {
      hue = (b - r) / d + 2;
    } else {
      hue = (r - g) / d + 4;
    }
    hue *= 60;
  }
  return [hue, s, l];
}

/**
 * HSL 转十六进制颜色。
 * @param hue 色相（任意角度，会归一化到 0~360）
 * @param s 饱和度 0~1
 * @param l 亮度 0~1
 * @returns '#RRGGBB'
 */
function hslToHex(hue: number, s: number, l: number): string {
  const c = (1 - Math.abs(2 * l - 1)) * s;
  const hp = ((hue % 360) + 360) % 360 / 60;
  const x = c * (1 - Math.abs(hp % 2 - 1));
  let r = 0;
  let g = 0;
  let b = 0;
  if (hp < 1) {
    r = c; g = x;
  } else if (hp < 2) {
    r = x; g = c;
  } else if (hp < 3) {
    g = c; b = x;
  } else if (hp < 4) {
    g = x; b = c;
  } else if (hp < 5) {
    r = x; b = c;
  } else {
    r = c; b = x;
  }
  const m = l - c / 2;
  const to = (v: number): string => {
    const n = Math.round((v + m) * 255).toString(16).toUpperCase();
    return n.length < 2 ? '0' + n : n;
  };
  return '#' + to(r) + to(g) + to(b);
}

/**
 * Color of the i-th icon tile in a list: hues fan out from the accent color, so the set changes with the
 * theme while neighbours stay distinct. Lightness is kept low enough for a white glyph (>= 3:1).
 */
/**
 * 计算列表中第 i 个图标色块的颜色。
 * @param accent 当前强调色（'#RRGGBB'）
 * @param i 序号（超出预设步长数组长度时循环）
 * @param dark 是否深色模式（深色模式亮度略高）
 * @returns 色块颜色
 * 实现：以强调色色相为中心按固定步长向两侧展开，使相邻色块区分明显且整体随主题变化；
 *       饱和度限制在 0.5~0.72 之间，避免过灰或过艳。
 */
export function tileColor(accent: string, i: number, dark: boolean): string {
  const hsl = hexToHsl(accent);
  const steps: number[] = [0, 38, -38, 76, -76, 152, 114, -114, 190];
  const hue = hsl[0] + steps[i % steps.length];
  const sat = Math.min(0.72, Math.max(0.5, hsl[1]));
  let l = dark ? 0.5 : 0.46;
  let c = hslToHex(hue, sat, l);
  // Yellows and greens are bright: darken until a white glyph reaches 3.2:1
  while (l > 0.2 && 1.05 / (relLum(c) + 0.05) < 3.2) {
    l -= 0.02;
    c = hslToHex(hue, sat, l);
  }
  return c;
}

/**
 * 计算 WCAG 相对亮度（用于对比度计算：对比度 = (L1 + 0.05) / (L2 + 0.05)，白色 L = 1）。
 * @param hex '#RRGGBB'
 * @returns 相对亮度 0~1
 */
function relLum(hex: string): number {
  const h = hex.substring(1);
  const ch = (v: number): number => {
    const x = v / 255;
    return x <= 0.03928 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4);
  };
  return 0.2126 * ch(parseInt(h.substring(0, 2), 16)) + 0.7152 * ch(parseInt(h.substring(2, 4), 16)) +
    0.0722 * ch(parseInt(h.substring(4, 6), 16));
}
