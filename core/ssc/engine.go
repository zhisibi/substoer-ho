package ssc

// Embedded Sub-Store backend: runs the Sub-Store JS bundle (sub-store-hm.js,
// built from upstream with a patched express adapter) in goja, presenting a
// GUI.for.Cores-style host ($Plugins) for storage, HTTP and notifications.

import (
	"bytes"
	"crypto/tls"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/dop251/goja"
	"github.com/dop251/goja_nodejs/console"
	"github.com/dop251/goja_nodejs/eventloop"
	"github.com/dop251/goja_nodejs/require"
	gurl "github.com/dop251/goja_nodejs/url"
)

type Engine struct {
	loop    *eventloop.EventLoop
	dataDir string
	store   *KV
	logf    func(level, msg string)
	notify  func(title, body string)
	ready   chan error
	ua      string
}

type JSResponse struct {
	Status  int
	Headers map[string]string
	Body    []byte
}

// KV is the persistent store behind $Plugins.SubStoreCache (one JSON file per key).
type KV struct {
	mu  sync.Mutex
	dir string
	mem map[string]string
}

func NewKV(dir string) *KV {
	os.MkdirAll(dir, 0o700)
	return &KV{dir: dir, mem: map[string]string{}}
}

func kvFile(dir, key string) string {
	return filepath.Join(dir, url.PathEscape(key)+".json")
}

func (k *KV) Get(key string) (string, bool) {
	k.mu.Lock()
	defer k.mu.Unlock()
	if v, ok := k.mem[key]; ok {
		return v, true
	}
	b, err := os.ReadFile(kvFile(k.dir, key))
	if err != nil {
		return "", false
	}
	k.mem[key] = string(b)
	return string(b), true
}

func (k *KV) Set(key, val string) error {
	k.mu.Lock()
	defer k.mu.Unlock()
	k.mem[key] = val
	p := kvFile(k.dir, key)
	tmp := p + ".tmp"
	if err := os.WriteFile(tmp, []byte(val), 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, p)
}

func (k *KV) Remove(key string) {
	k.mu.Lock()
	defer k.mu.Unlock()
	delete(k.mem, key)
	os.Remove(kvFile(k.dir, key))
}

func NewEngine(dataDir string, script []byte, logf func(level, msg string), notify func(title, body string)) *Engine {
	e := &Engine{dataDir: dataDir, store: NewKV(filepath.Join(dataDir, "store")), logf: logf, notify: notify, ready: make(chan error, 1)}
	reg := require.NewRegistry()
	reg.RegisterNativeModule(console.ModuleName, console.RequireWithPrinter(e))
	e.loop = eventloop.NewEventLoop(eventloop.WithRegistry(reg), eventloop.EnableConsole(true))
	e.loop.Start()
	e.loop.RunOnLoop(func(vm *goja.Runtime) {
		err := e.setup(vm, script)
		e.ready <- err
	})
	return e
}

// console printer
func (e *Engine) Log(s string)   { e.logf("info", s) }
func (e *Engine) Warn(s string)  { e.logf("warn", s) }
func (e *Engine) Error(s string) { e.logf("error", s) }

func (e *Engine) Wait() error { return <-e.ready }

func (e *Engine) Stop() { e.loop.Stop() }

var httpClient = &http.Client{
	Transport: &http.Transport{
		Proxy:               nil,
		TLSClientConfig:     &tls.Config{},
		MaxIdleConnsPerHost: 4,
		IdleConnTimeout:     60 * time.Second,
	},
}

func (e *Engine) setup(vm *goja.Runtime, script []byte) error {
	gurl.Enable(vm)
	g := vm.GlobalObject()
	g.Set("__SS_HM__", true)
	g.Set("$done", func(goja.Value) {})
	installPolyfills(vm)
	g.Set("__hm_yamlParse", func(s string) goja.Value {
		if out, ok := yamlToJSON(s); ok {
			return vm.ToValue(out)
		}
		return goja.Null()
	})

	cache := vm.NewObject()
	cache.Set("get", func(key string) goja.Value {
		if v, ok := e.store.Get(key); ok {
			return vm.ToValue(v)
		}
		return goja.Null()
	})
	cache.Set("set", func(key string, val goja.Value) bool {
		s := ""
		if !goja.IsUndefined(val) && !goja.IsNull(val) {
			s = val.String()
		}
		if err := e.store.Set(key, s); err != nil {
			e.logf("error", "store set "+key+": "+err.Error())
			return false
		}
		return true
	})
	cache.Set("remove", func(key string) bool { e.store.Remove(key); return true })

	plugins := vm.NewObject()
	plugins.Set("SubStoreCache", cache)
	plugins.Set("Notify", func(title, body string) {
		if e.notify != nil {
			e.notify(title, body)
		}
		e.logf("notify", title+" "+body)
	})
	plugins.Set("Requests", func(opts map[string]interface{}) *goja.Promise {
		p, resolve, reject := vm.NewPromise()
		go func() {
			res, err := e.doRequest(opts)
			e.loop.RunOnLoop(func(vm *goja.Runtime) {
				if err != nil {
					reject(vm.NewGoError(err))
					return
				}
				resolve(res)
			})
		}()
		return p
	})
	g.Set("$Plugins", plugins)
	g.Set("$Plugin", map[string]interface{}{"name": "MimiSubStore"})

	prog, err := goja.Compile("sub-store-hm.js", string(script), false)
	if err != nil {
		return err
	}
	if _, err := vm.RunProgram(prog); err != nil {
		return err
	}
	if fn, ok := goja.AssertFunction(g.Get("__ssDispatch")); !ok || fn == nil {
		return errors.New("__ssDispatch not registered")
	}
	return nil
}

func (e *Engine) doRequest(opts map[string]interface{}) (map[string]interface{}, error) {
	method, _ := opts["method"].(string)
	if method == "" {
		method = "GET"
	}
	u, _ := opts["url"].(string)
	var body io.Reader
	switch b := opts["body"].(type) {
	case string:
		body = strings.NewReader(b)
	case nil:
	default:
		j, _ := json.Marshal(b)
		body = bytes.NewReader(j)
	}
	timeout := 15 * time.Second
	client := httpClient
	if o, ok := opts["options"].(map[string]interface{}); ok {
		if t, ok := toFloat(o["Timeout"]); ok && t > 0 {
			timeout = time.Duration(t * float64(time.Second))
		}
		if px, ok := o["Proxy"].(string); ok && px != "" {
			if pu, err := url.Parse(px); err == nil {
				client = &http.Client{Transport: &http.Transport{Proxy: http.ProxyURL(pu)}}
			}
		}
	}
	req, err := http.NewRequest(strings.ToUpper(method), u, body)
	if err != nil {
		return nil, err
	}
	if h, ok := opts["headers"].(map[string]interface{}); ok {
		for k, v := range h {
			if v == nil {
				continue
			}
			req.Header.Set(k, fmt.Sprint(v))
		}
	}
	if req.Header.Get("User-Agent") == "" {
		req.Header.Set("User-Agent", "Sub-Store MimiSubStore")
	}
	c := *client
	c.Timeout = timeout
	resp, err := c.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 64<<20))
	if err != nil {
		return nil, err
	}
	hdr := map[string]interface{}{}
	for k, v := range resp.Header {
		hdr[strings.ToLower(k)] = strings.Join(v, ", ")
	}
	return map[string]interface{}{"status": resp.StatusCode, "headers": hdr, "body": string(data)}, nil
}

func toFloat(v interface{}) (float64, bool) {
	switch n := v.(type) {
	case float64:
		return n, true
	case int64:
		return float64(n), true
	case int:
		return float64(n), true
	}
	return 0, false
}

// Dispatch runs one HTTP request through the Sub-Store router.
func (e *Engine) Dispatch(method, rawURL string, headers map[string]string, body []byte, timeout time.Duration) (*JSResponse, error) {
	ch := make(chan *JSResponse, 1)
	ok := e.loop.RunOnLoop(func(vm *goja.Runtime) {
		fn, _ := goja.AssertFunction(vm.Get("__ssDispatch"))
		req := vm.NewObject()
		req.Set("method", method)
		req.Set("url", rawURL)
		h := vm.NewObject()
		for k, v := range headers {
			h.Set(k, v)
		}
		req.Set("headers", h)
		req.Set("body", string(body))
		var once sync.Once
		req.Set("__done", func(r *goja.Object) {
			once.Do(func() { ch <- toResponse(vm, r) })
		})
		if _, err := fn(goja.Undefined(), req); err != nil {
			once.Do(func() {
				ch <- &JSResponse{Status: 500, Headers: map[string]string{"Content-Type": "application/json"}, Body: []byte(fmt.Sprintf(`{"status":"failed","message":%q}`, err.Error()))}
			})
		}
	})
	if !ok {
		return nil, errors.New("engine stopped")
	}
	select {
	case r := <-ch:
		return r, nil
	case <-time.After(timeout):
		return nil, errors.New("timeout")
	}
}

func toResponse(vm *goja.Runtime, r *goja.Object) *JSResponse {
	res := &JSResponse{Status: 200, Headers: map[string]string{}}
	if r == nil {
		return res
	}
	if s := r.Get("status"); s != nil && !goja.IsUndefined(s) {
		res.Status = int(s.ToInteger())
		if res.Status == 0 {
			res.Status = 200
		}
	}
	if h, ok := r.Get("headers").(*goja.Object); ok && h != nil {
		for _, k := range h.Keys() {
			v := h.Get(k)
			if v == nil || goja.IsUndefined(v) || goja.IsNull(v) {
				continue
			}
			res.Headers[k] = v.String()
		}
	}
	b := r.Get("body")
	if b != nil && !goja.IsUndefined(b) && !goja.IsNull(b) {
		switch x := b.Export().(type) {
		case string:
			res.Body = []byte(x)
		case []byte:
			res.Body = x
		case goja.ArrayBuffer:
			res.Body = x.Bytes()
		default:
			if o, ok := b.(*goja.Object); ok {
				if ab, ok := o.Export().(goja.ArrayBuffer); ok {
					res.Body = ab.Bytes()
					break
				}
			}
			res.Body = []byte(b.String())
		}
	}
	return res
}
