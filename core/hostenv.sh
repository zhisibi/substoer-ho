# source me: host (linux/arm64) Go env for unit tests, using the OHOS Go fork as a plain linux toolchain
GM=${GM:-$HOME/workspace/lanbox-build/gm}
export PATH=$GM/ohos-go/bin:$PATH GOTOOLCHAIN=local GOFLAGS=-mod=mod
export GOPATH=$GM/gopath GOMODCACHE=$GM/gopath/pkg/mod GOCACHE=/workspace/work/substore/gocache-host
unset GOOS GOARCH CGO_ENABLED CC CXX
