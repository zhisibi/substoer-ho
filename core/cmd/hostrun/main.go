// hostrun: run the embedded Sub-Store server on the host for tests.  go run ./cmd/hostrun <dataDir> <port> [host]
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"time"

	"mimisubstore/core/ssc"
)

func main() {
	// hostrun upd <dataDir> <manifestURL> [part]  — install an update like the app does, print UpdateInfo
	if len(os.Args) > 3 && os.Args[1] == "upd" {
		part := ""
		if len(os.Args) > 4 {
			part = os.Args[4]
		}
		info, err := ssc.S.UpdateInstall(os.Args[2], os.Args[3], nil, part, false)
		b, _ := json.Marshal(info)
		fmt.Println(string(b))
		if err != nil {
			fmt.Println("error:", err)
			os.Exit(1)
		}
		return
	}
	port, _ := strconv.Atoi(os.Args[2])
	host := "127.0.0.1"
	if len(os.Args) > 3 {
		host = os.Args[3]
	}
	if err := ssc.S.Start(host, port, os.Args[1]); err != nil {
		fmt.Println("start:", err)
		os.Exit(1)
	}
	var seq int64
	for {
		lines, s := ssc.S.Logs(seq)
		seq = s
		for _, l := range lines {
			if l.Kind == "event" {
				fmt.Printf("[%s] %s\n", l.Level, l.Msg)
			} else {
				fmt.Printf("%s %s %s %d %dB %dms\n", l.IP, l.Method, l.Path, l.Status, l.Bytes, l.Ms)
			}
		}
		time.Sleep(300 * time.Millisecond)
	}
}
