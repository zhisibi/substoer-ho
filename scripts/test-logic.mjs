// Unit tests for the pure ArkTS logic (common/Lan.ets) under Node's type stripping.
// Usage: node scripts/test-logic.mjs   (Node >= 22.18; copies the .ets file to a temp dir as .ts)
import fs from 'fs';
import os from 'os';
import path from 'path';
import { pathToFileURL } from 'url';

const root = path.join(path.dirname(new URL(import.meta.url).pathname), '..');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'substore-ho-'));
fs.copyFileSync(path.join(root, 'entry/src/main/ets/common/Lan.ets'), path.join(tmp, 'Lan.ts'));
const m = await import(pathToFileURL(path.join(tmp, 'Lan.ts')).href);
let failed = 0, passed = 0;
const eq = (name, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  ok ? passed++ : failed++;
  console.log((ok ? 'ok   ' : 'FAIL ') + name + (ok ? '' : `\n     got  ${JSON.stringify(got)}\n     want ${JSON.stringify(want)}`));
};

// ---- LAN address filter
const C = (ip, iface = '', kind = '') => Object.assign(new m.LanCandidate(), { ip, iface, kind });
eq('isLanIpv4', ['192.168.3.163', '10.1.2.3', '172.16.0.5', '172.31.9.9', '198.18.0.1', '198.19.255.1', '127.0.0.1', '169.254.1.2',
  '100.64.0.1', '172.19.0.1', '172.19.0.9', '8.8.8.8', '172.32.0.1', '1.2.3', 'fe80::1'].map(m.isLanIpv4),
  [true, true, true, true, false, false, false, false, false, false, true, false, false, false, false]);
eq('virtual iface', ['tun0', 'utun3', 'vpn-tun', 'rmnet_data0', 'ccmni1', 'wg0', 'wlan0', 'eth0', 'ap0'].map(m.isVirtualIface),
  [true, true, true, true, true, true, false, false, false]);
eq('pickLanIps: screenshot case (VPN fake-ip dropped)', m.pickLanIps([C('192.168.3.163', 'wlan0', 'wifi'), C('198.18.0.1', 'tun0', 'vpn')]), ['192.168.3.163']);
eq('pickLanIps: 10.x on vpn bearer dropped, also when core sees it on tun', m.pickLanIps([C('10.0.0.2', '', 'vpn'), C('10.0.0.2', 'tun0'),
  C('10.0.0.3', 'tun1'), C('192.168.1.5', 'wlan0')]), ['192.168.1.5']);
eq('pickLanIps: cellular 10.x dropped', m.pickLanIps([C('10.45.3.2', 'rmnet_data0', 'cellular'), C('192.168.43.1', 'ap0')]), ['192.168.43.1']);
eq('pickLanIps: wifi first, dedupe, range order', m.pickLanIps([C('10.8.0.4', 'eth9'), C('172.20.1.2', 'br0'), C('192.168.0.9', 'x0'),
  C('10.8.0.4', 'wlan0', 'wifi'), C('127.0.0.1', 'lo'), C('169.254.3.3', 'wlan0')]), ['10.8.0.4', '172.20.1.2', '192.168.0.9']);
eq('pickLanIps: empty', m.pickLanIps([C('198.18.0.1'), C('127.0.0.1')]), []);

console.log(`\n${passed} passed, ${failed} failed`);
fs.rmSync(tmp, { recursive: true, force: true });
process.exit(failed ? 1 : 0);
