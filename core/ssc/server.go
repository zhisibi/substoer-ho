package ssc

import (
	"context"
	"embed"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"mime"
	"net"
	"net/http"
	"net/url"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
)

//go:embed assets/backend.js
var backendJS []byte

//go:embed all:assets/web
var webFS embed.FS

// AccessLog is one line of the run log: a served request (kind "access") or an event (kind "event":
// start / stop / bind errors, Sub-Store console output, events the app reports).
type AccessLog struct {
	Seq    int64  `json:"seq"`
	Time   int64  `json:"time"` // unix ms
	Kind   string `json:"kind"` // access | event
	IP     string `json:"ip"`
	Method string `json:"method"`
	Path   string `json:"path"`
	Status int    `json:"status"`
	Bytes  int    `json:"bytes"`
	UA     string `json:"ua"`
	Ms     int64  `json:"ms"`
	Level  string `json:"level"`
	Msg    string `json:"msg"`
}

type Status struct {
	Running   bool   `json:"running"`
	Host      string `json:"host"`
	Port      int    `json:"port"`
	Started   int64  `json:"started"`
	Requests  int64  `json:"requests"`
	LastErr   string `json:"lastErr"`
	EngineOK  bool   `json:"engineOk"`
	EngineErr string `json:"engineErr"`
	InitMs    int64  `json:"initMs"`
	Backend   string `json:"backend"`
	Frontend  string `json:"frontend"`
	// the running backend / served web UI is a downloaded update (not the copy built into the .so)
	BackendUpdated  bool `json:"backendUpdated"`
	FrontendUpdated bool `json:"frontendUpdated"`
}

type server struct {
	mu        sync.Mutex
	srv       *http.Server
	port      int
	host      string
	started   int64
	requests  int64
	logs      []AccessLog
	seq       int64
	lastErr   string
	eng       *Engine
	engDir    string
	engErr    string
	initMs    int64
	allowLAN  bool // serve /download and /share to other devices
	lanStatic bool // also serve the web UI + API to other devices (off by default)
	backVer   string
	backUpd   bool
	web       fs.FS // web UI root (built-in or <dataDir>/update/web/dist)
	webVer    string
	webUpd    bool
}

var S = &server{}

const maxLogs = 2000

func (s *server) engine(dataDir string) (*Engine, error) {
	s.mu.Lock()
	if s.eng != nil && s.engDir == dataDir {
		e := s.eng
		s.mu.Unlock()
		return e, nil
	}
	old := s.eng
	s.eng = nil
	s.mu.Unlock()
	if old != nil {
		old.Stop()
	}
	t := time.Now()
	script, ver, fromUpd := activeBackend(dataDir)
	e := NewEngine(dataDir, script, func(level, msg string) { s.Event(level, msg) }, func(title, body string) {
		s.Event("notify", strings.TrimSpace(title+" "+body))
	})
	err := e.Wait()
	if err != nil && fromUpd {
		// a downloaded backend that does not start: set it aside and fall back to the built-in one
		e.Stop()
		s.Event("error", "downloaded Sub-Store backend "+ver+" failed to start ("+err.Error()+"), using the built-in "+BackendVersion)
		markBackendBad(dataDir)
		script, ver, fromUpd = backendJS, BackendVersion, false
		e = NewEngine(dataDir, script, func(level, msg string) { s.Event(level, msg) }, func(title, body string) {
			s.Event("notify", strings.TrimSpace(title+" "+body))
		})
		err = e.Wait()
	}
	ms := time.Since(t).Milliseconds()
	s.mu.Lock()
	s.initMs = ms
	if err != nil {
		s.engErr = err.Error()
		s.mu.Unlock()
		e.Stop()
		s.Event("error", "Sub-Store backend failed to start: "+err.Error())
		return nil, err
	}
	s.eng, s.engDir, s.engErr = e, dataDir, ""
	s.backVer, s.backUpd = ver, fromUpd
	s.mu.Unlock()
	src := "built-in"
	if fromUpd {
		src = "updated"
	}
	s.Event("info", fmt.Sprintf("Sub-Store backend %s (%s) ready in %d ms", ver, src, ms))
	return e, nil
}

// reloadWeb picks the web UI to serve (downloaded update if intact, else built-in).
func (s *server) reloadWeb(dataDir string) {
	w, v, upd := activeWeb(dataDir)
	s.mu.Lock()
	s.web, s.webVer, s.webUpd = w, v, upd
	s.mu.Unlock()
}

func (s *server) webRoot() fs.FS {
	s.mu.Lock()
	w := s.web
	s.mu.Unlock()
	if w == nil {
		w, _ = fs.Sub(webFS, "assets/web")
	}
	return w
}

// Start loads the backend (once per data dir) and listens on host:port.
// host "127.0.0.1" = this device only; "0.0.0.0" = LAN too (other devices get /download and /share only).
func (s *server) Start(host string, port int, dataDir string) error {
	if port <= 0 || port > 65535 {
		return errors.New("bad port")
	}
	if dataDir == "" {
		return errors.New("no data dir")
	}
	if _, err := s.engine(dataDir); err != nil {
		return err
	}
	s.reloadWeb(dataDir)
	s.Stop()
	if host == "" {
		host = "127.0.0.1"
	}
	addr := net.JoinHostPort(host, strconv.Itoa(port))
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		if strings.Contains(err.Error(), "address already in use") {
			err = fmt.Errorf("port %d is already in use", port)
		}
		s.Event("error", "bind "+addr+" failed: "+err.Error())
		s.mu.Lock()
		s.lastErr = err.Error()
		s.mu.Unlock()
		return err
	}
	srv := &http.Server{Handler: http.HandlerFunc(s.handle), ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout: 60 * time.Second, WriteTimeout: 180 * time.Second, IdleTimeout: 90 * time.Second}
	s.mu.Lock()
	s.srv, s.port, s.host = srv, port, host
	s.allowLAN = host != "127.0.0.1" && host != "localhost"
	s.started = time.Now().UnixMilli()
	s.lastErr = ""
	s.mu.Unlock()
	s.Event("info", "listening on "+addr)
	go func() {
		err := srv.Serve(ln)
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			s.mu.Lock()
			s.lastErr = err.Error()
			if s.srv == srv {
				s.srv = nil
			}
			s.mu.Unlock()
			s.Event("error", "server stopped: "+err.Error())
		}
	}()
	return nil
}

func (s *server) Stop() {
	s.mu.Lock()
	srv := s.srv
	s.srv = nil
	s.mu.Unlock()
	if srv != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		if err := srv.Shutdown(ctx); err != nil {
			srv.Close()
		}
		s.Event("info", "stopped")
	}
}

// Reset stops the server and the backend and deletes the Sub-Store store under dataDir.
func (s *server) Reset(dataDir string) {
	s.Stop()
	s.mu.Lock()
	e := s.eng
	s.eng, s.engDir = nil, ""
	s.mu.Unlock()
	if e != nil {
		e.Stop()
	}
	if dataDir != "" {
		os.RemoveAll(filepath.Join(dataDir, "store"))
		// downloaded backend/web code is code, not data: wiping must not leave it behind to be loaded again
		os.RemoveAll(filepath.Join(dataDir, "update"))
	}
	s.Event("warn", "all Sub-Store data deleted (downloaded updates removed too)")
}

func (s *server) SetLanUI(on bool) {
	s.mu.Lock()
	s.lanStatic = on
	s.mu.Unlock()
}

func (s *server) Event(level, msg string) {
	msg = redactText(msg)
	if len(msg) > 4000 {
		msg = msg[:4000] + "…"
	}
	s.addLog(AccessLog{Time: time.Now().UnixMilli(), Kind: "event", Level: level, Msg: msg})
}

func (s *server) addLog(l AccessLog) {
	s.mu.Lock()
	s.seq++
	l.Seq = s.seq
	s.logs = append(s.logs, l)
	if len(s.logs) > maxLogs {
		s.logs = append([]AccessLog(nil), s.logs[len(s.logs)-maxLogs:]...)
	}
	s.mu.Unlock()
}

func (s *server) Status() Status {
	s.mu.Lock()
	defer s.mu.Unlock()
	return Status{Running: s.srv != nil, Host: s.host, Port: s.port, Started: s.started, Requests: s.requests,
		LastErr: s.lastErr, EngineOK: s.eng != nil, EngineErr: s.engErr, InitMs: s.initMs,
		Backend: orStr(s.backVer, BackendVersion), Frontend: orStr(s.webVer, FrontendVersion),
		BackendUpdated: s.backUpd && s.eng != nil, FrontendUpdated: s.webUpd}
}

func orStr(a, b string) string {
	if a != "" {
		return a
	}
	return b
}

func (s *server) Logs(after int64) ([]AccessLog, int64) {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := []AccessLog{}
	for _, l := range s.logs {
		if l.Seq > after {
			out = append(out, l)
		}
	}
	return out, s.seq
}

func (s *server) ClearLogs() {
	s.mu.Lock()
	s.logs = nil
	s.mu.Unlock()
}

func isLoopback(ip string) bool {
	p := net.ParseIP(ip)
	return p != nil && p.IsLoopback()
}

func clientIP(r *http.Request) string {
	h, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return h
}

func isBackendPath(p string) bool {
	return p == "/api" || strings.HasPrefix(p, "/api/") || strings.HasPrefix(p, "/download/") || strings.HasPrefix(p, "/share/")
}

func isPublicPath(p string) bool {
	return strings.HasPrefix(p, "/download/") || strings.HasPrefix(p, "/share/")
}

type countingWriter struct {
	http.ResponseWriter
	status int
	n      int
}

func (c *countingWriter) WriteHeader(code int) { c.status = code; c.ResponseWriter.WriteHeader(code) }
func (c *countingWriter) Write(b []byte) (int, error) {
	if c.status == 0 {
		c.status = 200
	}
	n, err := c.ResponseWriter.Write(b)
	c.n += n
	return n, err
}

func (s *server) handle(w http.ResponseWriter, r *http.Request) {
	t0 := time.Now()
	cw := &countingWriter{ResponseWriter: w}
	ip := clientIP(r)
	local := isLoopback(ip)
	p := r.URL.Path
	backend := isBackendPath(p)
	s.mu.Lock()
	s.requests++
	lanUI := s.lanStatic
	eng := s.eng
	s.mu.Unlock()

	defer func() {
		// the web UI's own asset and API traffic stays out of the run log; downloads and remote access are logged
		if backend && strings.HasPrefix(p, "/api/") && local {
			return
		}
		if !backend && local {
			return
		}
		ua := r.UserAgent()
		if len(ua) > 160 {
			ua = ua[:160]
		}
		s.addLog(AccessLog{Time: t0.UnixMilli(), Kind: "access", IP: ip, Method: r.Method, Path: redactPath(r.URL),
			Status: cw.status, Bytes: cw.n, UA: ua, Ms: time.Since(t0).Milliseconds()})
	}()

	if !local && !lanUI && !isPublicPath(p) {
		http.Error(cw, "403 forbidden: only subscription links (/download, /share) are reachable from other devices", http.StatusForbidden)
		return
	}
	if strings.HasPrefix(p, "/mss/gh/") {
		s.serveGHProxy(cw, r)
		return
	}
	if backend {
		if eng == nil {
			http.Error(cw, "Sub-Store backend not running", http.StatusServiceUnavailable)
			return
		}
		s.dispatch(cw, r, eng)
		return
	}
	s.serveStatic(cw, r)
}

// sensitive query parameter names (matched case-insensitively, as substrings so access_token / api-key count too)
func sensitiveParam(name string) bool {
	n := strings.ToLower(name)
	for _, s := range []string{"token", "secret", "key", "password", "passwd", "auth", "credential"} {
		if strings.Contains(n, s) {
			return true
		}
	}
	return false
}

// redactQuery masks sensitive parameter values in place; a parameter whose value is itself a URL
// (url=…, the usual way subscription links ride inside a request) is parsed and redacted recursively.
func redactQuery(q url.Values) {
	for k, vs := range q {
		if sensitiveParam(k) {
			for i := range vs {
				vs[i] = "***"
			}
			q[k] = vs
			continue
		}
		for i, v := range vs {
			if strings.Contains(v, "://") {
				if u, err := url.Parse(v); err == nil && len(u.Query()) > 0 {
					inner := u.Query()
					redactQuery(inner)
					u.RawQuery = inner.Encode()
					vs[i] = u.String()
				}
			}
		}
		q[k] = vs
	}
}

var redactRe = regexp.MustCompile(`(?i)((?:token|secret|api[-_]?key|password|passwd|auth|credential)[a-z0-9_-]*=)([^&\s"'<>]+)`)

// redactText masks `name=value` secrets inside free text (engine console lines carry full subscription URLs).
func redactText(s string) string {
	return redactRe.ReplaceAllString(s, "${1}***")
}

func redactPath(u *url.URL) string {
	q := u.Query()
	redactQuery(q)
	out := u.Path
	if len(q) > 0 {
		out += "?" + q.Encode()
	}
	if len(out) > 300 {
		out = out[:300] + "…"
	}
	return out
}

func (s *server) dispatch(w http.ResponseWriter, r *http.Request, eng *Engine) {
	body, err := io.ReadAll(io.LimitReader(r.Body, 32<<20))
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	h := map[string]string{}
	for k, v := range r.Header {
		h[k] = strings.Join(v, ", ")
	}
	// The bundled web UI is same-origin; Sub-Store's non-node CORS allow-list doesn't know 127.0.0.1.
	if o := r.Header.Get("Origin"); o != "" {
		if ou, err := url.Parse(o); err == nil && (ou.Host == r.Host || isLoopback(ou.Hostname()) || ou.Hostname() == "localhost") {
			delete(h, "Origin")
		}
	}
	method := r.Method
	head := method == http.MethodHead
	if head {
		method = http.MethodGet
	}
	host := r.Host
	if host == "" {
		host = "127.0.0.1"
	}
	res, err := eng.Dispatch(method, "http://"+host+r.URL.RequestURI(), h, body, 150*time.Second)
	if err != nil {
		http.Error(w, "Sub-Store: "+err.Error(), http.StatusGatewayTimeout)
		return
	}
	for k, v := range res.Headers {
		if strings.EqualFold(k, "content-length") {
			continue
		}
		w.Header().Set(k, v)
	}
	w.Header().Set("Content-Length", strconv.Itoa(len(res.Body)))
	w.WriteHeader(res.Status)
	if !head {
		w.Write(res.Body)
	}
}

func (s *server) serveStatic(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	p := path.Clean("/" + r.URL.Path)
	root := s.webRoot()
	name := strings.TrimPrefix(p, "/")
	if p == "/" {
		name = "index.html"
	}
	data, err := fs.ReadFile(root, name)
	if err != nil {
		// SPA route → index.html (no extension); a missing file with an extension is a real 404
		if path.Ext(p) != "" {
			http.NotFound(w, r)
			return
		}
		name = "index.html"
		data, err = fs.ReadFile(root, name)
		if err != nil {
			http.NotFound(w, r)
			return
		}
	}
	if name == "index.html" {
		data = injectIndex(data)
	}
	ct := mime.TypeByExtension(path.Ext(name))
	if ct == "" {
		ct = http.DetectContentType(data)
	}
	if path.Ext(name) == ".webmanifest" {
		ct = "application/manifest+json"
	}
	w.Header().Set("Content-Type", ct)
	if strings.HasSuffix(name, "index.html") {
		w.Header().Set("Cache-Control", "no-cache")
	} else if strings.Contains(name, "/chunks/") || strings.Contains(name, "/css/") || strings.Contains(name, "/fonts/") {
		w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
	}
	w.Header().Set("Content-Length", strconv.Itoa(len(data)))
	if r.Method == http.MethodHead {
		return
	}
	w.Write(data)
}

// IfAddr is one IPv4 address with the name of its interface (the app filters VPN / TUN / cellular links by name).
type IfAddr struct {
	Name string `json:"name"`
	IP   string `json:"ip"`
}

func LocalIPv4Addrs() []IfAddr {
	out := []IfAddr{}
	ifs, err := net.Interfaces()
	if err != nil {
		return out
	}
	for _, i := range ifs {
		if i.Flags&net.FlagUp == 0 || i.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, _ := i.Addrs()
		for _, a := range addrs {
			if ipn, ok := a.(*net.IPNet); ok && ipn.IP.To4() != nil {
				out = append(out, IfAddr{Name: i.Name, IP: ipn.IP.String()})
			}
		}
	}
	return out
}
