#!/bin/bash
# Fetch upstream Sub-Store (backend source at BACKEND_TAG + frontend dist at FRONTEND_TAG), build the embedded
# backend bundle (patched express adapter, ES2020, indirect eval for goja) and copy the web UI into ssc/assets.
# Needs node + network. Output: core/ssc/assets/backend.js, core/ssc/assets/web/**
set -e
BACKEND_TAG=${BACKEND_TAG:-2.42.6}
FRONTEND_TAG=${FRONTEND_TAG:-2.34.1}
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$HERE/.build}
ASSETS=$HERE/../ssc/assets
mkdir -p $WORK
cd $WORK
if [ ! -d Sub-Store-$BACKEND_TAG ]; then
  git clone --depth 1 --branch $BACKEND_TAG https://github.com/sub-store-org/Sub-Store.git Sub-Store-$BACKEND_TAG
fi
cd Sub-Store-$BACKEND_TAG/backend
git checkout -- src/vendor/express.js src/utils/yaml.js
git apply $HERE/substore-hm.patch || git apply --3way $HERE/substore-hm.patch
cp $HERE/sub-store-hm.js src/products/sub-store-hm.js
cp $HERE/build-hm.js build-hm.js
[ -d node_modules ] || npx -y pnpm@${PNPM_VERSION:-11.0.9} install --frozen-lockfile || npx -y pnpm@${PNPM_VERSION:-11.0.9} install
node build-hm.js 2>&1 | grep -v 'direct-eval\|direct eval\|esbuild.github.io\|│\|╵\|^$\|src/utils\|src/vendor\|src/core\|src/restful' || true
mkdir -p $ASSETS
cp dist/sub-store-hm.js $ASSETS/backend.js
cd $WORK
[ -f dist-$FRONTEND_TAG.zip ] || curl -fsSL -o dist-$FRONTEND_TAG.zip https://github.com/sub-store-org/Sub-Store-Front-End/releases/download/$FRONTEND_TAG/dist.zip
rm -rf fe && mkdir fe && (cd fe && unzip -q ../dist-$FRONTEND_TAG.zip)
rm -rf $ASSETS/web && cp -r fe/dist $ASSETS/web
cd $ASSETS/web
# no service worker / PWA install inside the app; drop precompressed duplicates
find . -name '*.gz' -delete
rm -f sw.js registerSW.js workbox-*.js vercel.json
sed -i 's|<script id="vite-plugin-pwa:register-sw" src="/registerSW.js"></script>||' index.html
ls -la $ASSETS/backend.js; du -sh $ASSETS/web
