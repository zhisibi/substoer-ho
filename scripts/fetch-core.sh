#!/bin/bash
# Download the prebuilt libmimisubstore.so matching CORE_VERSION (entry/.../AppInfo.ets) from the repo's `dist`
# branch into entry/libs/arm64-v8a/, verifying SHA256SUMS.  Usage: scripts/fetch-core.sh [version]
set -e
cd "$(dirname "$0")/.."
VER=${1:-$(grep -oP "CORE_VERSION: string = '\K[^']+" entry/src/main/ets/common/AppInfo.ets)}
BASE=${CORE_BASE:-https://raw.githubusercontent.com/zhisibi/substoer-ho/dist/core/v$VER}
mkdir -p entry/libs/arm64-v8a
T=$(mktemp -d)
curl -fL --retry 2 -o $T/libmimisubstore.so $BASE/libmimisubstore.so
curl -fsSL -o $T/SHA256SUMS $BASE/SHA256SUMS
(cd $T && sha256sum -c SHA256SUMS)
mv $T/libmimisubstore.so entry/libs/arm64-v8a/libmimisubstore.so
rm -rf $T
echo "libmimisubstore.so $VER -> entry/libs/arm64-v8a/"
