package ssc

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestGHMirrorPath(t *testing.T) {
	good := map[string]string{
		"Koolson/Qure/master/Other/QureColor.json":      "gh/Koolson/Qure@master/Other/QureColor.json",
		"u/r/main/a/b/c.png":                            "gh/u/r@main/a/b/c.png",
		"sub-store-org/Sub-Store/main/backend/src/x.js": "gh/sub-store-org/Sub-Store@main/backend/src/x.js",
	}
	for in, want := range good {
		got, ok := ghMirrorPath(in)
		if !ok || got != want {
			t.Errorf("ghMirrorPath(%q) = %q,%v want %q", in, got, ok, want)
		}
	}
	for _, bad := range []string{"", "a/b", "a/b/c", "a//c/d", "a/../c/d", "a/b/c d/e", "a/b/@x/d"} {
		if _, ok := ghMirrorPath(bad); ok {
			t.Errorf("ghMirrorPath(%q) unexpectedly ok", bad)
		}
	}
}

func TestGHProxyServesAndCaches(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/gh/Koolson/Qure@master/Other/QureColor.json" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"icons":[]}`))
	}))
	defer upstream.Close()
	old := ghMirrorBases
	ghMirrorBases = []string{upstream.URL}
	defer func() { ghMirrorBases = old }()

	dir := t.TempDir()
	s := &server{engDir: dir}
	req := httptest.NewRequest(http.MethodGet, "/mss/gh/raw.githubusercontent.com/Koolson/Qure/master/Other/QureColor.json", nil)
	rec := httptest.NewRecorder()
	s.serveGHProxy(rec, req)
	if rec.Code != 200 || !strings.Contains(rec.Body.String(), `"icons"`) {
		t.Fatalf("first fetch: code=%d body=%q", rec.Code, rec.Body.String())
	}
	if rec.Header().Get("Content-Type") != "application/json" {
		t.Fatalf("content-type = %q", rec.Header().Get("Content-Type"))
	}
	// second fetch must come from the disk cache (upstream closed by then would still pass)
	entries, _ := filepath.Glob(filepath.Join(dir, "ghcache", "*.json"))
	if len(entries) != 1 {
		t.Fatalf("cache entries = %v", entries)
	}
	rec2 := httptest.NewRecorder()
	s.serveGHProxy(rec2, req)
	if rec2.Code != 200 || rec2.Body.String() != rec.Body.String() {
		t.Fatalf("cached fetch: code=%d", rec2.Code)
	}
	// wrong host rejected
	bad := httptest.NewRequest(http.MethodGet, "/mss/gh/example.com/a/b/c/d", nil)
	rec3 := httptest.NewRecorder()
	s.serveGHProxy(rec3, bad)
	if rec3.Code != http.StatusBadRequest {
		t.Fatalf("bad host code = %d", rec3.Code)
	}
	// cached file is inside ghcache, nothing written elsewhere
	if _, err := os.Stat(filepath.Join(dir, "ghcache")); err != nil {
		t.Fatal(err)
	}
}

func TestInjectIndex(t *testing.T) {
	out := string(injectIndex([]byte("<html><head><title>x</title></head>")))
	if !strings.Contains(out, "<head><script>") || !strings.Contains(out, "/mss/gh/raw.githubusercontent.com/") {
		t.Fatalf("patch not injected after <head>: %q", out[:120])
	}
	out2 := string(injectIndex([]byte("<html>no head</html>")))
	if !strings.HasPrefix(out2, "<script>") {
		t.Fatalf("fallback prepend failed")
	}
}
