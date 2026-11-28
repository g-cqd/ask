// GatewayShell/app.mjs — Browser controller application (ADR-0170).

import {
  argon2id, base64ToBytes, bytesToBase64, chacha20Poly1305Open, chacha20Poly1305Seal,
  ControllerChannel, encodeAttach, encodeInput, encodeRelayFrame, encodeResize, encodeStart,
  importX25519PrivateSeed, keyFingerprint, openSealedList, parseListsBody, parseRelayFrame,
  RelayKind, verifyShellManifest,
} from "./crypto.mjs";

const STORAGE_WRAPPED = "ask.gateway.wrappedController.v1";

const el = (id) => document.getElementById(id);
let identity = null; // { privateKey: non-extractable CryptoKey, publicBytes: Uint8Array }
let ws = null;
let nextChannelId = 1;
let activeChannel = null; // { id, controllerChannel, cleanup }

async function checkAndRegisterShellPin() {
  const pinEl = el("shell-pin");
  try {
    const [mRes, sRes] = await Promise.all([
      fetch("/manifest.json", { cache: "no-store" }),
      fetch("/manifest.sig", { cache: "no-store" }),
    ]);
    if (mRes.ok && sRes.ok) {
      const mBytes = new Uint8Array(await mRes.arrayBuffer());
      const sBytes = new Uint8Array(await sRes.arrayBuffer());
      const { fingerprint } = await verifyShellManifest(mBytes, sBytes);
      pinEl.textContent = `Signed shell: ${fingerprint}`;
      if ("serviceWorker" in navigator) {
        const reg = await navigator.serviceWorker.register("/sw.js");
        reg.active?.postMessage({ type: "pin-status" });
        navigator.serviceWorker.addEventListener("message", (ev) => {
          if (ev.data?.type === "pin-status" && ev.data.fingerprint) {
            pinEl.textContent = `Pinned shell key: ${ev.data.fingerprint}`;
          }
        });
      }
    } else {
      pinEl.textContent = "Unsigned shell (run `ask gateway sign-shell`)";
    }
  } catch (err) {
    pinEl.textContent = `Shell verification failed: ${err.message}`;
  }
}

async function unlockWithPassphrase() {
  const pass = el("passphrase").value;
  const msg = el("unlock-msg");
  if (pass.length < 8) {
    msg.textContent = "Use a passphrase of at least 8 characters.";
    return;
  }
  msg.textContent = "Deriving key with Argon2id (64 MiB / 3 passes)…";
  await new Promise((r) => setTimeout(r, 20));
  try {
    const storedRaw = localStorage.getItem(STORAGE_WRAPPED);
    const passBytes = new TextEncoder().encode(pass);
    let seed32;
    if (storedRaw) {
      const stored = JSON.parse(storedRaw);
      const salt = base64ToBytes(stored.salt);
      const nonce = base64ToBytes(stored.nonce);
      const sealed = base64ToBytes(stored.sealed);
      const kek = argon2id(passBytes, salt, { memoryKiB: 65536, passes: 3, tagLength: 32 });
      try {
        seed32 = chacha20Poly1305Open(kek, nonce, sealed, new TextEncoder().encode("ask-controller-v1"));
      } finally {
        kek.fill(0);
      }
    } else {
      const salt = crypto.getRandomValues(new Uint8Array(16));
      const nonce = crypto.getRandomValues(new Uint8Array(12));
      seed32 = crypto.getRandomValues(new Uint8Array(32));
      const kek = argon2id(passBytes, salt, { memoryKiB: 65536, passes: 3, tagLength: 32 });
      try {
        const sealed = chacha20Poly1305Seal(kek, nonce, seed32, new TextEncoder().encode("ask-controller-v1"));
        localStorage.setItem(STORAGE_WRAPPED, JSON.stringify({
          salt: bytesToBase64(salt),
          nonce: bytesToBase64(nonce),
          sealed: bytesToBase64(sealed),
        }));
      } finally {
        kek.fill(0);
      }
    }
    passBytes.fill(0);
    try {
      identity = await importX25519PrivateSeed(seed32);
    } finally {
      seed32.fill(0);
    }
    el("passphrase").value = "";
    msg.textContent = "";
    await enterDashboard();
  } catch {
    msg.textContent = "Wrong passphrase for the stored controller key.";
  }
}

async function importKeyFile(file) {
  const msg = el("unlock-msg");
  try {
    const raw = new Uint8Array(await file.arrayBuffer());
    let seed;
    if (raw.length === 32) {
      seed = raw;
    } else {
      const text = new TextDecoder().decode(raw).trim();
      seed = base64ToBytes(text);
    }
    if (seed.length !== 32) throw new Error("key file must decode to 32 bytes");
    try {
      identity = await importX25519PrivateSeed(seed);
    } finally {
      seed.fill(0);
    }
    msg.textContent = "";
    await enterDashboard();
  } catch (err) {
    msg.textContent = `Cannot import key: ${err.message}`;
  }
}

async function enterDashboard() {
  el("unlock-view").hidden = true;
  el("dashboard-view").hidden = false;
  const fp = await keyFingerprint(identity.publicBytes);
  const pubB64 = bytesToBase64(identity.publicBytes);
  el("ctrl-fp").textContent = fp;
  el("copy-trust").onclick = () => {
    navigator.clipboard.writeText(`ask gateway trust ${pubB64} --label "Browser"`);
  };
  connectSocket();
}

function connectSocket() {
  const proto = location.protocol === "https:" ? "wss:" : "ws:";
  ws = new WebSocket(`${proto}//${location.host}/socket`);
  ws.binaryType = "arraybuffer";
  ws.onopen = () => {
    el("conn-status").textContent = "Connected";
    ws.send(encodeRelayFrame(RelayKind.HELLO, 0, new Uint8Array([0, 1, 2])));
  };
  ws.onclose = () => {
    el("conn-status").textContent = "Disconnected — reconnecting…";
    setTimeout(connectSocket, 2000);
  };
  ws.onmessage = async (ev) => {
    const frame = parseRelayFrame(new Uint8Array(ev.data));
    if (frame.kind === RelayKind.PING) {
      ws.send(encodeRelayFrame(RelayKind.PONG, 0, frame.body));
    } else if (frame.kind === RelayKind.LISTS) {
      await renderLists(frame.body);
    } else if (activeChannel && frame.channel === activeChannel.id) {
      await handleChannelFrame(frame);
    }
  };
}

async function renderLists(body) {
  const container = el("nodes-list");
  container.replaceChildren();
  const entries = parseListsBody(body);
  if (entries.length === 0) {
    const p = document.createElement("p");
    p.className = "hint";
    p.textContent = "No computers are currently connected to the gateway.";
    container.appendChild(p);
    return;
  }
  for (const entry of entries) {
    const nodeFp = await keyFingerprint(entry.nodeKey);
    const card = document.createElement("div");
    card.className = "node-card";
    const header = document.createElement("div");
    header.className = "node-header";
    header.textContent = `Node ${nodeFp}`;
    card.appendChild(header);
    try {
      const jsonBytes = await openSealedList(entry.sealedList, identity);
      const list = JSON.parse(new TextDecoder().decode(jsonBytes));
      for (const s of list.sessions ?? []) {
        const row = document.createElement("div");
        row.className = "session-row";
        const info = document.createElement("span");
        info.textContent = `[#${s.id}] ${s.folder} — ${s.label}`;
        const btn = document.createElement("button");
        btn.type = "button";
        btn.textContent = "Attach";
        btn.onclick = () => openTerminal(entry.nodeKey, nodeFp, { mode: "attach", session: s.id, title: `${s.folder} (#${s.id})` });
        row.append(info, btn);
        card.appendChild(row);
      }
      for (const folder of list.folders ?? []) {
        const row = document.createElement("div");
        row.className = "folder-row";
        const info = document.createElement("span");
        info.textContent = `Folder: ${folder}`;
        const btn = document.createElement("button");
        btn.type = "button";
        btn.textContent = "Start session";
        btn.onclick = () => openTerminal(entry.nodeKey, nodeFp, { mode: "start", folder, title: `New session in ${folder}` });
        row.append(info, btn);
        card.appendChild(row);
      }
    } catch {
      const locked = document.createElement("div");
      locked.className = "hint";
      locked.textContent = "Not trusted on this computer yet — run the `ask gateway trust` command above on it.";
      card.appendChild(locked);
    }
    container.appendChild(card);
  }
}

async function mountTerminalWidget(hostEl, onInput, onResize) {
  hostEl.replaceChildren();
  try {
    const xtermMod = await import("./vendor/xterm.mjs");
    const graphMod = await import("./vendor/addon-unicode-graphemes.mjs");
    if (!document.getElementById("xterm-css")) {
      const link = document.createElement("link");
      link.id = "xterm-css";
      link.rel = "stylesheet";
      link.href = "/vendor/xterm.css";
      document.head.appendChild(link);
    }
    const Terminal = xtermMod.Terminal ?? xtermMod.default?.Terminal;
    const Addon = graphMod.UnicodeGraphemesAddon ?? graphMod.default?.UnicodeGraphemesAddon;
    const term = new Terminal({ cols: 100, rows: 30, cursorBlink: true, allowProposedApi: true });
    if (Addon) {
      term.loadAddon(new Addon());
      term.unicode.activeVersion = "15";
    }
    term.open(hostEl);
    term.focus();
    const d1 = term.onData((str) => onInput(new TextEncoder().encode(str)));
    const d2 = term.onResize(({ cols, rows }) => onResize(cols, rows));
    return {
      cols: term.cols,
      rows: term.rows,
      write: (bytes) => term.write(bytes),
      dispose: () => { d1.dispose(); d2.dispose(); term.dispose(); },
    };
  } catch {
    // Clean built-in keyboard fallback when vendor/xterm.mjs has not been copied yet.
    let screenText = "";
    const onKey = (ev) => {
      ev.preventDefault();
      let seq = null;
      if (ev.ctrlKey && ev.key.length === 1) {
        const code = ev.key.toUpperCase().charCodeAt(0) - 64;
        if (code > 0 && code < 32) seq = String.fromCharCode(code);
      } else if (ev.key === "Enter") seq = "\r";
      else if (ev.key === "Backspace") seq = "\x7f";
      else if (ev.key === "Escape") seq = "\x1b";
      else if (ev.key === "Tab") seq = "\t";
      else if (ev.key === "ArrowUp") seq = "\x1b[A";
      else if (ev.key === "ArrowDown") seq = "\x1b[B";
      else if (ev.key === "ArrowRight") seq = "\x1b[C";
      else if (ev.key === "ArrowLeft") seq = "\x1b[D";
      else if (ev.key.length === 1 && !ev.metaKey) seq = ev.key;
      if (seq) onInput(new TextEncoder().encode(seq));
    };
    hostEl.addEventListener("keydown", onKey);
    hostEl.focus();
    return {
      cols: 100,
      rows: 30,
      write: (bytes) => {
        const chunk = new TextDecoder().decode(bytes);
        screenText = (screenText + chunk.replace(/\x1b\[[0-9;?<>=]*[ -/]*[@-~]/g, "")).slice(-16000);
        hostEl.textContent = screenText;
      },
      dispose: () => hostEl.removeEventListener("keydown", onKey),
    };
  }
}

async function openTerminal(nodeKey, nodeFp, target) {
  el("dashboard-view").hidden = true;
  el("terminal-view").hidden = false;
  el("term-title").textContent = `${target.title} (${nodeFp})`;

  const channelId = nextChannelId;
  nextChannelId += 2;
  const { channel, first } = await ControllerChannel.open(identity, nodeKey);

  const widget = await mountTerminalWidget(
    el("terminal-host"),
    (bytes) => {
      if (activeChannel?.ready) {
        ws?.send(encodeRelayFrame(RelayKind.DATA, channelId, channel.send(encodeInput(bytes))));
      }
    },
    (cols, rows) => {
      if (activeChannel?.ready) {
        ws?.send(encodeRelayFrame(RelayKind.DATA, channelId, channel.send(encodeResize(cols, rows))));
      }
    },
  );

  activeChannel = {
    id: channelId,
    channel,
    target,
    widget,
    ready: false,
  };

  const openBody = new Uint8Array(32 + first.length);
  openBody.set(nodeKey, 0);
  openBody.set(first, 32);
  ws.send(encodeRelayFrame(RelayKind.OPEN, channelId, openBody));
}

async function handleChannelFrame(frame) {
  if (!activeChannel) return;
  if (frame.kind === RelayKind.CLOSE) {
    const words = new TextDecoder().decode(frame.body.slice(1));
    activeChannel.widget.write(new TextEncoder().encode(`\r\n[channel closed: ${words}]\r\n`));
    activeChannel.ready = false;
    return;
  }
  if (frame.kind !== RelayKind.DATA) return;
  if (!activeChannel.ready) {
    await activeChannel.channel.finish(frame.body);
    activeChannel.ready = true;
    const { cols, rows } = activeChannel.widget;
    const firstMsg = activeChannel.target.mode === "attach"
      ? encodeAttach(cols, rows, activeChannel.target.session)
      : encodeStart(cols, rows, activeChannel.target.folder);
    ws.send(encodeRelayFrame(RelayKind.DATA, activeChannel.id, activeChannel.channel.send(firstMsg)));
    return;
  }
  const msg = activeChannel.channel.receive(frame.body);
  if (msg.type === "output") {
    activeChannel.widget.write(msg.bytes);
  } else if (msg.type === "ended" || msg.type === "refused") {
    activeChannel.widget.write(new TextEncoder().encode(`\r\n[${msg.type}: ${msg.reason}]\r\n`));
  }
}

el("term-detach").onclick = () => {
  if (activeChannel) {
    if (ws?.readyState === WebSocket.OPEN) {
      ws.send(encodeRelayFrame(RelayKind.CLOSE, activeChannel.id, new Uint8Array([0])));
    }
    activeChannel.widget.dispose();
    activeChannel = null;
  }
  el("terminal-view").hidden = true;
  el("dashboard-view").hidden = false;
};

el("unlock-passphrase").onclick = unlockWithPassphrase;
el("key-file").onchange = (ev) => {
  const file = ev.target.files?.[0];
  if (file) importKeyFile(file);
};

checkAndRegisterShellPin();
