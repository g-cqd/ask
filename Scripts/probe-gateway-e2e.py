#!/usr/bin/env python3
"""ADR-0170 end-to-end multi-process probe: ask session + ask gateway node + ask gateway serve + JS GatewayShell client.

Exercises the real release `ask` binary across all processes:
1. Signs `GatewayShell` with `ask gateway sign-shell` and verifies `manifest.json` + `manifest.sig` + asset SHA-256s in JS.
2. Enrolls the node on the gateway (`ask gateway enroll`) and trusts the JS controller on the node (`ask gateway trust`).
3. Runs `ask gateway serve`, an interactive `ask` session (`gateway.enabled`), and `ask gateway node`.
4. Connects from Node.js using `GatewayShell/crypto.mjs` over HTTP + WebSocket:
   - verifies CSP headers and Ed25519 shell signature,
   - opens the Noise N `SealedList` and checks both `sessions` and `folders`,
   - opens an end-to-end Noise IK `ControllerChannel`, attaches to the live `ask` screen, receives `ask>`, and types into it,
   - verifies the typed text appears on the local `ask` PTY,
   - revokes the controller live (`ask gateway untrust`) and verifies a new channel is immediately refused.
5. Verifies `security-audit.jsonl` entries on both node and gateway.
"""
import importlib.util, json, os, shutil, socket, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import probe_keychain

spec = importlib.util.spec_from_file_location("probe_folding", os.path.join(HERE, "probe-folding.py"))
folding = importlib.util.module_from_spec(spec)
spec.loader.exec_module(folding)
agent = folding.agent

ASK = os.path.abspath(os.environ.get("ASK_BIN") or (sys.argv[1] if len(sys.argv) > 1 else ".build/release/ask"))


def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def check(label, condition, detail=""):
    print(("PASS " if condition else "FAIL ") + label + ("" if condition else f": {str(detail)[-700:]}"))
    if not condition:
        sys.exit(1)


def run_cli(env, *args):
    res = subprocess.run([ASK, *args], env=env, capture_output=True, text=True, timeout=30)
    if res.returncode != 0:
        raise RuntimeError(f"ask {' '.join(args)} failed ({res.returncode}): {res.stdout}\n{res.stderr}")
    return res.stdout


def extract_key(output):
    for line in output.splitlines():
        if line.startswith("Key:") or line.startswith("PublicKey:"):
            return line.split(":", 1)[1].strip()
    raise RuntimeError(f"No key found in:\n{output}")


root = tempfile.mkdtemp(dir="/tmp", prefix="askgwe2e-")
procs = []
terminal = None
try:
    node_home = os.path.join(root, "node-home")
    gw_home = os.path.join(root, "gw-home")
    project = os.path.join(root, "project")
    shell_copy = os.path.join(root, "shell")
    os.makedirs(node_home)
    os.makedirs(gw_home)
    os.makedirs(project)
    shutil.copytree(os.path.join(REPO, "GatewayShell"), shell_copy)

    server = agent.Server([agent.turn([("text", "ok")], "end_turn")])

    gw_env = dict(
        os.environ,
        HOME=gw_home,
        XDG_CONFIG_HOME=gw_home + "/config",
        XDG_STATE_HOME=gw_home + "/state",
        ASK_KEYCHAIN_PATH=probe_keychain.throwaway_keychain(),
    )
    node_env = agent.environment(node_home + "/state", server.url, config=node_home + "/config")
    node_env.update(
        HOME=node_home,
        ASK_KEYCHAIN_PATH=probe_keychain.throwaway_keychain(),
        TERM="xterm-256color",
        LANG="en_US.UTF-8",
    )

    # 1. Sign shell and generate keys
    sign_out = run_cli(gw_env, "gateway", "sign-shell", "--shell-dir", shell_copy)
    shell_pub_b64 = extract_key(sign_out)
    check("ask gateway sign-shell wrote manifest.json and manifest.sig",
          os.path.exists(shell_copy + "/manifest.json") and os.path.exists(shell_copy + "/manifest.sig"), sign_out)

    gw_server_key = extract_key(run_cli(gw_env, "gateway", "server-fingerprint"))
    node_pub_key = extract_key(run_cli(node_env, "gateway", "fingerprint"))

    # Generate controller seed (32 bytes of 0x5a) and derive its X25519 public key via GatewayShell/crypto.mjs
    ctrl_pub_b64 = subprocess.check_output(
        [
            "node", "--input-type=module", "-e",
            f"import {{ importX25519PrivateSeed, bytesToBase64 }} from {json.dumps(REPO + '/GatewayShell/crypto.mjs')};"
            "const id = await importX25519PrivateSeed(new Uint8Array(32).fill(0x5a));"
            "process.stdout.write(bytesToBase64(id.publicBytes));"
        ],
        text=True,
        timeout=15,
    ).strip()

    run_cli(gw_env, "gateway", "enroll", node_pub_key, "--label", "laptop")
    run_cli(node_env, "gateway", "trust", ctrl_pub_b64, "--label", "probe-browser")

    nodes_port = free_port()
    controllers_port = free_port()

    os.makedirs(node_home + "/config/ask", exist_ok=True)
    with open(node_home + "/config/ask/config.json", "w") as f:
        json.dump(
            {
                "ui": {"inputPrefix": "ask> "},
                "gateway": {
                    "enabled": True,
                    "address": f"127.0.0.1:{nodes_port}",
                    "key": gw_server_key,
                    "folders": [project],
                },
            },
            f,
        )

    # 2. Start gateway server, interactive ask session, and gateway node
    gw_proc = subprocess.Popen(
        [
            ASK, "gateway", "serve",
            "--nodes-listen", f"127.0.0.1:{nodes_port}",
            "--nodes-cidr", "127.0.0.0/8",
            "--controllers-port", str(controllers_port),
            "--insecure-local-no-access",
            "--shell-dir", shell_copy,
        ],
        env=gw_env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    procs.append(gw_proc)

    deadline = time.time() + 15
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", controllers_port), timeout=0.2):
                break
        except OSError:
            time.sleep(0.1)

    os.environ["ASK_BIN"] = ASK
    terminal = folding.Terminal(project, node_env)
    terminal.until(lambda: "ask>" in terminal.text())

    node_proc = subprocess.Popen(
        [ASK, "gateway", "node"],
        env=node_env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    procs.append(node_proc)

    # 3. Run real JS controller over HTTP + WebSocket + Noise N + Noise IK
    js_driver = os.path.join(root, "driver.mjs")
    with open(js_driver, "w") as f:
        f.write(f"""
import crypto from "node:crypto";
import {{
  bytesToHex, importX25519PrivateSeed, verifyShellManifest,
  openSealedList, ControllerChannel, encodeRelayFrame, parseRelayFrame,
  parseListsBody, encodeAttach, encodeInput, RelayKind
}} from {json.dumps(REPO + "/GatewayShell/crypto.mjs")};

const base = "http://127.0.0.1:{controllers_port}";
const wsUrl = "ws://127.0.0.1:{controllers_port}/socket";
const pinnedPub = {json.dumps(shell_pub_b64)};

// Verify HTTP CSP + signed shell manifest + every listed file's SHA-256
const idxRes = await fetch(base + "/");
const csp = idxRes.headers.get("content-security-policy") || "";
if (!csp.includes("default-src 'none'")) throw new Error("missing strict CSP: " + csp);
const mBytes = new Uint8Array(await (await fetch(base + "/manifest.json")).arrayBuffer());
const sBytes = new Uint8Array(await (await fetch(base + "/manifest.sig")).arrayBuffer());
const {{ manifest }} = await verifyShellManifest(mBytes, sBytes, pinnedPub);
for (const [webPath, expectedHex] of Object.entries(manifest.files)) {{
  const body = new Uint8Array(await (await fetch(base + webPath)).arrayBuffer());
  const actualHex = bytesToHex(new Uint8Array(await crypto.subtle.digest("SHA-256", body)));
  if (actualHex !== expectedHex) throw new Error("hash mismatch for " + webPath);
}}

const id = await importX25519PrivateSeed(new Uint8Array(32).fill(0x5a));
const ws = new WebSocket(wsUrl);
ws.binaryType = "arraybuffer";

const queue = [];
let waiter = null;
ws.onmessage = (ev) => {{
  const frame = parseRelayFrame(new Uint8Array(ev.data));
  if (waiter) {{ const w = waiter; waiter = null; w(frame); }}
  else queue.push(frame);
}};
function nextFrame(timeoutMs = 15000) {{
  if (queue.length > 0) return Promise.resolve(queue.shift());
  return new Promise((resolve, reject) => {{
    const t = setTimeout(() => reject(new Error("timeout waiting for frame")), timeoutMs);
    waiter = (f) => {{ clearTimeout(t); resolve(f); }};
  }});
}}

await new Promise((res, rej) => {{ ws.onopen = res; ws.onerror = rej; }});
ws.send(encodeRelayFrame(RelayKind.HELLO, 0, new Uint8Array([0, 1, 2])));

// Wait until node connects and publishes its non-empty lists frame
let entries = [];
const waitDeadline = Date.now() + 15000;
while (Date.now() < waitDeadline) {{
  const f = await nextFrame();
  if (f.kind === RelayKind.LISTS) {{
    entries = parseListsBody(f.body);
    if (entries.length > 0) break;
  }}
}}
if (entries.length !== 1) throw new Error("expected 1 node list, got " + entries.length);

const plainList = JSON.parse(new TextDecoder().decode(await openSealedList(entries[0].sealedList, id)));
if (!plainList.sessions?.length || !plainList.folders?.length) {{
  throw new Error("unexpected list payload: " + JSON.stringify(plainList));
}}
const sessionId = plainList.sessions[0].id;
const nodeKey = entries[0].nodeKey;

const {{ channel, first }} = await ControllerChannel.open(id, nodeKey);
const openBody = new Uint8Array(32 + first.length);
openBody.set(nodeKey, 0);
openBody.set(first, 32);
ws.send(encodeRelayFrame(RelayKind.OPEN, 1, openBody));

let ans;
while (true) {{
  ans = await nextFrame();
  if (ans.channel === 1 && ans.kind === RelayKind.DATA) break;
}}
await channel.finish(ans.body);
ws.send(encodeRelayFrame(RelayKind.DATA, 1, channel.send(encodeAttach(100, 30, sessionId))));

let drawn = "";
while (!drawn.includes("ask>")) {{
  const f = await nextFrame();
  if (f.channel !== 1 || f.kind !== RelayKind.DATA) continue;
  const msg = channel.receive(f.body);
  if (msg.type === "output") drawn += new TextDecoder().decode(msg.bytes);
}}

ws.send(encodeRelayFrame(RelayKind.DATA, 1, channel.send(encodeInput(new TextEncoder().encode("remote-e2e-ok")))));
await new Promise((r) => setTimeout(r, 400));
ws.close();
console.log(JSON.stringify({{ ok: true, sessionId, folders: plainList.folders }}));
""")

    js_out = subprocess.check_output(["node", js_driver], text=True, timeout=30).strip()
    parsed = json.loads(js_out.splitlines()[-1])
    check("JS controller verified signed shell, decrypted SealedList, attached over Noise IK and received ask>", parsed["ok"], js_out)

    terminal.until(lambda: "remote-e2e-ok" in terminal.text())
    check("remote typing over WebSocket -> GatewayServer -> Noise XX -> Node -> PTY reached ask's live screen",
          "remote-e2e-ok" in terminal.text())

    # 4. Revoke controller live (`ask gateway untrust`) and verify immediate refusal on a new channel
    run_cli(node_env, "gateway", "untrust", ctrl_pub_b64)
    js_revoke = os.path.join(root, "revoke.mjs")
    with open(js_revoke, "w") as f:
        f.write(f"""
import {{
  importX25519PrivateSeed, ControllerChannel, encodeRelayFrame, parseRelayFrame,
  parseListsBody, RelayKind
}} from {json.dumps(REPO + "/GatewayShell/crypto.mjs")};

const id = await importX25519PrivateSeed(new Uint8Array(32).fill(0x5a));
const ws = new WebSocket("ws://127.0.0.1:{controllers_port}/socket");
ws.binaryType = "arraybuffer";
const queue = [];
let waiter = null;
ws.onmessage = (ev) => {{
  const frame = parseRelayFrame(new Uint8Array(ev.data));
  if (waiter) {{ const w = waiter; waiter = null; w(frame); }} else queue.push(frame);
}};
const nextFrame = () => queue.length ? Promise.resolve(queue.shift()) : new Promise((r) => {{ waiter = r; }});
await new Promise((res, rej) => {{ ws.onopen = res; ws.onerror = rej; }});
ws.send(encodeRelayFrame(RelayKind.HELLO, 0, new Uint8Array([0, 1, 2])));
const lists = await nextFrame();
const nodeKey = parseListsBody(lists.body)[0].nodeKey;
const {{ first }} = await ControllerChannel.open(id, nodeKey);
const openBody = new Uint8Array(32 + first.length);
openBody.set(nodeKey, 0);
openBody.set(first, 32);
ws.send(encodeRelayFrame(RelayKind.OPEN, 3, openBody));
let reply;
while (true) {{
  reply = await nextFrame();
  if (reply.channel === 3) break;
}}
ws.close();
console.log(JSON.stringify({{ kind: reply.kind, reason: reply.body[0] }}));
""")
    rev_out = json.loads(subprocess.check_output(["node", js_revoke], text=True, timeout=15).strip())
    check("revoked controller (`ask gateway untrust`) is refused immediately with CLOSE reason 1",
          rev_out["kind"] == 0x12 and rev_out["reason"] == 1, rev_out)

    node_audit = open(node_home + "/state/ask/security-audit.jsonl").read()
    gw_audit = open(gw_home + "/state/ask/security-audit.jsonl").read()
    check("node security audit log records trust, remote attach, refusal and viewer",
          '"gateway.trust"' in node_audit and '"gateway.remote"' in node_audit and '"gateway.viewer"' in node_audit, node_audit)
    check("gateway security audit log records shell signing, enroll, and accepted node",
          '"gateway.shell"' in gw_audit and '"gateway.enroll"' in gw_audit and '"gateway.node"' in gw_audit, gw_audit)
    print("PROBE PASS")
finally:
    if terminal is not None:
        terminal.close()
    for p in procs:
        p.terminate()
        try:
            p.wait(timeout=3)
        except Exception:
            p.kill()
    shutil.rmtree(root, ignore_errors=True)
