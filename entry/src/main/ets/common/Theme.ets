/**
 * Theme.ets — colors of the native pages, taken from the Sub-Store web UI's default themes (light / dark,
 * Sub-Store-Front-End src/theme) so the 服务管理 page looks like part of the same app.
 * ArkUI colors are '#RRGGBB' or '#AARRGGBB'.
 */
export class Palette {
  dark: boolean = false;
  /** page background (--background-color) */
  bg: string = '#F4F4F4';
  /** card (--card-color) */
  card: string = '#FFFFFF';
  /** input / segmented track */
  chip: string = '#EEEFF2';
  sheet: string = '#F4F4F4';
  /** --primary-text-color / --second-text-color / --comment-text-color / --lowest-text-color */
  text: string = '#303133';
  subtle: string = '#606266';
  tertiary: string = '#909399';
  disabled: string = '#C0C4CC';
  outline: string = '#DCDFE6';
  divider: string = '#EBEEF5';
  good: string = '#0ED57D';
  warn: string = '#E6A23C';
  bad: string = '#E56459';
  info: string = '#478EF2';
  /** --primary-color, gradient to --primary-color-end */
  accent: string = '#478EF2';
  accentUi: string = '#478EF2';
  accentFill: string = '#478EF2';
  primary: string = '#478EF2';
  primaryEnd: string = '#496AF2';
  onPrimary: string = '#FFFFFF';
  accentSoft: string = '#1A478EF2';
  codeBg: string = '#F7F8FA';
  codeText: string = '#303133';
}

/** '#RRGGBB' (or '#AARRGGBB') with its alpha replaced by `alpha` (0–1), as '#AARRGGBB'. */
export function withAlpha(hex: string, alpha: number): string {
  const a = Math.round(Math.max(0, Math.min(1, alpha)) * 255);
  const h = a.toString(16).toUpperCase();
  const aa = h.length < 2 ? '0' + h : h;
  const rgb = hex.length === 9 ? hex.substring(3) : hex.substring(1);
  return '#' + aa + rgb;
}

/** One accent color's tones for one mode: ui (icons/controls), text (accent text), fill (solid buttons), on (text on fill). */
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

/** A selectable 主题色 (same set and values as MimiSSH / MimiPanel; first entry 华为红 is the default). */
export class AccentDef {
  key: string;
  /** Chinese source name; render with t() */
  name: string;
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

  tone(dark: boolean): AccentTone {
    return dark ? this.dk : this.lt;
  }
}

export const ACCENTS: AccentDef[] = [
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

export function findAccent(key: string): AccentDef {
  for (const a of ACCENTS) {
    if (a.key === key) {
      return a;
    }
  }
  return ACCENTS[0];
}

/** Readable glyph color (white or near-black) for content drawn on a solid swatch. */
export function onColor(bg: string): string {
  const h = bg.length === 9 ? bg.substring(3) : bg.substring(1);
  const ch = (v: number): number => {
    const x = v / 255;
    return x <= 0.03928 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4);
  };
  const lum = 0.2126 * ch(parseInt(h.substring(0, 2), 16)) + 0.7152 * ch(parseInt(h.substring(2, 4), 16)) +
    0.0722 * ch(parseInt(h.substring(4, 6), 16));
  return lum > 0.3 ? '#172026' : '#FFFFFF';
}

/** Applies the accent to a palette: accent tokens, the primary gradient (fill → deeper text tone) and the soft wash. */
export function applyAccent(p: Palette, a: AccentDef): Palette {
  const tone = a.tone(p.dark);
  p.accent = tone.text;
  p.accentUi = tone.ui;
  p.accentFill = a.swatch;
  p.primary = tone.fill;
  p.primaryEnd = tone.text;
  p.onPrimary = tone.on;
  p.accentSoft = withAlpha(tone.ui, p.dark ? 0.22 : 0.12);
  return p;
}

/** A gradient 背景 preset; stops are soft tints near the plain page color so text keeps its contrast. */
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

  stops(dark: boolean): string[] {
    return dark ? this.dark : this.light;
  }
}

export const BACKDROPS: BackdropDef[] = [
  new BackdropDef('aurora', '极光', ['#DDF5EF', '#E4ECFB', '#F1E9FA'], ['#0C1F1D', '#0F1A2E', '#1B1430']),
  new BackdropDef('ocean', '深海', ['#DCEBFA', '#DDF2F3', '#E9F0FB'], ['#08182A', '#0A2230', '#0D162E']),
  new BackdropDef('dusk', '暮霞', ['#FCE8DE', '#F9E4EC', '#ECE6F5'], ['#25150F', '#241520', '#1A1528']),
  new BackdropDef('forest', '林间', ['#E3F2E2', '#EDF4E0', '#E0EFEA'], ['#0E1A10', '#141C10', '#0C1A17'])
];

export function findBackdrop(key: string): BackdropDef {
  for (const b of BACKDROPS) {
    if (b.key === key) {
      return b;
    }
  }
  return BACKDROPS[0];
}

/** With a gradient behind the pages, cards go translucent so it shows through (text stays readable at this alpha). */
export function applyBackdrop(p: Palette, on: boolean): Palette {
  if (on) {
    p.card = withAlpha(p.card, p.dark ? 0.86 : 0.88);
  }
  return p;
}

export function lightPalette(): Palette {
  return new Palette();
}

export function darkPalette(): Palette {
  const p = new Palette();
  p.dark = true;
  p.bg = '#121212';
  p.card = '#202020';
  p.chip = '#2A2A2A';
  p.sheet = '#1A1A1A';
  p.text = '#EEFFFFFF';
  p.subtle = '#BBFFFFFF';
  p.tertiary = '#88FFFFFF';
  p.disabled = '#36FFFFFF';
  p.outline = '#24FFFFFF';
  p.divider = '#14FFFFFF';
  p.good = '#49BB88';
  p.accentSoft = '#29478EF2';
  p.codeBg = '#1A1A1A';
  p.codeText = '#EEFFFFFF';
  return p;
}
