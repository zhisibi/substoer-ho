/**
 * LightSense.ets — 导航栏沉浸光感 (HarmonyOS Immersive Light Sense) for the native pages' top
 * navigation bar, ported from 咪咪SSH 1.5.6/1.5.7 (itself from 咪咪Neko).
 *
 * - API ≥ 26 and uiMaterial.isImmersiveMaterialSupported() (state not DISABLE) → the bar surface takes
 *   ArkUI's systemMaterial(ImmersiveMaterial THIN) with a light neutral tint; the material replaces
 *   background / border / shadow on that node, so the hairline rim and refraction highlight are drawn
 *   as separate non-interactive overlays (GlassRimMod).
 * - Otherwise (API 20–25 or no system material): heavy backdrop blur with the same tint.
 * - Off: the bar is the plain page background, exactly as before this feature.
 * Every newer API is only called behind deviceInfo.sdkApiVersion + canIUse and inside try/catch, and
 * applied through AttributeModifiers, so nothing above API 20 runs on older systems
 * (compatibleSdkVersion 6.0.0(20)).
 */
import { deviceInfo } from '@kit.BasicServicesKit';
import { uiMaterial } from '@kit.ArkUI';
import { hdsMaterial } from '@kit.UIDesignKit';
import { withAlpha } from './Theme';

export const LEVEL_EXQUISITE: number = 0;
export const LEVEL_GENTLE: number = 1;
export const LEVEL_SMOOTH: number = 2;

export class LightSense {
  private static done: boolean = false;
  private static mat: boolean = false;
  private static lvl: number = LEVEL_SMOOTH;

  private static init(): void {
    if (LightSense.done) {
      return;
    }
    LightSense.done = true;
    const api = deviceInfo.sdkApiVersion;
    let hds = false;
    try {
      hds = canIUse('SystemCapability.UIDesign.HDSComponent.Core');
    } catch (e) {
      hds = false;
    }
    let hdsImmersive = false;
    if (api >= 23 && hds) {
      try {
        const types: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes();
        hdsImmersive = types.indexOf(hdsMaterial.MaterialType.IMMERSIVE) >= 0;
      } catch (e) {
        hdsImmersive = false;
      }
    }
    LightSense.lvl = hdsImmersive ? LEVEL_EXQUISITE : LEVEL_SMOOTH;
    if (api >= 26) {
      try {
        LightSense.lvl = uiMaterial.getGlobalMaterialLevel();
        const info = uiMaterial.getMaterialInfo();
        LightSense.mat = uiMaterial.isImmersiveMaterialSupported() && info.state !== uiMaterial.MaterialState.DISABLE;
      } catch (e) {
        LightSense.mat = false;
      }
    }
  }

  /** ArkUI ImmersiveMaterial renders on this device (API ≥ 26) */
  static material(): boolean {
    LightSense.init();
    return LightSense.mat;
  }

  /** 0 EXQUISITE / 1 GENTLE / 2 SMOOTH */
  static level(): number {
    LightSense.init();
    return LightSense.lvl;
  }
}

/** Glass tints: dark theme / light theme, ImmersiveMaterial alpha, fallback alpha */
export const GLASS_TINT_DARK: string = '#0E1216';
export const GLASS_TINT_LIGHT: string = '#FFFFFF';
export const GLASS_ALPHA_DARK: number = 0.34;
export const GLASS_ALPHA_LIGHT: number = 0.46;
export const GLASS_FB_ALPHA_DARK: number = 0.5;
export const GLASS_FB_ALPHA_LIGHT: number = 0.6;

/** Plain values for the modifiers (they must not read @Trace state themselves). */
export class BarLook {
  on: boolean = true;
  dark: boolean = false;
}

/**
 * Navigation-bar surface. On → ImmersiveMaterial THIN with a neutral tint where supported, else heavy
 * backdrop blur with the same tint. Off → fully transparent (the page background shows, legacy look).
 */
export class BarGlassMod implements AttributeModifier<RowAttribute> {
  look: BarLook;

  constructor(look: BarLook) {
    this.look = look;
  }

  applyNormalAttribute(ins: RowAttribute): void {
    const l = this.look;
    if (!l.on) {
      ins.backgroundColor(Color.Transparent);
      return;
    }
    if (LightSense.material()) {
      ins.systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.THIN,
        materialColor: withAlpha(l.dark ? GLASS_TINT_DARK : GLASS_TINT_LIGHT, l.dark ? GLASS_ALPHA_DARK : GLASS_ALPHA_LIGHT),
        applyShadow: true,
        interactive: false,
        lightEffect: { color: '#FFFFFF' }
      }));
    } else {
      ins.backgroundColor(withAlpha(l.dark ? GLASS_TINT_DARK : GLASS_TINT_LIGHT,
        l.dark ? GLASS_FB_ALPHA_DARK : GLASS_FB_ALPHA_LIGHT));
      ins.backdropBlur(60);
      ins.shadow({ radius: 18, color: l.dark ? '#66000000' : '#1F000000', offsetY: 3 });
    }
  }
}

/**
 * Glass rim overlays (non-interactive, drawn above the surface, below the content):
 * kind 0 = 1px hairline, brightest on top, softer at the sides, dim at the bottom, plus a top sheen;
 * kind 1 = refraction rim: bright at both ends fading to clear in the middle, with an inset ring.
 */
export class GlassRimMod implements AttributeModifier<RowAttribute> {
  dark: boolean = false;
  kind: number = 0;

  constructor(dark: boolean, kind: number) {
    this.dark = dark;
    this.kind = kind;
  }

  applyNormalAttribute(ins: RowAttribute): void {
    const d = this.dark;
    if (this.kind === 0) {
      ins.border({
        width: 1,
        color: {
          top: withAlpha('#FFFFFF', d ? 0.42 : 0.95),
          left: withAlpha('#FFFFFF', d ? 0.3 : 0.85),
          right: withAlpha('#FFFFFF', d ? 0.3 : 0.85),
          bottom: withAlpha('#FFFFFF', d ? 0.14 : 0.6)
        }
      });
      ins.linearGradient({
        angle: 180,
        colors: [[withAlpha('#FFFFFF', d ? 0.1 : 0.32), 0], [withAlpha('#FFFFFF', 0), 0.45],
          [withAlpha('#FFFFFF', 0), 0.8], [withAlpha('#FFFFFF', d ? 0.04 : 0.12), 1]]
      });
    } else {
      ins.border({ width: 0.5, color: withAlpha('#FFFFFF', d ? 0.12 : 0.5) });
      ins.linearGradient({
        angle: 90,
        colors: [[withAlpha('#FFFFFF', d ? 0.16 : 0.34), 0], [withAlpha('#FFFFFF', 0), 0.07],
          [withAlpha('#FFFFFF', 0), 0.93], [withAlpha('#FFFFFF', d ? 0.16 : 0.34), 1]]
      });
    }
  }
}
