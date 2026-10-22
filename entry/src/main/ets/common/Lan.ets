/** Lan.ets: picks the LAN IPv4 addresses to offer for subscription links . */
// ------------------------------------------------------------------ LAN addresses

/**
 * One IPv4 address seen on the device: from NetworkKit (kind = bearer: wifi | ethernet | cellular | vpn | bluetooth)
 * or from the core's net.Interfaces (iface = interface name, kind '').
 */
export class LanCandidate {
  ip: string = '';
  iface: string = '';
  kind: string = '';
}

function ipv4Parts(ip: string): number[] | null {
  const ps = ip.trim().split('.');
  if (ps.length !== 4) {
    return null;
  }
  const out: number[] = [];
  for (const p of ps) {
    if (!/^\d{1,3}$/.test(p)) {
      return null;
    }
    const n = Number(p);
    if (n > 255) {
      return null;
    }
    out.push(n);
  }
  return out;
}

/**
 * Private (RFC 1918) IPv4 address a LAN client can reach: 192.168/16, 172.16/12, 10/8. Excludes loopback, link-local
 * 169.254/16, CGNAT 100.64/10, the proxy fake-ip / TUN range 198.18.0.0/15 (mihomo, Clash) and sing-box's default
 * TUN 172.19.0.0/30, multicast and everything public.
 */
export function isLanIpv4(ip: string): boolean {
  const p = ipv4Parts(ip);
  if (p === null) {
    return false;
  }
  if (p[0] === 172 && p[1] === 19 && p[2] === 0 && p[3] < 4) {
    return false;
  }
  return p[0] === 10 || (p[0] === 192 && p[1] === 168) || (p[0] === 172 && p[1] >= 16 && p[1] <= 31);
}

/** Interface names of VPN / TUN / cellular links (never a LAN). */
export function isVirtualIface(name: string): boolean {
  const n = name.toLowerCase();
  return /^(tun|utun|tap|vpn|ppp|wg|ipsec|xfrm|gre|sit|ip6tnl|rmnet|ccmni|seth|sipa|pdp|clat|v4-|dummy|lo)/.test(n) ||
    n.indexOf('tun') >= 0 || n.indexOf('vpn') >= 0;
}

function lanIfaceRank(c: LanCandidate): number {
  if (c.kind === 'wifi' || c.kind === 'ethernet') {
    return 0;
  }
  const n = c.iface.toLowerCase();
  if (/^(wlan|wlp|wifi|eth|en|ap|softap|swlan|p2p|rndis|usb|br|bridge)/.test(n)) {
    return 1;
  }
  return 2;
}

function lanRangeRank(ip: string): number {
  const p = ipv4Parts(ip) ?? [0, 0, 0, 0];
  if (p[0] === 192) {
    return 0;
  }
  return p[0] === 172 ? 1 : 2;
}

/**
 * The LAN addresses to offer for the subscription server: private IPv4 only, no address that any source puts on a
 * VPN / TUN / cellular link, de-duplicated, Wi-Fi / Ethernet first, then 192.168 → 172.16 → 10.
 */
export function pickLanIps(cands: LanCandidate[]): string[] {
  const banned: string[] = [];
  for (const c of cands) {
    if (c.kind === 'vpn' || c.kind === 'cellular' || (c.iface.length > 0 && isVirtualIface(c.iface))) {
      banned.push(c.ip.trim());
    }
  }
  const best: Map<string, number> = new Map<string, number>();
  const order: string[] = [];
  for (const c of cands) {
    const ip = c.ip.trim();
    if (!isLanIpv4(ip) || banned.indexOf(ip) >= 0) {
      continue;
    }
    const r = lanIfaceRank(c);
    const prev = best.get(ip);
    if (prev === undefined) {
      order.push(ip);
      best.set(ip, r);
    } else if (r < prev) {
      best.set(ip, r);
    }
  }
  return order.map((ip: string, i: number): number[] => [best.get(ip) ?? 2, lanRangeRank(ip), i])
    .sort((a: number[], b: number[]): number => a[0] - b[0] || a[1] - b[1] || a[2] - b[2])
    .map((x: number[]): string => order[x[2]]);
}

