/** Fixed app facts shown in 服务管理 › 关于 and used by the legal pages. */
import { bundleManager } from '@kit.AbilityKit';

export const APP_NAME: string = '咪咪SubStore';
export const DEVELOPER: string = '张世博';
/** 问题反馈 QQ 群（关于页显示群号，点按复制） */
export const FEEDBACK_QQ_GROUP: string = '1127250124';
/** 特别版 (special branch only): the app is gated behind an invite code until unlocked once. */
export const SPECIAL_EDITION: boolean = true;
/** 特别版 cross-promotion target: MimiSSH on AppGallery. */
export const MIMISSH_STORE_URL: string =
  'https://appgallery.huawei.com/app/detail?id=com.catssh.zhisibi&channelId=SHARE&source=appshare';
/** 特别版 developer QQ for invite codes. */
export const DEV_QQ: string = '526174637';
/** Source code (AGPL-3.0), releases, issues */
export const REPO_URL: string = 'https://github.com/zhisibi/substoer-ho';
export const REPO_NAME: string = 'github.com/zhisibi/substoer-ho';
/** The same disclaimer & privacy notice, published with the source */
export const DISCLAIMER_URL: string = 'https://github.com/zhisibi/substoer-ho/blob/main/docs/disclaimer.md';
export const DISCLAIMER_URL_EN: string = 'https://github.com/zhisibi/substoer-ho/blob/main/docs/disclaimer.en.md';
export const PRIVACY_URL: string = 'https://github.com/zhisibi/substoer-ho/blob/main/docs/privacy.md';
export const PRIVACY_URL_EN: string = 'https://github.com/zhisibi/substoer-ho/blob/main/docs/privacy.en.md';
export const TERMS_URL: string = 'https://github.com/zhisibi/substoer-ho/blob/main/docs/terms.md';
export const TERMS_URL_EN: string = 'https://github.com/zhisibi/substoer-ho/blob/main/docs/terms.en.md';
export const UPSTREAM_URL: string = 'https://github.com/sub-store-org/Sub-Store';
/** Version of libmimisubstore.so this app expects (core/ssc CoreVersion) */
export const CORE_VERSION: string = '1.2.0';
export const DEFAULT_PORT: number = 3000;

let cachedVersion: string = '';

/** versionName from the installed bundle, e.g. "1.2.0" */
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
