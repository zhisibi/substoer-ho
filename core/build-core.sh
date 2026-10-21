#!/bin/bash
# Build libmimisubstore.so (Go: embedded Sub-Store backend (goja) + HTTP server + NAPI) for HarmonyOS arm64 with the OHOS Go fork.
# Needs host clang (ohos-cc wraps it with the OHOS sysroot). Output: $OUT/libmimisubstore.so
set -e
GM=${GM:-/workspace/work/gm}  # OHOS Go fork + ohos-cc wrapper
HERE=$(cd "$(dirname "$0")" && pwd)
export PATH=$GM/ohos-go/bin:$PATH GOTOOLCHAIN=local GOFLAGS=-mod=mod
export GOPATH=$GM/gopath GOMODCACHE=$GM/gopath/pkg/mod GOCACHE=/workspace/work/substore/gocache-ohos
export CGO_ENABLED=1 GOOS=openharmony GOARCH=arm64 CC=$GM/bin/ohos-cc CXX=$GM/bin/ohos-cc
export CGO_CFLAGS="-O2 -ftls-model=global-dynamic"
OUT=${OUT:-$HERE/out}
mkdir -p $OUT
cat > $OUT/exports.map <<'MAP'
{ global: MsVersion; MsCall; MsFree; local: *; };
MAP
cd $HERE
go build -trimpath -buildmode=c-shared \
  -ldflags "-s -w -linkmode external -extldflags '-Wl,--version-script=$OUT/exports.map -Wl,-z,lazy'" \
  -o $OUT/libmimisubstore.so .
ls -la $OUT/libmimisubstore.so
