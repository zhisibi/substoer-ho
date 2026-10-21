#!/bin/bash
# Smoke test of core/ssc/assets (backend.js + web) with cmd/hostrun: serves the web UI, creates a local
# subscription and a remote Clash YAML one, downloads several targets. Used by CI before publishing an update
# and handy after prepare.sh.  Needs go (+ python3 for the tiny file server).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
cd $HERE/..
T=$(mktemp -d)
PORT=${PORT:-3399}; FPORT=${FPORT:-3398}
go build -o $T/hostrun ./cmd/hostrun
mkdir -p $T/files
cat > $T/files/clash.yaml <<'YAML'
port: 7890
proxies:
  - {name: HK 01, type: ss, server: hk.example.com, port: 10000, cipher: aes-256-gcm, password: pw, udp: true}
  - {name: SG 01, type: vmess, server: sg.example.com, port: 443, uuid: 218390ed-55be-425b-a521-becb8b63f0d6, alterId: 0, cipher: auto, tls: true, network: ws, ws-opts: {path: /, headers: {Host: sg.example.com}}}
  - {name: JP 01, type: trojan, server: jp.example.com, port: 443, password: pw, sni: jp.example.com}
rules:
  - DOMAIN-SUFFIX,example.com,DIRECT
  - MATCH,DIRECT
YAML
(cd $T/files && exec python3 -m http.server $FPORT --bind 127.0.0.1 >/dev/null 2>&1) &
FS=$!
$T/hostrun $T/data $PORT > $T/log.txt 2>&1 &
HR=$!
trap "kill $FS $HR 2>/dev/null; cat $T/log.txt | tail -40; rm -rf $T" EXIT
B=http://127.0.0.1:$PORT
for i in $(seq 1 50); do curl -sf $B/ -o /dev/null && break; sleep 0.2; done
fail() { echo "SMOKE FAIL: $*"; exit 1; }
curl -sf $B/ | grep -qi '<html' || fail "web UI"
curl -sf -XPOST $B/api/subs -H 'Content-Type: application/json' \
  -d '{"name":"local","source":"local","content":"vless://218390ed-55be-425b-a521-becb8b63f0d6@1.2.3.4:443?security=tls&type=ws&host=a.example&sni=a.example&path=%2F&encryption=none#SG\ntrojan://pw@5.6.7.8:443?sni=b.example#JP"}' -o /dev/null || fail "create local sub"
curl -sf -XPOST $B/api/subs -H 'Content-Type: application/json' \
  -d "{\"name\":\"remote\",\"source\":\"remote\",\"url\":\"http://127.0.0.1:$FPORT/clash.yaml\"}" -o /dev/null || fail "create remote sub"
for sub in local remote; do
  for t in ClashMeta sing-box Surge QX Loon V2Ray; do
    out=$(curl -s -m 60 -w '\n%{http_code}' "$B/download/$sub?target=$t")
    code=${out##*$'\n'}; body=${out%$'\n'*}
    [ "$code" = 200 ] || fail "$sub $t HTTP $code"
    [ -n "$body" ] || [ "$t" = Surge ] || [ "$t" = QX ] || fail "$sub $t empty"
    echo "ok $sub $t ${#body}B"
  done
done
curl -s "$B/download/remote?target=ClashMeta" | grep -q "HK 01" || fail "remote nodes missing"
curl -s "$B/download/local?target=sing-box" | grep -q '"vless"' || fail "local vless missing"
echo "SMOKE OK"
