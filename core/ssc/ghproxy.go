package ssc

import (
	"crypto/sha256"
	"encoding/hex"
	"io"
	"mime"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

/**
 * ghproxy.go — GitHub-raw mirror proxy for the web UI.
 *
 * The Sub-Store front end loads its subscription icon collections (and the icons themselves) from
 * raw.githubusercontent.com, which is unreachable on a direct connection in mainland China (it only
 * loads when the phone runs a proxy). The server injects a small script into index.html that rewrites
 * those URLs to this same-origin endpoint; the endpoint fetches the file from a jsDelivr mirror
 * (several hostnames tried in order) and caches it under <dataDir>/ghcache, so icons load on a direct
 * connection and later loads are instant.
 */

const ghRawHost = "raw.githubusercontent.com"

// jsDelivr mirror bases, tried in order (path suffix: /gh/<user>/<repo>@<branch>/<file>).
var ghMirrorBases = []string{
	"https://cdn.jsdelivr.net",
	"https://fastly.jsdelivr.net",
	"https://gcore.jsdelivr.net",
	"https://testingcf.jsdelivr.net",
}

const ghMaxBody = 16 << 20

// ghMirrorPath translates the path after the raw host —
// "Koolson/Qure/master/Other/QureColor.json" → "gh/Koolson/Qure@master/Other/QureColor.json".
func ghMirrorPath(rest string) (string, bool) {
	parts := strings.Split(rest, "/")
	if len(parts) < 4 {
		return "", false
	}
	for _, p := range parts {
		if p == "" || p == "." || p == ".." || strings.ContainsAny(p, "\\?#@ ") {
			return "", false
		}
	}
	return "gh/" + parts[0] + "/" + parts[1] + "@" + parts[2] + "/" + strings.Join(parts[3:], "/"), true
}

// indexPatch is injected into the served index.html before any app script: it retargets
// raw.githubusercontent.com loads (fetch / XHR / <img src>) at the same-origin mirror proxy.
const indexPatch = `<script>(function(){try{
function M(u){if(typeof u!=="string")return u;var p="https://raw.githubusercontent.com/";return u.indexOf(p)===0?"/mss/gh/raw.githubusercontent.com/"+u.slice(p.length):u;}
if(window.fetch){var F=window.fetch;window.fetch=function(i,o){try{if(typeof i==="string")i=M(i);else if(i&&typeof i.url==="string"&&M(i.url)!==i.url)i=new Request(M(i.url),i);}catch(e){}return F.call(this,i,o);};}
var X=XMLHttpRequest.prototype.open;XMLHttpRequest.prototype.open=function(m,u){try{if(typeof u==="string")arguments[1]=M(u);}catch(e){}return X.apply(this,arguments);};
var D=Object.getOwnPropertyDescriptor(HTMLImageElement.prototype,"src");if(D&&D.set){Object.defineProperty(HTMLImageElement.prototype,"src",{configurable:true,enumerable:D.enumerable,get:D.get,set:function(v){D.set.call(this,M(v));}});}
var SA=Element.prototype.setAttribute;Element.prototype.setAttribute=function(n,v){try{if(this&&this.tagName==="IMG"&&String(n).toLowerCase()==="src")v=M(v);}catch(e){}return SA.call(this,n,v);};
}catch(e){}})();</script>`

// injectIndex inserts the patch right after <head> (falling back to prepending).
func injectIndex(html []byte) []byte {
	s := string(html)
	if i := strings.Index(s, "<head>"); i >= 0 {
		i += len("<head>")
		return []byte(s[:i] + indexPatch + s[i:])
	}
	return append([]byte(indexPatch), html...)
}

func (s *server) ghCacheDir() string {
	s.mu.Lock()
	d := s.engDir
	s.mu.Unlock()
	if d == "" {
		return ""
	}
	return filepath.Join(d, "ghcache")
}

// serveGHProxy handles GET /mss/gh/raw.githubusercontent.com/<user>/<repo>/<branch>/<file...>.
func (s *server) serveGHProxy(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	rest := strings.TrimPrefix(r.URL.Path, "/mss/gh/")
	tail, ok := strings.CutPrefix(rest, ghRawHost+"/")
	if !ok {
		http.Error(w, "unsupported host", http.StatusBadRequest)
		return
	}
	mirrorPath, ok := ghMirrorPath(tail)
	if !ok {
		http.Error(w, "bad path", http.StatusBadRequest)
		return
	}
	rawURL := "https://" + ghRawHost + "/" + tail

	// disk cache first
	dir := s.ghCacheDir()
	sum := sha256.Sum256([]byte(rawURL))
	ext := path.Ext(tail)
	if len(ext) > 9 {
		ext = ""
	}
	var cacheFile, typeFile string
	if dir != "" {
		key := hex.EncodeToString(sum[:]) + ext
		cacheFile = filepath.Join(dir, key)
		typeFile = cacheFile + ".mime"
		if data, err := os.ReadFile(cacheFile); err == nil && len(data) > 0 {
			ct := ""
			if b, err := os.ReadFile(typeFile); err == nil {
				ct = strings.TrimSpace(string(b))
			}
			s.ghServe(w, r, data, ct, ext)
			return
		}
	}

	client := &http.Client{Timeout: 10 * time.Second}
	var body []byte
	var ct string
	for _, base := range ghMirrorBases {
		req, err := http.NewRequestWithContext(r.Context(), http.MethodGet, base+"/"+mirrorPath, nil)
		if err != nil {
			continue
		}
		req.Header.Set("User-Agent", "SubStoreHO/"+CoreVersion)
		resp, err := client.Do(req)
		if err != nil {
			continue
		}
		data, err := io.ReadAll(io.LimitReader(resp.Body, ghMaxBody))
		resp.Body.Close()
		if err != nil || resp.StatusCode != http.StatusOK || len(data) == 0 {
			continue
		}
		body, ct = data, resp.Header.Get("Content-Type")
		break
	}
	if body == nil {
		s.Event("warn", "icon mirror fetch failed for "+tail)
		http.Error(w, "mirror fetch failed", http.StatusBadGateway)
		return
	}
	if cacheFile != "" {
		if err := os.MkdirAll(dir, 0o755); err == nil {
			tmp := cacheFile + ".tmp"
			if os.WriteFile(tmp, body, 0o644) == nil {
				os.Rename(tmp, cacheFile)
				os.WriteFile(typeFile, []byte(ct), 0o644)
			}
		}
	}
	s.ghServe(w, r, body, ct, ext)
}

func (s *server) ghServe(w http.ResponseWriter, r *http.Request, data []byte, ct string, ext string) {
	if ct == "" || strings.Contains(ct, "octet-stream") {
		if byExt := mime.TypeByExtension(ext); byExt != "" {
			ct = byExt
		}
	}
	if ct == "" {
		ct = http.DetectContentType(data)
	}
	w.Header().Set("Content-Type", ct)
	w.Header().Set("Cache-Control", "public, max-age=86400")
	w.Header().Set("Content-Length", strconv.Itoa(len(data)))
	if r.Method == http.MethodHead {
		return
	}
	w.Write(data)
}
