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
