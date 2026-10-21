/** Fixed app facts shown in Settings › About and used by the legal pages. */
import { bundleManager } from '@kit.AbilityKit';

export const DEVELOPER: string = '张世博';
export const CONTACT_EMAIL: string = 'zhisibi@gmail.com';
/** Published on the 猫Mo家族 site (zh pages; *_en.html for English) */
export const PRIVACY_URL: string = 'https://aimm.886423.xyz/cats/mimisubstore/privacy.html';
export const TERMS_URL: string = 'https://aimm.886423.xyz/cats/mimisubstore/terms.html';
export const PRIVACY_URL_EN: string = 'https://aimm.886423.xyz/cats/mimisubstore/privacy_en.html';
export const TERMS_URL_EN: string = 'https://aimm.886423.xyz/cats/mimisubstore/terms_en.html';
/** Version of libmimisubstore.so this app expects (core/ssc CoreVersion) */
export const CORE_VERSION: string = '1.1.0';
export const DEFAULT_PORT: number = 3000;

let cachedVersion: string = '';

/** versionName from the installed bundle, e.g. "1.0.0" */
export function versionName(): string {
  if (cachedVersion.length > 0) {
    return cachedVersion;
  }
  try {
    const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
    cachedVersion = info.versionName;
  } catch (e) {
    cachedVersion = '1.0.0';
  }
  return cachedVersion;
}
