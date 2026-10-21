import { hapTasks } from '@ohos/hvigor-ohos-plugin';
import * as fs from 'fs';
import * as path from 'path';

/**
 * Fails the build when the native core entry/libs/arm64-v8a/libmimisubstore.so is missing (gitignored; built by
 * core/build-core.sh): a HAP without it compiles but cannot run Sub-Store.
 */
function coreCheck() {
  return {
    pluginId: 'mimisubstoreCoreCheck',
    apply(): void {
      const so = path.join(__dirname, 'libs', 'arm64-v8a', 'libmimisubstore.so');
      if (!fs.existsSync(so) || fs.statSync(so).size < 100000) {
        throw new Error('\n缺少内核 entry/libs/arm64-v8a/libmimisubstore.so —— 请先运行 core/substore/prepare.sh 与 core/build-core.sh，\n' +
          '再把 core/out/libmimisubstore.so 复制到该目录（见 README）。\n' +
          'Missing the native core entry/libs/arm64-v8a/libmimisubstore.so: run core/substore/prepare.sh and core/build-core.sh,\n' +
          'then copy core/out/libmimisubstore.so there (see README).\n');
      }
    }
  };
}

export default {
  system: hapTasks,
  plugins: [coreCheck()]
}
