/**
 * Invite.ets — 特别版邀请码 (special-edition activation).
 *
 * Flow: the gate shows a per-install 申请码 derived from the install id; the user sends it to the
 * developer (QQ), who returns the matching 邀请码 computed with the shared secret (HMAC-SHA256).
 * Verification is fully offline. A master code (derived from the literal request code "MASTER")
 * works on any install, for the developer's own use.
 *
 * SHA-256 / HMAC below are a compact pure-TS implementation so verification needs no async
 * crypto calls; correctness is covered by scripts/test-logic vectors against Node's crypto.
 */

/** Secret shared with the developer's code generator. Split so it does not sit in one literal. */
const SECRET_PARTS: string[] = ['9d7b4b59', 'c275ef75', '75b31d9d', '3335f38c'];

function secret(): string {
  return SECRET_PARTS.join('');
}

const ALPHABET: string = 'ABCDEFGHJKMNPQRSTUVWXYZ123456789';

function utf8(s: string): number[] {
  const out: number[] = [];
  for (let i = 0; i < s.length; i++) {
    let cp = s.charCodeAt(i);
    if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < s.length) {
      const lo = s.charCodeAt(i + 1);
      if (lo >= 0xDC00 && lo <= 0xDFFF) {
        cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
        i++;
      }
    }
    if (cp < 0x80) {
      out.push(cp);
    } else if (cp < 0x800) {
      out.push(0xC0 | (cp >> 6), 0x80 | (cp & 0x3F));
    } else if (cp < 0x10000) {
      out.push(0xE0 | (cp >> 12), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F));
    } else {
      out.push(0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3F), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F));
    }
  }
  return out;
}

const K: number[] = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
];

function rotr(x: number, n: number): number {
  return ((x >>> n) | (x << (32 - n))) >>> 0;
}

/** SHA-256 of a byte array, returned as 32 bytes. */
export function sha256(msg: number[]): number[] {
  const h: number[] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
  const bitLen = msg.length * 8;
  const data = msg.slice();
  data.push(0x80);
  while (data.length % 64 !== 56) {
    data.push(0);
  }
  // 64-bit length; messages here are short, high word is 0
  data.push(0, 0, 0, 0);
  data.push((bitLen >>> 24) & 0xFF, (bitLen >>> 16) & 0xFF, (bitLen >>> 8) & 0xFF, bitLen & 0xFF);
  const w: number[] = new Array(64).fill(0);
  for (let blk = 0; blk < data.length; blk += 64) {
    for (let i = 0; i < 16; i++) {
      w[i] = ((data[blk + i * 4] << 24) | (data[blk + i * 4 + 1] << 16) |
        (data[blk + i * 4 + 2] << 8) | data[blk + i * 4 + 3]) >>> 0;
    }
    for (let i = 16; i < 64; i++) {
      const s0 = (rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3)) >>> 0;
      const s1 = (rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10)) >>> 0;
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0;
    }
    let a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
    for (let i = 0; i < 64; i++) {
      const s1 = (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) >>> 0;
      const ch = ((e & f) ^ (~e & g)) >>> 0;
      const t1 = (hh + s1 + ch + K[i] + w[i]) >>> 0;
      const s0 = (rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) >>> 0;
      const maj = ((a & b) ^ (a & c) ^ (b & c)) >>> 0;
      const t2 = (s0 + maj) >>> 0;
      hh = g; g = f; f = e; e = (d + t1) >>> 0;
      d = c; c = b; b = a; a = (t1 + t2) >>> 0;
    }
    h[0] = (h[0] + a) >>> 0; h[1] = (h[1] + b) >>> 0; h[2] = (h[2] + c) >>> 0; h[3] = (h[3] + d) >>> 0;
    h[4] = (h[4] + e) >>> 0; h[5] = (h[5] + f) >>> 0; h[6] = (h[6] + g) >>> 0; h[7] = (h[7] + hh) >>> 0;
  }
  const out: number[] = [];
  for (const v of h) {
    out.push((v >>> 24) & 0xFF, (v >>> 16) & 0xFF, (v >>> 8) & 0xFF, v & 0xFF);
  }
  return out;
}

function hmacSha256(key: string, msg: string): number[] {
  let k = utf8(key);
  if (k.length > 64) {
    k = sha256(k);
  }
  while (k.length < 64) {
    k.push(0);
  }
  const ipad = k.map((b: number) => b ^ 0x36);
  const opad = k.map((b: number) => b ^ 0x5C);
  return sha256(opad.concat(sha256(ipad.concat(utf8(msg)))));
}

/** 8 code characters from the first 8 digest bytes, formatted XXXX-XXXX. */
function codeFromDigest(digest: number[]): string {
  let s = '';
  for (let i = 0; i < 8; i++) {
    s += ALPHABET.charAt(digest[i] & 31);
    if (i === 3) {
      s += '-';
    }
  }
  return s;
}

function normalize(code: string): string {
  return code.toUpperCase().replace(/[^A-Z0-9]/g, '');
}

function formatCode(raw8: string): string {
  return raw8.substring(0, 4) + '-' + raw8.substring(4, 8);
}

/** The 申请码 shown on the gate for this install. */
export function requestCode(installId: string): string {
  return codeFromDigest(hmacSha256(secret(), 'req:' + installId));
}

/** The 邀请码 matching a 申请码 (what the developer's generator produces). */
export function inviteCodeFor(req: string): string {
  const r = formatCode(normalize(req));
  return codeFromDigest(hmacSha256(secret(), 'inv:' + r));
}

/** Checks a user-entered invite code against this install (or the master code). */
export function verifyInvite(input: string, installId: string): boolean {
  const c = normalize(input);
  if (c.length !== 8) {
    return false;
  }
  const formatted = formatCode(c);
  return formatted === inviteCodeFor(requestCode(installId)) || formatted === inviteCodeFor('MASTER');
}
