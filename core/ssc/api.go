package ssc

import (
	"encoding/json"
	"os"
	"path/filepath"
)

const (
	CoreVersion     = "1.4.1"
	BackendVersion  = "2.42.6" // sub-store-org/Sub-Store backend (bundled, patched express adapter)
	FrontendVersion = "2.34.1" // sub-store-org/Sub-Store-Front-End dist
)

func VersionJSON() string {
	b, _ := json.Marshal(map[string]any{"core": CoreVersion, "backend": BackendVersion, "frontend": FrontendVersion, "hostApi": HostAPI})
	return string(b)
}

type req struct {
	Op    string `json:"op"`
	Host  string `json:"host"`
	Port  int    `json:"port"`
	Dir   string `json:"dir"`
	After int64  `json:"after"`
	Level string `json:"level"`
	Text  string `json:"text"`
	On    bool   `json:"on"`
	Key   string `json:"key"`
	Value string `json:"value"`
	// update ops
	URL     string   `json:"url"`
	Mirrors []string `json:"mirrors"`
	Part    string   `json:"part"`
	Force   bool     `json:"force"`
}

func jsonOut(v any) string {
	b, err := json.Marshal(v)
	if err != nil {
		return `{"error":"marshal"}`
	}
	return string(b)
}

func errOut(err error) string { return jsonOut(map[string]string{"error": err.Error()}) }

// Call is the single JSON entry point of the NAPI layer:
//
//	{op:"start",host,port,dir} → {ok} | {error}   (loads the Sub-Store backend on first start; dir = data dir)
//	{op:"stop"}                → {ok}
//	{op:"lanUI",on}            → {ok}             (serve web UI + API to other devices too)
//	{op:"status"}              → Status
//	{op:"logs",after}          → {seq, lines}     {op:"clearLogs"} → {ok}
//	{op:"event",level,text}    → {ok}
//	{op:"reset",dir}           → {ok}             (stop server + backend, delete the Sub-Store store)
//	{op:"ifaddrs"}             → {addrs:[{name, ip}]}
//	{op:"updInfo",dir}                              → UpdateInfo (local only)
//	{op:"updCheck",dir,url?,mirrors}                → UpdateInfo | {error}   (callAsync: network)
//	{op:"updInstall",dir,url?,mirrors,part?,force?} → UpdateInfo | {error}   (then stop + start the service)
//	{op:"updRollback",dir,part?}                    → UpdateInfo
//	{op:"appRelease",mirrors}                       → AppRelease (newest v* release of the app on GitHub)
func Call(js string) string {
	var r req
	if err := json.Unmarshal([]byte(js), &r); err != nil {
		return errOut(err)
	}
	switch r.Op {
	case "start":
		if err := S.Start(r.Host, r.Port, r.Dir); err != nil {
			return errOut(err)
		}
		return `{"ok":true}`
	case "stop":
		S.Stop()
		return `{"ok":true}`
	case "lanUI":
		S.SetLanUI(r.On)
		return `{"ok":true}`
	case "status":
		return jsonOut(S.Status())
	case "logs":
		lines, seq := S.Logs(r.After)
		return jsonOut(map[string]any{"seq": seq, "lines": lines})
	case "clearLogs":
		S.ClearLogs()
		return `{"ok":true}`
	case "event":
		S.Event(r.Level, r.Text)
		return `{"ok":true}`
	case "ifaddrs":
		return jsonOut(map[string]any{"addrs": LocalIPv4Addrs()})
	case "reset":
		S.Reset(r.Dir)
		return `{"ok":true}`
	case "updInfo":
		return jsonOut(localInfo(r.Dir))
	case "updCheck":
		info, err := S.UpdateCheck(r.Dir, r.URL, r.Mirrors)
		if err != nil {
			return errOut(err)
		}
		return jsonOut(info)
	case "updInstall":
		info, err := S.UpdateInstall(r.Dir, r.URL, r.Mirrors, r.Part, r.Force)
		if err != nil {
			S.Event("error", "update failed: "+err.Error())
			return errOut(err)
		}
		return jsonOut(info)
	case "appRelease":
		rel, err := LatestAppRelease(r.Mirrors)
		if err != nil {
			return errOut(err)
		}
		return jsonOut(rel)
	case "updRollback":
		return jsonOut(S.UpdateRollback(r.Dir, r.Part))
	case "storeSize":
		var n int64
		filepath.Walk(filepath.Join(r.Dir, "store"), func(_ string, info os.FileInfo, err error) error {
			if err == nil && !info.IsDir() {
				n += info.Size()
			}
			return nil
		})
		return jsonOut(map[string]int64{"bytes": n})
	}
	return errOut(errUnknown(r.Op))
}

type errUnknown string

func (e errUnknown) Error() string { return "unknown op " + string(e) }
