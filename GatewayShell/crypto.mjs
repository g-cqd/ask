// GatewayShell/crypto.mjs — End-to-end cryptography and wire codecs for the ask web shell (ADR-0170).
// Zero external dependencies: WebCrypto (X25519, Ed25519, SHA-256, HMAC-SHA256) + RFC 8439 ChaCha20-Poly1305 + RFC 9106 Argon2id.

const X25519_PKCS8_PREFIX = new Uint8Array([
  0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06,
  0x03, 0x2b, 0x65, 0x6e, 0x04, 0x22, 0x04, 0x20,
]);

const BASEPOINT_9 = (() => {
  const b = new Uint8Array(32);
  b[0] = 9;
  return b;
})();

const DOMAIN_SHELL = new TextEncoder().encode("ask-gateway-shell/1\n");
const PROLOGUE_LIST = new TextEncoder().encode("ask-gateway/1 list");
const PROLOGUE_CHANNEL = new TextEncoder().encode("ask-gateway/1 channel");

export function concatBytes(...arrays) {
  let total = 0;
  for (const a of arrays) total += a.length;
  const out = new Uint8Array(total);
  let offset = 0;
  for (const a of arrays) {
    out.set(a, offset);
    offset += a.length;
  }
  return out;
}

export function bytesToHex(bytes) {
  let s = "";
  for (let i = 0; i < bytes.length; i++) s += bytes[i].toString(16).padStart(2, "0");
  return s;
}

export function hexToBytes(hex) {
  const clean = hex.replace(/\s+/g, "");
  if (clean.length % 2 !== 0) throw new Error("invalid hex length");
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < out.length; i++) {
    const v = Number.parseInt(clean.slice(i * 2, i * 2 + 2), 16);
    if (Number.isNaN(v)) throw new Error("invalid hex byte");
    out[i] = v;
  }
  return out;
}

export function bytesToBase64(bytes) {
  if (typeof Buffer !== "undefined") return Buffer.from(bytes).toString("base64");
  let bin = "";
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin);
}

export function base64ToBytes(text) {
  let norm = text.trim().replace(/-/g, "+").replace(/_/g, "/");
  while (norm.length % 4 !== 0) norm += "=";
  if (typeof Buffer !== "undefined") return new Uint8Array(Buffer.from(norm, "base64"));
  const bin = atob(norm);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export async function sha256(bytes) {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
}

export async function hmacSha256(keyBytes, dataBytes) {
  const key = await crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return new Uint8Array(await crypto.subtle.sign("HMAC", key, dataBytes));
}

export async function hkdf2(chainingKey, inputKeyMaterial) {
  const tempKey = await hmacSha256(chainingKey, inputKeyMaterial);
  const out1 = await hmacSha256(tempKey, new Uint8Array([0x01]));
  const out2 = await hmacSha256(tempKey, concatBytes(out1, new Uint8Array([0x02])));
  return [out1, out2];
}

export async function keyFingerprint(publicKeyBytes) {
  const digest = await sha256(publicKeyBytes);
  const hex = bytesToHex(digest.slice(0, 16));
  const groups = [];
  for (let i = 0; i < 32; i += 4) groups.push(hex.slice(i, i + 4));
  return groups.join(" ");
}

// --- RFC 8439 ChaCha20-Poly1305 ---

function rotl32(v, c) {
  return ((v << c) | (v >>> (32 - c))) >>> 0;
}

function quarterRound(x, a, b, c, d) {
  x[a] = (x[a] + x[b]) >>> 0; x[d] = rotl32(x[d] ^ x[a], 16);
  x[c] = (x[c] + x[d]) >>> 0; x[b] = rotl32(x[b] ^ x[c], 12);
  x[a] = (x[a] + x[b]) >>> 0; x[d] = rotl32(x[d] ^ x[a], 8);
  x[c] = (x[c] + x[d]) >>> 0; x[b] = rotl32(x[b] ^ x[c], 7);
}

function chacha20Block(key32, counter, nonce12) {
  const state = new Uint32Array(16);
  state[0] = 0x61707865;
  state[1] = 0x3320646e;
  state[2] = 0x79622d32;
  state[3] = 0x6b206574;
  const kv = new DataView(key32.buffer, key32.byteOffset, 32);
  for (let i = 0; i < 8; i++) state[4 + i] = kv.getUint32(i * 4, true);
  state[12] = counter >>> 0;
  const nv = new DataView(nonce12.buffer, nonce12.byteOffset, 12);
  state[13] = nv.getUint32(0, true);
  state[14] = nv.getUint32(4, true);
  state[15] = nv.getUint32(8, true);

  const working = new Uint32Array(state);
  for (let i = 0; i < 10; i++) {
    quarterRound(working, 0, 4, 8, 12);
    quarterRound(working, 1, 5, 9, 13);
    quarterRound(working, 2, 6, 10, 14);
    quarterRound(working, 3, 7, 11, 15);
    quarterRound(working, 0, 5, 10, 15);
    quarterRound(working, 1, 6, 11, 12);
    quarterRound(working, 2, 7, 8, 13);
    quarterRound(working, 3, 4, 9, 14);
  }
  const out = new Uint8Array(64);
  const ov = new DataView(out.buffer);
  for (let i = 0; i < 16; i++) ov.setUint32(i * 4, (working[i] + state[i]) >>> 0, true);
  return out;
}

function chacha20Xor(key32, counter, nonce12, input) {
  const out = new Uint8Array(input.length);
  for (let pos = 0, blockIndex = 0; pos < input.length; pos += 64, blockIndex++) {
    const stream = chacha20Block(key32, (counter + blockIndex) >>> 0, nonce12);
    const take = Math.min(64, input.length - pos);
    for (let i = 0; i < take; i++) out[pos + i] = input[pos + i] ^ stream[i];
  }
  return out;
}

const POLY_P = (1n << 130n) - 5n;

function leBytesToBigInt(bytes) {
  let v = 0n;
  for (let i = bytes.length - 1; i >= 0; i--) v = (v << 8n) | BigInt(bytes[i]);
  return v;
}

function poly1305Mac(otk32, message) {
  const rBytes = new Uint8Array(otk32.slice(0, 16));
  rBytes[3] &= 15; rBytes[7] &= 15; rBytes[11] &= 15; rBytes[15] &= 15;
  rBytes[4] &= 252; rBytes[8] &= 252; rBytes[12] &= 252;
  const r = leBytesToBigInt(rBytes);
  const s = leBytesToBigInt(otk32.slice(16, 32));
  let acc = 0n;
  for (let i = 0; i < message.length; i += 16) {
    const slice = message.slice(i, Math.min(i + 16, message.length));
    const n = leBytesToBigInt(slice) + (1n << BigInt(slice.length * 8));
    acc = ((acc + n) * r) % POLY_P;
  }
  acc = (acc + s) & ((1n << 128n) - 1n);
  const tag = new Uint8Array(16);
  for (let i = 0; i < 16; i++) {
    tag[i] = Number(acc & 0xffn);
    acc >>= 8n;
  }
  return tag;
}

function pad16(len) {
  const rem = len % 16;
  return rem === 0 ? new Uint8Array(0) : new Uint8Array(16 - rem);
}

function u64le(n) {
  const out = new Uint8Array(8);
  let v = BigInt(n);
  for (let i = 0; i < 8; i++) {
    out[i] = Number(v & 0xffn);
    v >>= 8n;
  }
  return out;
}

function aeadPolyInput(ad, ciphertext) {
  return concatBytes(ad, pad16(ad.length), ciphertext, pad16(ciphertext.length), u64le(ad.length), u64le(ciphertext.length));
}

export function chacha20Poly1305Seal(key32, nonce12, plaintext, ad) {
  const otk = chacha20Block(key32, 0, nonce12).slice(0, 32);
  const ciphertext = chacha20Xor(key32, 1, nonce12, plaintext);
  const tag = poly1305Mac(otk, aeadPolyInput(ad, ciphertext));
  return concatBytes(ciphertext, tag);
}

export function chacha20Poly1305Open(key32, nonce12, sealed, ad) {
  if (sealed.length < 16) throw new Error("authenticationFailed");
  const ciphertext = sealed.slice(0, sealed.length - 16);
  const tag = sealed.slice(sealed.length - 16);
  const otk = chacha20Block(key32, 0, nonce12).slice(0, 32);
  const expected = poly1305Mac(otk, aeadPolyInput(ad, ciphertext));
  let diff = 0;
  for (let i = 0; i < 16; i++) diff |= tag[i] ^ expected[i];
  if (diff !== 0) throw new Error("authenticationFailed");
  return chacha20Xor(key32, 1, nonce12, ciphertext);
}

function noiseNonce12(n) {
  const out = new Uint8Array(12);
  let v = BigInt(n);
  for (let i = 0; i < 8; i++) {
    out[4 + i] = Number(v & 0xffn);
    v >>= 8n;
  }
  return out;
}

// --- WebCrypto X25519 Non-Extractable Keys ---

export async function importX25519PrivateSeed(seed32) {
  if (seed32.length !== 32) throw new Error("seed must be 32 bytes");
  const pkcs8 = new Uint8Array(48);
  pkcs8.set(X25519_PKCS8_PREFIX, 0);
  pkcs8.set(seed32, 16);
  try {
    const privateKey = await crypto.subtle.importKey("pkcs8", pkcs8, { name: "X25519" }, false, ["deriveBits"]);
    const basePub = await crypto.subtle.importKey("raw", BASEPOINT_9, { name: "X25519" }, false, []);
    const publicBytes = new Uint8Array(await crypto.subtle.deriveBits({ name: "X25519", public: basePub }, privateKey, 256));
    return { privateKey, publicBytes };
  } finally {
    pkcs8.fill(0);
  }
}

export async function generateX25519Pair() {
  const kp = await crypto.subtle.generateKey({ name: "X25519" }, false, ["deriveBits"]);
  const publicBytes = new Uint8Array(await crypto.subtle.exportKey("raw", kp.publicKey));
  return { privateKey: kp.privateKey, publicBytes };
}

async function x25519DH(privateCryptoKey, peerPublicBytes32) {
  const pub = await crypto.subtle.importKey("raw", peerPublicBytes32, { name: "X25519" }, false, []);
  const shared = new Uint8Array(await crypto.subtle.deriveBits({ name: "X25519", public: pub }, privateCryptoKey, 256));
  let nonZero = 0;
  for (let i = 0; i < 32; i++) nonZero |= shared[i];
  if (nonZero === 0) throw new Error("low-order X25519 point refused");
  return shared;
}

// --- Noise CipherState & SymmetricState ---

class CipherState {
  constructor(key = null) {
    this.key = key;
    this.nonce = 0n;
  }
  get hasKey() { return this.key !== null; }
  encrypt(plaintext, ad) {
    if (!this.key) return plaintext;
    if (this.nonce >= 0xffffffffffffffffn) throw new Error("nonceExhausted");
    const out = chacha20Poly1305Seal(this.key, noiseNonce12(this.nonce), plaintext, ad);
    this.nonce += 1n;
    return out;
  }
  decrypt(ciphertext, ad) {
    if (!this.key) return ciphertext;
    if (this.nonce >= 0xffffffffffffffffn) throw new Error("nonceExhausted");
    const out = chacha20Poly1305Open(this.key, noiseNonce12(this.nonce), ciphertext, ad);
    this.nonce += 1n;
    return out;
  }
}

class SymmetricState {
  static async create(protocolName) {
    const name = new TextEncoder().encode(protocolName);
    let h;
    if (name.length <= 32) {
      h = new Uint8Array(32);
      h.set(name, 0);
    } else {
      h = await sha256(name);
    }
    return new SymmetricState(h, new Uint8Array(h));
  }
  constructor(ck, h) {
    this.ck = ck;
    this.h = h;
    this.cipher = new CipherState();
  }
  async mixHash(data) {
    this.h = await sha256(concatBytes(this.h, data));
  }
  async mixKey(ikm) {
    const [ck, k] = await hkdf2(this.ck, ikm);
    this.ck = ck;
    this.cipher = new CipherState(k);
  }
  async encryptAndHash(plaintext) {
    const ct = this.cipher.encrypt(plaintext, this.h);
    await this.mixHash(ct);
    return ct;
  }
  async decryptAndHash(ciphertext) {
    const pt = this.cipher.decrypt(ciphertext, this.h);
    await this.mixHash(ciphertext);
    return pt;
  }
  async split() {
    const [k1, k2] = await hkdf2(this.ck, new Uint8Array(0));
    return [new CipherState(k1), new CipherState(k2)];
  }
}

// --- SealedList (Noise_N_25519_ChaChaPoly_SHA256) ---

export async function openSealedList(sealedBytes, controllerIdentity) {
  const myFp = (await sha256(controllerIdentity.publicBytes)).slice(0, 8);
  let offset = 0;
  while (offset < sealedBytes.length) {
    if (sealedBytes.length - offset < 12) throw new Error("malformed sealed list");
    const fp = sealedBytes.slice(offset, offset + 8);
    const dv = new DataView(sealedBytes.buffer, sealedBytes.byteOffset + offset + 8, 4);
    const len = dv.getUint32(0, false);
    offset += 12;
    if (len < 48 || sealedBytes.length - offset < len) throw new Error("malformed sealed list entry");
    const msg = sealedBytes.slice(offset, offset + len);
    offset += len;
    let match = true;
    for (let i = 0; i < 8; i++) if (fp[i] !== myFp[i]) match = false;
    if (!match) continue;

    const sym = await SymmetricState.create("Noise_N_25519_ChaChaPoly_SHA256");
    await sym.mixHash(PROLOGUE_LIST);
    await sym.mixHash(controllerIdentity.publicBytes);
    const re = msg.slice(0, 32);
    await sym.mixHash(re);
    await sym.mixKey(await x25519DH(controllerIdentity.privateKey, re));
    return await sym.decryptAndHash(msg.slice(32));
  }
  throw new Error("notOpened");
}

// --- ControllerChannel (Noise_IK_25519_ChaChaPoly_SHA256) ---

export class ControllerChannel {
  static async open(controllerIdentity, nodePublicBytes32, fixedEphemeral = null) {
    const sym = await SymmetricState.create("Noise_IK_25519_ChaChaPoly_SHA256");
    await sym.mixHash(PROLOGUE_CHANNEL);
    await sym.mixHash(nodePublicBytes32);
    const eph = fixedEphemeral ?? (await generateX25519Pair());
    await sym.mixHash(eph.publicBytes);
    await sym.mixKey(await x25519DH(eph.privateKey, nodePublicBytes32)); // es
    const encS = await sym.encryptAndHash(controllerIdentity.publicBytes); // s
    await sym.mixKey(await x25519DH(controllerIdentity.privateKey, nodePublicBytes32)); // ss
    const encPayload = await sym.encryptAndHash(new Uint8Array(0));
    const first = concatBytes(eph.publicBytes, encS, encPayload);
    const ch = new ControllerChannel(sym, controllerIdentity, eph);
    return { channel: ch, first };
  }
  constructor(sym, controllerIdentity, eph) {
    this.sym = sym;
    this.controllerIdentity = controllerIdentity;
    this.eph = eph;
    this.sending = null;
    this.receiving = null;
  }
  async finish(answerBytes) {
    if (answerBytes.length < 48) throw new Error("malformed IK answer");
    const re = answerBytes.slice(0, 32);
    await this.sym.mixHash(re);
    await this.sym.mixKey(await x25519DH(this.eph.privateKey, re)); // ee
    await this.sym.mixKey(await x25519DH(this.controllerIdentity.privateKey, re)); // se
    await this.sym.decryptAndHash(answerBytes.slice(32));
    const [c1, c2] = await this.sym.split();
    this.sending = c1;
    this.receiving = c2;
    this.sym = null;
    this.eph = null;
  }
  send(channelMessageBytes) {
    if (!this.sending) throw new Error("channel not open");
    return this.sending.encrypt(channelMessageBytes, new Uint8Array(0));
  }
  receive(dataBytes) {
    if (!this.receiving) throw new Error("channel not open");
    return parseChannelMessage(this.receiving.decrypt(dataBytes, new Uint8Array(0)));
  }
}

// --- RelayFrame & ChannelMessage codecs ---

export const RelayKind = {
  HELLO: 0x01,
  LIST: 0x02,
  LISTS: 0x03,
  OPEN: 0x10,
  DATA: 0x11,
  CLOSE: 0x12,
  PING: 0x20,
  PONG: 0x21,
};

export function encodeRelayFrame(kind, channel, body = new Uint8Array(0)) {
  const out = new Uint8Array(5 + body.length);
  out[0] = kind;
  new DataView(out.buffer).setUint32(1, channel >>> 0, false);
  out.set(body, 5);
  return out;
}

export function parseRelayFrame(bytes) {
  if (bytes.length < 5) throw new Error("relay frame too short");
  const kind = bytes[0];
  const channel = new DataView(bytes.buffer, bytes.byteOffset + 1, 4).getUint32(0, false);
  const body = bytes.slice(5);
  return { kind, channel, body };
}

export function parseListsBody(body) {
  const entries = [];
  let offset = 0;
  while (offset < body.length) {
    if (body.length - offset < 36) throw new Error("malformed lists frame");
    const nodeKey = body.slice(offset, offset + 32);
    const len = new DataView(body.buffer, body.byteOffset + offset + 32, 4).getUint32(0, false);
    offset += 36;
    if (body.length - offset < len) throw new Error("truncated lists entry");
    const sealedList = body.slice(offset, offset + len);
    offset += len;
    entries.push({ nodeKey, sealedList });
  }
  return entries;
}

export function encodeAttach(columns, rows, session) {
  const s = new TextEncoder().encode(session);
  const out = new Uint8Array(5 + s.length);
  out[0] = 0x01;
  const dv = new DataView(out.buffer);
  dv.setUint16(1, columns, false);
  dv.setUint16(3, rows, false);
  out.set(s, 5);
  return out;
}

export function encodeStart(columns, rows, folder) {
  const s = new TextEncoder().encode(folder);
  const out = new Uint8Array(5 + s.length);
  out[0] = 0x02;
  const dv = new DataView(out.buffer);
  dv.setUint16(1, columns, false);
  dv.setUint16(3, rows, false);
  out.set(s, 5);
  return out;
}

export function encodeInput(bytes) {
  return concatBytes(new Uint8Array([0x03]), bytes);
}

export function encodeResize(columns, rows) {
  const out = new Uint8Array(5);
  out[0] = 0x04;
  const dv = new DataView(out.buffer);
  dv.setUint16(1, columns, false);
  dv.setUint16(3, rows, false);
  return out;
}

export function parseChannelMessage(bytes) {
  if (bytes.length === 0) throw new Error("empty channel message");
  const kind = bytes[0];
  const body = bytes.slice(1);
  if (kind === 0x10) return { type: "output", bytes: body };
  if (kind === 0x11) return { type: "ended", reason: new TextDecoder().decode(body) };
  if (kind === 0x12) return { type: "refused", reason: new TextDecoder().decode(body) };
  return { type: "other", kind, bytes: body };
}

// --- Ed25519 Shell Manifest Verification ---

export async function verifyShellManifest(manifestJsonBytes, signatureBytes, pinnedPublicKeyBase64 = null) {
  const manifest = JSON.parse(new TextDecoder().decode(manifestJsonBytes));
  if (manifest.version !== 1 || typeof manifest.publicKey !== "string" || typeof manifest.files !== "object") {
    throw new Error("invalid manifest format");
  }
  const keyBytes = base64ToBytes(manifest.publicKey);
  if (pinnedPublicKeyBase64 !== null) {
    const pinnedBytes = base64ToBytes(pinnedPublicKeyBase64);
    if (bytesToHex(pinnedBytes) !== bytesToHex(keyBytes)) {
      throw new Error("manifest public key does not match pinned release key");
    }
  }
  const edKey = await crypto.subtle.importKey("raw", keyBytes, { name: "Ed25519" }, false, ["verify"]);
  const ok = await crypto.subtle.verify("Ed25519", edKey, signatureBytes, concatBytes(DOMAIN_SHELL, manifestJsonBytes));
  if (!ok) throw new Error("invalid Ed25519 manifest signature");
  return { manifest, fingerprint: await keyFingerprint(keyBytes) };
}

// --- RFC 9106 Argon2id (1 lane, 32-bit word halves for fast JIT execution) ---

const BLAKE2B_IV = new Uint32Array([
  0xf3bcc908, 0x6a09e667, 0x84caa73b, 0xbb67ae85,
  0xfe94f82b, 0x3c6ef372, 0x5f1d36f1, 0xa54ff53a,
  0xade682d1, 0x510e527f, 0x2b3e6c1f, 0x9b05688c,
  0xfb41bd6b, 0x1f83d9ab, 0x137e2179, 0x5be0cd19,
]);

const BLAKE2B_SIGMA = [
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
  [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
  [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
  [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
  [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
  [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
  [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
  [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
  [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
  [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0],
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
  [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
];

function add64(v, a, b) {
  const lo = (v[a] + v[b]) >>> 0;
  v[a + 1] = (v[a + 1] + v[b + 1] + (lo < (v[a] >>> 0) ? 1 : 0)) >>> 0;
  v[a] = lo;
}

function add64_3(v, a, b, mLo, mHi) {
  let lo = (v[a] + v[b]) >>> 0;
  let hi = (v[a + 1] + v[b + 1] + (lo < (v[a] >>> 0) ? 1 : 0)) >>> 0;
  const lo2 = (lo + mLo) >>> 0;
  hi = (hi + mHi + (lo2 < lo ? 1 : 0)) >>> 0;
  v[a] = lo2;
  v[a + 1] = hi;
}

function rotr64(v, d, s, bits) {
  const xLo = (v[d] ^ v[s]) >>> 0;
  const xHi = (v[d + 1] ^ v[s + 1]) >>> 0;
  if (bits === 32) {
    v[d] = xHi; v[d + 1] = xLo;
  } else if (bits < 32) {
    v[d] = ((xLo >>> bits) | (xHi << (32 - bits))) >>> 0;
    v[d + 1] = ((xHi >>> bits) | (xLo << (32 - bits))) >>> 0;
  } else {
    const k = bits - 32;
    v[d] = ((xHi >>> k) | (xLo << (32 - k))) >>> 0;
    v[d + 1] = ((xLo >>> k) | (xHi << (32 - k))) >>> 0;
  }
}

function blake2bG(v, a, b, c, d, xLo, xHi, yLo, yHi) {
  add64_3(v, a, b, xLo, xHi); rotr64(v, d, a, 32);
  add64(v, c, d); rotr64(v, b, c, 24);
  add64_3(v, a, b, yLo, yHi); rotr64(v, d, a, 16);
  add64(v, c, d); rotr64(v, b, c, 63);
}

export function blake2b(input, outLen = 64) {
  const h = new Uint32Array(BLAKE2B_IV);
  h[0] ^= 0x01010000 ^ outLen;
  const v = new Uint32Array(32);
  const m = new Uint32Array(32);
  let tLo = 0;
  let tHi = 0;
  const total = input.length;
  let offset = 0;

  while (total - offset > 128 || total === 0) {
    const take = total === 0 ? 0 : 128;
    m.fill(0);
    if (take > 0) {
      const dv = new DataView(input.buffer, input.byteOffset + offset, take);
      for (let i = 0; i < 32; i++) m[i] = dv.getUint32(i * 4, true);
    }
    tLo = (tLo + take) >>> 0;
    if (tLo < take) tHi = (tHi + 1) >>> 0;
    const last = total === 0;
    v.set(h, 0);
    v.set(BLAKE2B_IV, 16);
    v[24] ^= tLo; v[25] ^= tHi;
    if (last) { v[28] = ~v[28]; v[29] = ~v[29]; }
    for (let r = 0; r < 12; r++) {
      const s = BLAKE2B_SIGMA[r];
      blake2bG(v, 0, 8, 16, 24, m[s[0] * 2], m[s[0] * 2 + 1], m[s[1] * 2], m[s[1] * 2 + 1]);
      blake2bG(v, 2, 10, 18, 26, m[s[2] * 2], m[s[2] * 2 + 1], m[s[3] * 2], m[s[3] * 2 + 1]);
      blake2bG(v, 4, 12, 20, 28, m[s[4] * 2], m[s[4] * 2 + 1], m[s[5] * 2], m[s[5] * 2 + 1]);
      blake2bG(v, 6, 14, 22, 30, m[s[6] * 2], m[s[6] * 2 + 1], m[s[7] * 2], m[s[7] * 2 + 1]);
      blake2bG(v, 0, 10, 20, 30, m[s[8] * 2], m[s[8] * 2 + 1], m[s[9] * 2], m[s[9] * 2 + 1]);
      blake2bG(v, 2, 12, 22, 24, m[s[10] * 2], m[s[10] * 2 + 1], m[s[11] * 2], m[s[11] * 2 + 1]);
      blake2bG(v, 4, 14, 16, 26, m[s[12] * 2], m[s[12] * 2 + 1], m[s[13] * 2], m[s[13] * 2 + 1]);
      blake2bG(v, 6, 8, 18, 28, m[s[14] * 2], m[s[14] * 2 + 1], m[s[15] * 2], m[s[15] * 2 + 1]);
    }
    for (let i = 0; i < 16; i++) h[i] ^= v[i] ^ v[16 + i];
    if (last) {
      const out = new Uint8Array(outLen);
      const hb = new Uint8Array(h.buffer);
      out.set(hb.subarray(0, outLen));
      return out;
    }
    offset += 128;
  }

  const rem = total - offset;
  const padded = new Uint8Array(128);
  padded.set(input.subarray(offset));
  const dv = new DataView(padded.buffer);
  for (let i = 0; i < 32; i++) m[i] = dv.getUint32(i * 4, true);
  tLo = (tLo + rem) >>> 0;
  if (tLo < rem) tHi = (tHi + 1) >>> 0;
  v.set(h, 0);
  v.set(BLAKE2B_IV, 16);
  v[24] ^= tLo; v[25] ^= tHi;
  v[28] = ~v[28]; v[29] = ~v[29];
  for (let r = 0; r < 12; r++) {
    const s = BLAKE2B_SIGMA[r];
    blake2bG(v, 0, 8, 16, 24, m[s[0] * 2], m[s[0] * 2 + 1], m[s[1] * 2], m[s[1] * 2 + 1]);
    blake2bG(v, 2, 10, 18, 26, m[s[2] * 2], m[s[2] * 2 + 1], m[s[3] * 2], m[s[3] * 2 + 1]);
    blake2bG(v, 4, 12, 20, 28, m[s[4] * 2], m[s[4] * 2 + 1], m[s[5] * 2], m[s[5] * 2 + 1]);
    blake2bG(v, 6, 14, 22, 30, m[s[6] * 2], m[s[6] * 2 + 1], m[s[7] * 2], m[s[7] * 2 + 1]);
    blake2bG(v, 0, 10, 20, 30, m[s[8] * 2], m[s[8] * 2 + 1], m[s[9] * 2], m[s[9] * 2 + 1]);
    blake2bG(v, 2, 12, 22, 24, m[s[10] * 2], m[s[10] * 2 + 1], m[s[11] * 2], m[s[11] * 2 + 1]);
    blake2bG(v, 4, 14, 16, 26, m[s[12] * 2], m[s[12] * 2 + 1], m[s[13] * 2], m[s[13] * 2 + 1]);
    blake2bG(v, 6, 8, 18, 28, m[s[14] * 2], m[s[14] * 2 + 1], m[s[15] * 2], m[s[15] * 2 + 1]);
  }
  for (let i = 0; i < 16; i++) h[i] ^= v[i] ^ v[16 + i];
  const out = new Uint8Array(outLen);
  out.set(new Uint8Array(h.buffer).subarray(0, outLen));
  return out;
}

function u32le(n) {
  const b = new Uint8Array(4);
  new DataView(b.buffer).setUint32(0, n >>> 0, true);
  return b;
}

function blake2bLong(input, outLen) {
  const prefix = concatBytes(u32le(outLen), input);
  if (outLen <= 64) return blake2b(prefix, outLen);
  const out = new Uint8Array(outLen);
  let v = blake2b(prefix, 64);
  out.set(v.subarray(0, 32), 0);
  let pos = 32;
  const r = Math.ceil(outLen / 32) - 2;
  for (let i = 2; i <= r; i++) {
    v = blake2b(v, 64);
    out.set(v.subarray(0, 32), pos);
    pos += 32;
  }
  const last = blake2b(v, outLen - 32 * r);
  out.set(last, pos);
  return out;
}

let _mHi = 0;
function mul32x2Lo(x, y) {
  const xLo = x & 0xffff, xHi = x >>> 16;
  const yLo = y & 0xffff, yHi = y >>> 16;
  const p0 = xLo * yLo;
  const p1 = xLo * yHi + xHi * yLo;
  const p2 = xHi * yHi;
  const lo = (p0 + ((p1 & 0xffff) << 16)) >>> 0;
  const hi = (p2 + Math.floor(p1 * 0.0000152587890625) + (lo < (p0 >>> 0) ? 1 : 0)) >>> 0;
  _mHi = ((hi << 1) | (lo >>> 31)) >>> 0;
  return (lo << 1) >>> 0;
}

function argonGBFast(b, a, bIdx, c, d) {
  let aLo = b[a], aHi = b[a + 1], bLo = b[bIdx], bHi = b[bIdx + 1];
  let cLo = b[c], cHi = b[c + 1], dLo = b[d], dHi = b[d + 1];

  let mLo = mul32x2Lo(aLo, bLo), mHi = _mHi;
  let tLo = (aLo + bLo) >>> 0, tHi = (aHi + bHi + (tLo < aLo ? 1 : 0)) >>> 0;
  aLo = (tLo + mLo) >>> 0; aHi = (tHi + mHi + (aLo < tLo ? 1 : 0)) >>> 0;
  let xLo = (dLo ^ aLo) >>> 0, xHi = (dHi ^ aHi) >>> 0;
  dLo = xHi; dHi = xLo;

  mLo = mul32x2Lo(cLo, dLo); mHi = _mHi;
  tLo = (cLo + dLo) >>> 0; tHi = (cHi + dHi + (tLo < cLo ? 1 : 0)) >>> 0;
  cLo = (tLo + mLo) >>> 0; cHi = (tHi + mHi + (cLo < tLo ? 1 : 0)) >>> 0;
  xLo = (bLo ^ cLo) >>> 0; xHi = (bHi ^ cHi) >>> 0;
  bLo = ((xLo >>> 24) | (xHi << 8)) >>> 0; bHi = ((xHi >>> 24) | (xLo << 8)) >>> 0;

  mLo = mul32x2Lo(aLo, bLo); mHi = _mHi;
  tLo = (aLo + bLo) >>> 0; tHi = (aHi + bHi + (tLo < aLo ? 1 : 0)) >>> 0;
  aLo = (tLo + mLo) >>> 0; aHi = (tHi + mHi + (aLo < tLo ? 1 : 0)) >>> 0;
  xLo = (dLo ^ aLo) >>> 0; xHi = (dHi ^ aHi) >>> 0;
  dLo = ((xLo >>> 16) | (xHi << 16)) >>> 0; dHi = ((xHi >>> 16) | (xLo << 16)) >>> 0;

  mLo = mul32x2Lo(cLo, dLo); mHi = _mHi;
  tLo = (cLo + dLo) >>> 0; tHi = (cHi + dHi + (tLo < cLo ? 1 : 0)) >>> 0;
  cLo = (tLo + mLo) >>> 0; cHi = (tHi + mHi + (cLo < tLo ? 1 : 0)) >>> 0;
  xLo = (bLo ^ cLo) >>> 0; xHi = (bHi ^ cHi) >>> 0;
  bLo = ((xHi >>> 31) | (xLo << 1)) >>> 0; bHi = ((xLo >>> 31) | (xHi << 1)) >>> 0;

  b[a] = aLo; b[a + 1] = aHi; b[bIdx] = bLo; b[bIdx + 1] = bHi;
  b[c] = cLo; b[c + 1] = cHi; b[d] = dLo; b[d + 1] = dHi;
}

function argonPermuteP(r) {
  // 8 rows of 16 u64 words (32 u32 words per row)
  for (let row = 0; row < 8; row++) {
    const o = row * 32;
    argonGBFast(r, o + 0, o + 8, o + 16, o + 24);
    argonGBFast(r, o + 2, o + 10, o + 18, o + 26);
    argonGBFast(r, o + 4, o + 12, o + 20, o + 28);
    argonGBFast(r, o + 6, o + 14, o + 22, o + 30);
    argonGBFast(r, o + 0, o + 10, o + 20, o + 30);
    argonGBFast(r, o + 2, o + 12, o + 22, o + 24);
    argonGBFast(r, o + 4, o + 14, o + 16, o + 26);
    argonGBFast(r, o + 6, o + 8, o + 18, o + 28);
  }
  // 8 columns: v = [0:c, 1:c+2, 2:32+c, 3:32+c+2, 4:64+c, 5:64+c+2, 6:96+c, 7:96+c+2,
  //                 8:128+c, 9:128+c+2, 10:160+c, 11:160+c+2, 12:192+c, 13:192+c+2, 14:224+c, 15:224+c+2]
  for (let col = 0; col < 8; col++) {
    const c = col * 4;
    argonGBFast(r, c, 64 + c, 128 + c, 192 + c);               // 0, 4, 8, 12
    argonGBFast(r, c + 2, 64 + c + 2, 128 + c + 2, 192 + c + 2); // 1, 5, 9, 13
    argonGBFast(r, 32 + c, 96 + c, 160 + c, 224 + c);           // 2, 6, 10, 14
    argonGBFast(r, 32 + c + 2, 96 + c + 2, 160 + c + 2, 224 + c + 2); // 3, 7, 11, 15
    argonGBFast(r, c, 64 + c + 2, 160 + c, 224 + c + 2);       // 0, 5, 10, 15
    argonGBFast(r, c + 2, 96 + c, 160 + c + 2, 192 + c);       // 1, 6, 11, 12
    argonGBFast(r, 32 + c, 96 + c + 2, 128 + c, 192 + c + 2);  // 2, 7, 8, 13
    argonGBFast(r, 32 + c + 2, 64 + c, 128 + c + 2, 224 + c);  // 3, 4, 9, 14
  }
}

function argonCompress(mem, dstOff, xOff, yOff, xorExisting, rBuf, zBuf) {
  for (let i = 0; i < 256; i++) rBuf[i] = mem[xOff + i] ^ mem[yOff + i];
  zBuf.set(rBuf);
  argonPermuteP(zBuf);
  if (xorExisting) {
    for (let i = 0; i < 256; i++) mem[dstOff + i] ^= rBuf[i] ^ zBuf[i];
  } else {
    for (let i = 0; i < 256; i++) mem[dstOff + i] = rBuf[i] ^ zBuf[i];
  }
}

export function argon2id(passwordBytes, saltBytes, { memoryKiB = 65536, passes = 3, tagLength = 32 } = {}) {
  const lanes = 1;
  const q = Math.floor(memoryKiB / (4 * lanes)) * 4; // blocks in single lane (multiple of 4)
  const segmentLength = q / 4;
  const h0Input = concatBytes(
    u32le(lanes), u32le(tagLength), u32le(memoryKiB), u32le(passes),
    u32le(0x13), u32le(2), // version 0x13, type 2 = Argon2id
    u32le(passwordBytes.length), passwordBytes,
    u32le(saltBytes.length), saltBytes,
    u32le(0), u32le(0), // secret len 0, ad len 0
  );
  const h0 = blake2b(h0Input, 64);

  // Each 1024-byte block = 256 Uint32 words. Add 4 scratch blocks at end for address generation.
  const mem = new Uint32Array((q + 4) * 256);
  const b0 = blake2bLong(concatBytes(h0, u32le(0), u32le(0)), 1024);
  const b1 = blake2bLong(concatBytes(h0, u32le(1), u32le(0)), 1024);
  mem.set(new Uint32Array(b0.buffer, b0.byteOffset, 256), 0);
  mem.set(new Uint32Array(b1.buffer, b1.byteOffset, 256), 256);

  const rBuf = new Uint32Array(256);
  const zBuf = new Uint32Array(256);
  const zeroOff = q * 256;
  const inputOff = (q + 1) * 256;
  const scratchOff = (q + 2) * 256;
  const addrOff = (q + 3) * 256;

  function nextAddresses() {
    mem[inputOff + 12] = (mem[inputOff + 12] + 1) >>> 0;
    argonCompress(mem, scratchOff, zeroOff, inputOff, false, rBuf, zBuf);
    argonCompress(mem, addrOff, zeroOff, scratchOff, false, rBuf, zBuf);
  }

  for (let pass = 0; pass < passes; pass++) {
    for (let slice = 0; slice < 4; slice++) {
      const dataIndependent = pass === 0 && slice < 2;
      if (dataIndependent) {
        mem.fill(0, inputOff, inputOff + 256);
        mem[inputOff + 0] = pass;
        mem[inputOff + 2] = 0; // lane 0
        mem[inputOff + 4] = slice;
        mem[inputOff + 6] = q;
        mem[inputOff + 8] = passes;
        mem[inputOff + 10] = 2; // Argon2id
      }
      const startIndex = pass === 0 && slice === 0 ? 2 : 0;
      if (dataIndependent && startIndex === 2) nextAddresses();

      for (let idx = startIndex; idx < segmentLength; idx++) {
        const currBlock = slice * segmentLength + idx;
        const prevBlock = currBlock === 0 ? q - 1 : currBlock - 1;

        let j1;
        if (dataIndependent) {
          if (idx % 128 === 0) nextAddresses();
          j1 = mem[addrOff + (idx % 128) * 2] >>> 0;
        } else {
          j1 = mem[prevBlock * 256] >>> 0;
        }

        const areaSize = pass === 0
          ? slice * segmentLength + idx - 1
          : q - segmentLength + idx - 1;
        const x = Number((BigInt(j1) * BigInt(j1)) >> 32n);
        const y = Number((BigInt(areaSize) * BigInt(x)) >> 32n);
        const relPos = areaSize - 1 - y;
        const startPos = (pass === 0 || slice === 3) ? 0 : (slice + 1) * segmentLength;
        const refBlock = (startPos + relPos) % q;

        argonCompress(mem, currBlock * 256, prevBlock * 256, refBlock * 256, pass > 0, rBuf, zBuf);
      }
    }
  }

  const finalBlock = new Uint8Array(mem.buffer, (q - 1) * 1024, 1024);
  const tag = blake2bLong(finalBlock, tagLength);
  mem.fill(0);
  return tag;
}
