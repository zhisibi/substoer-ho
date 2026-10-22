package ssc

// In-app update of the Sub-Store backend / web UI.
//
// The repo's GitHub Actions workflow (.github/workflows/substore-assets.yml) follows upstream releases, builds the
// backend with the same patches as core/substore/prepare.sh, smoke-tests it with cmd/hostrun and publishes
//   release "substore-<backend>-<frontend>": backend.js, web.zip
//   release "substore-latest": manifest.json (absolute URLs of the files above + sha256)
// The app downloads them into <dataDir>/update/{backend,web}; the built-in copies stay in the .so and are used
// whenever the update is missing, damaged, incompatible or fails to start (and after 恢复内置版本).

import (
	"archive/zip"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"net"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// HostAPI is the contract between this core and a backend.js build (global __ssDispatch, $Plugins host,
// __hm_yamlParse…). The workflow writes the API its patches target into the manifest; a mismatch is refused.
const HostAPI = 1

// DefaultManifestURL is where the workflow publishes the manifest.
const DefaultManifestURL = "https://github.com/zhisibi/substoer-ho/releases/download/substore-latest/manifest.json"

type ManifestPart struct {
	Version string `json:"version"`
	URL     string `json:"url"`
	SHA256  string `json:"sha256"`
	Size    int64  `json:"size"`
}

type Manifest struct {
	Schema   int          `json:"schema"`
	HostAPI  int          `json:"hostApi"`
	MinCore  string       `json:"minCore"`
	Built    string       `json:"built"`
	Backend  ManifestPart `json:"backend"`
	Frontend ManifestPart `json:"frontend"`
}

// installed is <dataDir>/update/<part>/version.json
type installed struct {
	Version string `json:"version"`
	SHA256  string `json:"sha256"`
	Time    int64  `json:"time"`
}

func updRoot(dataDir string) string { return filepath.Join(dataDir, "update") }

func readInstalled(dir string) (installed, bool) {
	var v installed
	b, err := os.ReadFile(filepath.Join(dir, "version.json"))
	if err != nil || json.Unmarshal(b, &v) != nil || v.Version == "" {
		return v, false
	}
	return v, true
}

// activeBackend returns the backend script to run: the downloaded one if present and intact, else built-in.
func activeBackend(dataDir string) (script []byte, ver string, fromUpdate bool) {
	dir := filepath.Join(updRoot(dataDir), "backend")
	if v, ok := readInstalled(dir); ok {
		if b, err := os.ReadFile(filepath.Join(dir, "backend.js")); err == nil && sha256Hex(b) == v.SHA256 {
			return b, v.Version, true
		}
	}
	return backendJS, BackendVersion, false
}

// activeWeb returns the web UI file system (rooted at the dist folder).
func activeWeb(dataDir string) (fs.FS, string, bool) {
	dir := filepath.Join(updRoot(dataDir), "web")
	if v, ok := readInstalled(dir); ok {
		if st, err := os.Stat(filepath.Join(dir, "dist", "index.html")); err == nil && !st.IsDir() {
			return os.DirFS(filepath.Join(dir, "dist")), v.Version, true
		}
	}
	sub, _ := fs.Sub(webFS, "assets/web")
	return sub, FrontendVersion, false
}

// markBackendBad moves a downloaded backend that failed to start aside so the built-in one is used next time.
func markBackendBad(dataDir string) {
	dir := filepath.Join(updRoot(dataDir), "backend")
	bad := dir + ".bad"
	os.RemoveAll(bad)
	os.Rename(dir, bad)
}

func sha256Hex(b []byte) string {
	h := sha256.Sum256(b)
	return hex.EncodeToString(h[:])
}

// verNewer reports a > b for dotted numeric versions ("2.42.10" > "2.42.6").
func verNewer(a, b string) bool {
	pa, pb := strings.Split(a, "."), strings.Split(b, ".")
	for i := 0; i < len(pa) || i < len(pb); i++ {
		var x, y int
		if i < len(pa) {
			x, _ = strconv.Atoi(strings.TrimLeft(pa[i], "v"))
		}
		if i < len(pb) {
			y, _ = strconv.Atoi(strings.TrimLeft(pb[i], "v"))
		}
		if x != y {
			return x > y
		}
	}
	return false
}

var updClient = &http.Client{Timeout: 120 * time.Second, Transport: &http.Transport{
	Proxy:                 http.ProxyFromEnvironment,
	DialContext:           (&net.Dialer{Timeout: 10 * time.Second}).DialContext,
	TLSHandshakeTimeout:   10 * time.Second,
	ResponseHeaderTimeout: 20 * time.Second,
}}

// fetch downloads url, trying each mirror prefix in order ("" = direct). Returns the body and the prefix used.
func fetch(url string, mirrors []string, max int64) ([]byte, string, error) {
	if len(mirrors) == 0 {
		mirrors = []string{""}
	}
	var lastErr error
	for _, m := range mirrors {
		u := url
		if m != "" {
			u = strings.TrimRight(m, "/") + "/" + url
		}
		req, _ := http.NewRequest(http.MethodGet, u, nil)
		req.Header.Set("User-Agent", "SubStoreHO/"+CoreVersion)
		res, err := updClient.Do(req)
		if err != nil {
			lastErr = err
			continue
		}
		b, err := io.ReadAll(io.LimitReader(res.Body, max+1))
		res.Body.Close()
		if err != nil {
			lastErr = err
			continue
		}
		if res.StatusCode != 200 {
			lastErr = fmt.Errorf("HTTP %d", res.StatusCode)
			continue
		}
		if int64(len(b)) > max {
			lastErr = errors.New("file too large")
			continue
		}
		return b, m, nil
	}
	return nil, "", lastErr
}

type UpdateInfo struct {
	Manifest        *Manifest `json:"manifest,omitempty"`
	Backend         string    `json:"backend"`         // running / active backend version
	Frontend        string    `json:"frontend"`        // active web UI version
	BuiltinBackend  string    `json:"builtinBackend"`  // versions inside the .so
	BuiltinFrontend string    `json:"builtinFrontend"` //
	BackendUpdated  bool      `json:"backendUpdated"`  // active backend is a downloaded one
	FrontendUpdated bool      `json:"frontendUpdated"` //
	BackendNew      bool      `json:"backendNew"`      // manifest offers a newer backend
	FrontendNew     bool      `json:"frontendNew"`     //
	Compatible      bool      `json:"compatible"`      // this core can run the manifest's backend
	Reason          string    `json:"reason"`          // why not compatible
	Mirror          string    `json:"mirror"`          // mirror prefix that worked
}

func localInfo(dataDir string) UpdateInfo {
	_, bv, bu := activeBackend(dataDir)
	_, fv, fu := activeWeb(dataDir)
	return UpdateInfo{Backend: bv, Frontend: fv, BuiltinBackend: BackendVersion, BuiltinFrontend: FrontendVersion,
		BackendUpdated: bu, FrontendUpdated: fu}
}

func checkCompat(m *Manifest) (bool, string) {
	if m.Schema != 1 {
		return false, "schema"
	}
	if m.HostAPI != HostAPI {
		return false, "hostApi"
	}
	if m.MinCore != "" && verNewer(m.MinCore, CoreVersion) {
		return false, "minCore " + m.MinCore
	}
	return true, ""
}

// UpdateCheck fetches the manifest and compares it with what is installed.
func (s *server) UpdateCheck(dataDir, manifestURL string, mirrors []string) (UpdateInfo, error) {
	info := localInfo(dataDir)
	if manifestURL == "" {
		manifestURL = DefaultManifestURL
	}
	b, m, err := fetch(manifestURL, mirrors, 1<<20)
	if err != nil {
		return info, fmt.Errorf("manifest: %w", err)
	}
	var man Manifest
	if err := json.Unmarshal(b, &man); err != nil {
		return info, fmt.Errorf("manifest: %w", err)
	}
	info.Manifest, info.Mirror = &man, m
	info.Compatible, info.Reason = checkCompat(&man)
	info.BackendNew = man.Backend.URL != "" && verNewer(man.Backend.Version, info.Backend)
	info.FrontendNew = man.Frontend.URL != "" && verNewer(man.Frontend.Version, info.Frontend)
	return info, nil
}

// UpdateInstall downloads and installs the parts of the manifest that are newer (or `force`d), verifying the
// sha256 of each file; a backend is test-started in a scratch data dir before it replaces the active one.
// The caller restarts the service afterwards (stop + start) to load it.
func (s *server) UpdateInstall(dataDir, manifestURL string, mirrors []string, part string, force bool) (UpdateInfo, error) {
	info, err := s.UpdateCheck(dataDir, manifestURL, mirrors)
	if err != nil {
		return info, err
	}
	man := info.Manifest
	if info.Mirror != "" { // a working mirror first
		mirrors = append([]string{info.Mirror}, mirrors...)
	}
	root := updRoot(dataDir)
	if err := os.MkdirAll(root, 0o755); err != nil {
		return info, err
	}
	did := []string{}
	if (part == "" || part == "backend") && (info.BackendNew || force) && man.Backend.URL != "" {
		if !info.Compatible {
			return info, errors.New("incompatible: " + info.Reason)
		}
		s.Event("info", "downloading Sub-Store backend "+man.Backend.Version)
		b, _, err := fetch(man.Backend.URL, mirrors, 32<<20)
		if err != nil {
			return info, fmt.Errorf("backend: %w", err)
		}
		if sha256Hex(b) != strings.ToLower(man.Backend.SHA256) {
			return info, errors.New("backend: sha256 mismatch")
		}
		// test-start in a throwaway data dir: never touches the user's store
		tmp, err := os.MkdirTemp(root, "probe-")
		if err != nil {
			return info, err
		}
		e := NewEngine(tmp, b, func(level, msg string) {}, nil)
		perr := e.Wait()
		e.Stop()
		os.RemoveAll(tmp)
		if perr != nil {
			return info, fmt.Errorf("backend %s does not start: %v", man.Backend.Version, perr)
		}
		if err := installDir(root, "backend", func(dir string) error {
			return os.WriteFile(filepath.Join(dir, "backend.js"), b, 0o644)
		}, installed{Version: man.Backend.Version, SHA256: sha256Hex(b), Time: time.Now().UnixMilli()}); err != nil {
			return info, err
		}
		os.RemoveAll(filepath.Join(root, "backend.bad"))
		s.mu.Lock()
		s.engDir = "" // reload on next start
		s.mu.Unlock()
		did = append(did, "backend "+man.Backend.Version)
	}
	if (part == "" || part == "frontend") && (info.FrontendNew || force) && man.Frontend.URL != "" {
		s.Event("info", "downloading Sub-Store web UI "+man.Frontend.Version)
		b, _, err := fetch(man.Frontend.URL, mirrors, 64<<20)
		if err != nil {
			return info, fmt.Errorf("web UI: %w", err)
		}
		if sha256Hex(b) != strings.ToLower(man.Frontend.SHA256) {
			return info, errors.New("web UI: sha256 mismatch")
		}
		if err := installDir(root, "web", func(dir string) error {
			return unzipDist(b, filepath.Join(dir, "dist"))
		}, installed{Version: man.Frontend.Version, SHA256: sha256Hex(b), Time: time.Now().UnixMilli()}); err != nil {
			return info, fmt.Errorf("web UI: %w", err)
		}
		s.reloadWeb(dataDir)
		did = append(did, "web UI "+man.Frontend.Version)
	}
	if len(did) > 0 {
		s.Event("info", "installed "+strings.Join(did, ", ")+" (restart the service to load a new backend)")
	}
	out := localInfo(dataDir)
	out.Manifest, out.Mirror, out.Compatible, out.Reason = man, info.Mirror, info.Compatible, info.Reason
	out.BackendNew = verNewer(man.Backend.Version, out.Backend)
	out.FrontendNew = verNewer(man.Frontend.Version, out.Frontend)
	return out, nil
}

// installDir fills <root>/<name>.new with fill(), writes version.json and swaps it in for <root>/<name>.
func installDir(root, name string, fill func(dir string) error, v installed) error {
	tmp := filepath.Join(root, name+".new")
	os.RemoveAll(tmp)
	if err := os.MkdirAll(tmp, 0o755); err != nil {
		return err
	}
	if err := fill(tmp); err != nil {
		os.RemoveAll(tmp)
		return err
	}
	vb, _ := json.Marshal(v)
	if err := os.WriteFile(filepath.Join(tmp, "version.json"), vb, 0o644); err != nil {
		os.RemoveAll(tmp)
		return err
	}
	dst := filepath.Join(root, name)
	old := filepath.Join(root, name+".old")
	os.RemoveAll(old)
	os.Rename(dst, old)
	if err := os.Rename(tmp, dst); err != nil {
		os.Rename(old, dst)
		return err
	}
	os.RemoveAll(old)
	return nil
}

// unzipDist extracts web.zip (upstream dist.zip layout: dist/…; a flat zip works too) into dst, applying the
// same clean-up as prepare.sh (no service worker, no .gz duplicates).
func unzipDist(b []byte, dst string) error {
	zr, err := zip.NewReader(bytes.NewReader(b), int64(len(b)))
	if err != nil {
		return err
	}
	prefix := ""
	for _, f := range zr.File {
		if strings.HasPrefix(f.Name, "dist/") {
			prefix = "dist/"
			break
		}
	}
	var total int64
	for _, f := range zr.File {
		name := f.Name
		if prefix != "" {
			if !strings.HasPrefix(name, prefix) {
				continue
			}
			name = strings.TrimPrefix(name, prefix)
		}
		name = path.Clean("/" + name)[1:]
		if name == "" || strings.HasSuffix(f.Name, "/") {
			continue
		}
		base := path.Base(name)
		if strings.HasSuffix(name, ".gz") || base == "sw.js" || base == "registerSW.js" || base == "vercel.json" ||
			strings.HasPrefix(base, "workbox-") {
			continue
		}
		total += int64(f.UncompressedSize64)
		if total > 128<<20 {
			return errors.New("archive too large")
		}
		p := filepath.Join(dst, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			return err
		}
		rc, err := f.Open()
		if err != nil {
			return err
		}
		data, err := io.ReadAll(rc)
		rc.Close()
		if err != nil {
			return err
		}
		if name == "index.html" {
			data = bytes.Replace(data, []byte(`<script id="vite-plugin-pwa:register-sw" src="/registerSW.js"></script>`), nil, 1)
		}
		if err := os.WriteFile(p, data, 0o644); err != nil {
			return err
		}
	}
	if _, err := os.Stat(filepath.Join(dst, "index.html")); err != nil {
		return errors.New("index.html missing")
	}
	return nil
}

// UpdateRollback deletes downloaded parts ("" = both) so the built-in versions are used again.
func (s *server) UpdateRollback(dataDir, part string) UpdateInfo {
	root := updRoot(dataDir)
	if part == "" || part == "backend" {
		os.RemoveAll(filepath.Join(root, "backend"))
		os.RemoveAll(filepath.Join(root, "backend.bad"))
		s.mu.Lock()
		s.engDir = ""
		s.mu.Unlock()
	}
	if part == "" || part == "frontend" {
		os.RemoveAll(filepath.Join(root, "web"))
		s.reloadWeb(dataDir)
	}
	s.Event("info", "restored built-in Sub-Store "+part)
	return localInfo(dataDir)
}

// AppReleasesURL lists the app's own releases (tags v<version>; substore-* tags are component builds).
const AppReleasesURL = "https://api.github.com/repos/zhisibi/substoer-ho/releases?per_page=30"

type AppAsset struct {
	Name string `json:"name"`
	URL  string `json:"url"`
	Size int64  `json:"size"`
}

type AppRelease struct {
	Version   string     `json:"version"`
	Name      string     `json:"name"`
	Notes     string     `json:"notes"`
	URL       string     `json:"url"`
	Published string     `json:"published"`
	Assets    []AppAsset `json:"assets"`
}

// LatestAppRelease returns the newest published v* release of the app ({version:""} when there is none).
func LatestAppRelease(mirrors []string) (AppRelease, error) {
	var out AppRelease
	b, _, err := fetch(AppReleasesURL, mirrors, 4<<20)
	if err != nil {
		return out, err
	}
	var rels []struct {
		Tag        string `json:"tag_name"`
		Name       string `json:"name"`
		Body       string `json:"body"`
		HTML       string `json:"html_url"`
		Draft      bool   `json:"draft"`
		Prerelease bool   `json:"prerelease"`
		Published  string `json:"published_at"`
		Assets     []struct {
			Name string `json:"name"`
			URL  string `json:"browser_download_url"`
			Size int64  `json:"size"`
		} `json:"assets"`
	}
	if err := json.Unmarshal(b, &rels); err != nil {
		return out, err
	}
	for _, r := range rels {
		if r.Draft || r.Prerelease || !strings.HasPrefix(r.Tag, "v") {
			continue
		}
		v := strings.TrimPrefix(r.Tag, "v")
		if out.Version != "" && !verNewer(v, out.Version) {
			continue
		}
		out = AppRelease{Version: v, Name: r.Name, Notes: r.Body, URL: r.HTML, Published: r.Published}
		for _, a := range r.Assets {
			out.Assets = append(out.Assets, AppAsset{Name: a.Name, URL: a.URL, Size: a.Size})
		}
	}
	return out, nil
}
