// libmimisubstore.so: cgo exports of the embedded Sub-Store backend (goja) + HTTP server, wrapped for ArkTS by napi.c.
package main

/*
#cgo LDFLAGS: -lace_napi.z
#include <stdlib.h>
*/
import "C"

import (
	"runtime/debug"
	"unsafe"

	"mimisubstore/core/ssc"
)

func init() {
	debug.SetMemoryLimit(160 << 20)
}

func cs(s string) *C.char { return C.CString(s) }

//export MsVersion
func MsVersion() *C.char { return cs(ssc.VersionJSON()) }

//export MsCall
func MsCall(js *C.char) *C.char { return cs(ssc.Call(C.GoString(js))) }

//export MsFree
func MsFree(p *C.char) { C.free(unsafe.Pointer(p)) }

func main() {}
