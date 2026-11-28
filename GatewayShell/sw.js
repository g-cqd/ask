// GatewayShell/sw.js — Release-key-pinning Service Worker (ADR-0170).
// On first install, pins the Ed25519 public key that signed /manifest.json (/manifest.sig).
// On every subsequent install/update, refuses any manifest not signed by the pinned key or any file whose SHA-256 differs.

const DB_NAME = "ask-gateway-shell-pin";
const STORE = "pin";
const PIN_KEY = "releasePublicKey";
const CACHE_PREFIX = "ask-gateway-shell-v1-";
const DOMAIN = new TextEncoder().encode("ask-gateway-shell/1\n");

function openPinDB() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, 1);
    req.onupgradeneeded = () => req.result.createObjectStore(STORE);
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function getPinnedKey() {
  const db = await openPinDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE, "readonly");
    const r = tx.objectStore(STORE).get(PIN_KEY);
    r.onsuccess = () => resolve(r.result ?? null);
    r.onerror = () => reject(r.error);
  });
}

async function setPinnedKey(base64Key) {
  const db = await openPinDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE, "readwrite");
    tx.objectStore(STORE).put(base64Key, PIN_KEY);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

function base64ToBytes(b64) {
  let norm = b64.trim().replace(/-/g, "+").replace(/_/g, "/");
  while (norm.length % 4 !== 0) norm += "=";
  const bin = atob(norm);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function bytesToHex(bytes) {
  let s = "";
  for (let i = 0; i < bytes.length; i++) s += bytes[i].toString(16).padStart(2, "0");
  return s;
}

async function fingerprintOf(keyBytes) {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", keyBytes));
  const hex = bytesToHex(digest.slice(0, 16));
  const parts = [];
  for (let i = 0; i < 32; i += 4) parts.push(hex.slice(i, i + 4));
  return parts.join(" ");
}

async function verifyAndCacheShell() {
  const [manifestRes, sigRes] = await Promise.all([
    fetch("/manifest.json", { cache: "no-store", credentials: "same-origin" }),
    fetch("/manifest.sig", { cache: "no-store", credentials: "same-origin" }),
  ]);
  if (!manifestRes.ok || !sigRes.ok) throw new Error("manifest or signature missing");
  const manifestBytes = new Uint8Array(await manifestRes.arrayBuffer());
  const sigBytes = new Uint8Array(sigRes ? await sigRes.arrayBuffer() : new ArrayBuffer(0));
  const manifest = JSON.parse(new TextDecoder().decode(manifestBytes));
  if (manifest.version !== 1 || typeof manifest.publicKey !== "string" || typeof manifest.files !== "object") {
    throw new Error("malformed manifest");
  }

  const keyBytes = base64ToBytes(manifest.publicKey);
  const pinned = await getPinnedKey();
  if (pinned !== null && bytesToHex(base64ToBytes(pinned)) !== bytesToHex(keyBytes)) {
    throw new Error("shell update refused: signing key differs from pinned release key");
  }

  const signedMessage = new Uint8Array(DOMAIN.length + manifestBytes.length);
  signedMessage.set(DOMAIN, 0);
  signedMessage.set(manifestBytes, DOMAIN.length);
  const edKey = await crypto.subtle.importKey("raw", keyBytes, { name: "Ed25519" }, false, ["verify"]);
  const valid = await crypto.subtle.verify("Ed25519", edKey, sigBytes, signedMessage);
  if (!valid) throw new Error("shell update refused: invalid Ed25519 manifest signature");

  const manifestDigest = bytesToHex(new Uint8Array(await crypto.subtle.digest("SHA-256", manifestBytes))).slice(0, 16);
  const cacheName = CACHE_PREFIX + manifestDigest;
  const cache = await caches.open(cacheName);

  for (const [webPath, expectedHex] of Object.entries(manifest.files)) {
    const res = await fetch(webPath, { cache: "no-store", credentials: "same-origin" });
    if (!res.ok) throw new Error(`missing shell asset ${webPath}`);
    const body = new Uint8Array(await res.arrayBuffer());
    const actualHex = bytesToHex(new Uint8Array(await crypto.subtle.digest("SHA-256", body)));
    if (actualHex !== expectedHex) {
      await caches.delete(cacheName);
      throw new Error(`tampered shell asset ${webPath}`);
    }
    const headers = new Headers(res.headers);
    await cache.put(webPath, new Response(body, { status: 200, headers }));
  }

  if (pinned === null) await setPinnedKey(manifest.publicKey);
  for (const existing of await caches.keys()) {
    if (existing.startsWith(CACHE_PREFIX) && existing !== cacheName) await caches.delete(existing);
  }
}

self.addEventListener("install", (event) => {
  event.waitUntil(verifyAndCacheShell().then(() => self.skipWaiting()));
});

self.addEventListener("activate", (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener("message", (event) => {
  if (event.data?.type === "pin-status") {
    event.waitUntil((async () => {
      const pinned = await getPinnedKey();
      const fingerprint = pinned ? await fingerprintOf(base64ToBytes(pinned)) : null;
      event.source?.postMessage({ type: "pin-status", pinnedPublicKey: pinned, fingerprint });
    })());
  }
});

self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin) return;
  if (url.pathname === "/socket" || url.pathname === "/manifest.json" || url.pathname === "/manifest.sig" || url.pathname === "/sw.js") {
    return;
  }
  const lookupPath = url.pathname === "/" ? "/index.html" : url.pathname;
  event.respondWith((async () => {
    const names = (await caches.keys()).filter((k) => k.startsWith(CACHE_PREFIX));
    for (const name of names) {
      const cache = await caches.open(name);
      const hit = await cache.match(lookupPath);
      if (hit) return hit;
    }
    return new Response("Unverified asset blocked by pinned shell service worker.", { status: 403 });
  })());
});
