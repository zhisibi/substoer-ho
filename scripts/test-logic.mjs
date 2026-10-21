// Unit tests for the pure ArkTS logic (common/Lan.ets, common/LockLogic.ets) under Node's type stripping.
// Usage: node scripts/test-logic.mjs   (Node >= 22.18; copies the .ets file to a temp dir as .ts)
import fs from 'fs';
import os from 'os';
import path from 'path';
import { pathToFileURL } from 'url';

const root = path.join(path.dirname(new URL(import.meta.url).pathname), '..');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'mimisubstore-'));
fs.copyFileSync(path.join(root, 'entry/src/main/ets/common/Lan.ets'), path.join(tmp, 'Lan.ts'));
fs.copyFileSync(path.join(root, 'entry/src/main/ets/common/LockLogic.ets'), path.join(tmp, 'LockLogic.ts'));
const m = await import(pathToFileURL(path.join(tmp, 'Lan.ts')).href);
const L = await import(pathToFileURL(path.join(tmp, 'LockLogic.ts')).href);
let failed = 0, passed = 0;
const eq = (name, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  ok ? passed++ : failed++;
  console.log((ok ? 'ok   ' : 'FAIL ') + name + (ok ? '' : `\n     got  ${JSON.stringify(got)}\n     want ${JSON.stringify(want)}`));
};

// ---- access lock rules (LockLogic)
eq('pw ok', L.passwordProblem('abcd', 'abcd'), '');
eq('pw short', L.passwordProblem('abc', 'abc'), '密码至少 4 个字符');
eq('pw spaces', L.passwordProblem('    ', '    '), '密码不能只包含空格');
eq('pw mismatch', L.passwordProblem('abcd', 'abce'), '两次输入的密码不一致');
eq('pw long', L.passwordProblem('x'.repeat(65), 'x'.repeat(65)), '密码最多 64 个字符');
eq('answer normalise', [L.normalizeAnswer('  Bei  Jing '), L.normalizeAnswer('ＢＥＩＪＩＮＧ'), L.normalizeAnswer('北京\u3000')], ['bei jing', 'beijing', '北京']);
eq('questions ok', L.questionsProblem(['q1', 'q2'], ['ab', '北京']), '');
eq('questions too few', L.questionsProblem(['q1'], ['ab']), '请设置全部密保问题');
eq('questions duplicate', L.questionsProblem(['q1', 'q1 '], ['ab', 'cd']), '请选择不同的密保问题');
eq('questions short answer', L.questionsProblem(['q1', 'q2'], ['ab', ' c ']), '密保答案至少 2 个字符');
eq('questions empty custom', L.questionsProblem(['q1', ' '], ['ab', 'cd']), '请填写密保问题');
eq('presets distinct', new Set(L.PRESET_QUESTIONS).size === L.PRESET_QUESTIONS.length && L.PRESET_QUESTIONS.length >= L.QUESTION_COUNT, true);
eq('lockout', [0, 4, 5, 6, 7, 20].map(L.lockoutMs), [0, 0, 30000, 60000, 120000, 900000]);
eq('relock', [L.shouldRelock(0, 99999, 30), L.shouldRelock(1000, 30999, 30), L.shouldRelock(1000, 31000, 30)], [false, false, true]);
eq('sameHex', [L.sameHex('ab01', 'ab01'), L.sameHex('ab01', 'ab02'), L.sameHex('ab', 'abc'), L.sameHex('', '')], [true, false, false, false]);
eq('fmtWait', [L.fmtWait(30000), L.fmtWait(61000), L.fmtWait(900000)], ['0:30', '1:01', '15:00']);
eq('lock delays', [L.LOCK_DELAYS.indexOf(L.LOCK_DELAY_DEFAULT) >= 0, L.LOCK_DELAYS.every((x) => x >= 30)], [true, true]);

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
