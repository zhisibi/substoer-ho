package ssc

import (
	"crypto/rand"
	"encoding/base64"
	"time"
	"unicode/utf8"

	"github.com/dop251/goja"
)

var start = time.Now()

func installPolyfills(vm *goja.Runtime) {
	g := vm.GlobalObject()
	g.Set("__hm_utf8enc", func(s string) goja.ArrayBuffer { return vm.NewArrayBuffer([]byte(s)) })
	g.Set("__hm_utf8dec", func(v goja.Value) string {
		b := bytesOf(vm, v)
		if utf8.Valid(b) {
			return string(b)
		}
		r := make([]rune, 0, len(b))
		for len(b) > 0 {
			c, n := utf8.DecodeRune(b)
			r = append(r, c)
			b = b[n:]
		}
		return string(r)
	})
	g.Set("__hm_rand", func(n int) goja.ArrayBuffer {
		b := make([]byte, n)
		rand.Read(b)
		return vm.NewArrayBuffer(b)
	})
	g.Set("__hm_now", func() float64 { return float64(time.Since(start).Microseconds()) / 1000 })
	g.Set("__hm_btoa", func(s string) (string, error) {
		b := make([]byte, 0, len(s))
		for _, r := range s {
			if r > 255 {
				panic(vm.NewTypeError("btoa: invalid character"))
			}
			b = append(b, byte(r))
		}
		return base64.StdEncoding.EncodeToString(b), nil
	})
	g.Set("__hm_atob", func(s string) string {
		clean := make([]byte, 0, len(s))
		for i := 0; i < len(s); i++ {
			c := s[i]
			if c == ' ' || c == '\n' || c == '\r' || c == '\t' {
				continue
			}
			clean = append(clean, c)
		}
		for len(clean)%4 != 0 {
			clean = append(clean, '=')
		}
		b, err := base64.StdEncoding.DecodeString(string(clean))
		if err != nil {
			b, err = base64.RawStdEncoding.DecodeString(string(trimEq(clean)))
			if err != nil {
				panic(vm.NewTypeError("atob: invalid base64"))
			}
		}
		r := make([]rune, len(b))
		for i, c := range b {
			r[i] = rune(c)
		}
		return string(r)
	})
	if _, err := vm.RunString(polyfillJS); err != nil {
		panic(err)
	}
}

func trimEq(b []byte) []byte {
	for len(b) > 0 && b[len(b)-1] == '=' {
		b = b[:len(b)-1]
	}
	return b
}

func bytesOf(vm *goja.Runtime, v goja.Value) []byte {
	if v == nil || goja.IsUndefined(v) || goja.IsNull(v) {
		return nil
	}
	switch x := v.Export().(type) {
	case goja.ArrayBuffer:
		return x.Bytes()
	case []byte:
		return x
	}
	o := v.ToObject(vm)
	if buf, ok := o.Get("buffer").Export().(goja.ArrayBuffer); ok {
		off := int(o.Get("byteOffset").ToInteger())
		ln := int(o.Get("byteLength").ToInteger())
		b := buf.Bytes()
		// bounds-check JS-supplied offsets: an out-of-range view must not panic the backend loop
		if off < 0 || ln < 0 || off > len(b) || ln > len(b)-off {
			return nil
		}
		return b[off : off+ln]
	}
	return nil
}

const polyfillJS = `
(function(g){
  if (typeof g.TextEncoder === 'undefined') {
    g.TextEncoder = class TextEncoder { get encoding(){return 'utf-8'} encode(s){ return new Uint8Array(__hm_utf8enc(String(s===undefined?'':s))); } };
  }
  if (typeof g.TextDecoder === 'undefined') {
    g.TextDecoder = class TextDecoder { constructor(l){this.encoding=(l||'utf-8')} decode(b){ if(b===undefined) return ''; return __hm_utf8dec(b); } };
  }
  if (typeof g.btoa === 'undefined') g.btoa = (s) => __hm_btoa(String(s));
  if (typeof g.atob === 'undefined') g.atob = (s) => __hm_atob(String(s));
  if (typeof g.crypto === 'undefined') g.crypto = {};
  if (!g.crypto.getRandomValues) g.crypto.getRandomValues = (a) => { const r = new Uint8Array(__hm_rand(a.byteLength)); new Uint8Array(a.buffer, a.byteOffset, a.byteLength).set(r); return a; };
  if (!g.crypto.randomUUID) g.crypto.randomUUID = () => { const b = new Uint8Array(__hm_rand(16)); b[6]=(b[6]&15)|64; b[8]=(b[8]&63)|128; const h=[...b].map(x=>x.toString(16).padStart(2,'0')).join(''); return h.slice(0,8)+'-'+h.slice(8,12)+'-'+h.slice(12,16)+'-'+h.slice(16,20)+'-'+h.slice(20); };
  if (typeof g.performance === 'undefined') g.performance = { now: () => __hm_now() };
  if (typeof g.queueMicrotask === 'undefined') g.queueMicrotask = (f) => Promise.resolve().then(f);
  if (typeof g.structuredClone === 'undefined') g.structuredClone = (v) => v === undefined ? undefined : JSON.parse(JSON.stringify(v));
  if (typeof g.self === 'undefined') g.self = g;
})(globalThis);
`
