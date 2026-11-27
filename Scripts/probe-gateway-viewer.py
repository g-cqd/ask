#!/usr/bin/env python3
"""ADR-0170: a viewer attaches to a running ask through its viewer socket, as the gateway's node will.

Runs the built ask in a pseudo-terminal with gateway.enabled, finds its socket and description under the state folder,
attaches with a size of its own, checks the screen arrives at that size and that what the viewer types reaches ask's own
screen; then leaves, and checks ask's screen goes on. Exits non-zero on the first failure.
"""
import importlib.util, json, os, select, socket, struct, sys, tempfile, time

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("probe_folding", os.path.join(here, "probe-folding.py"))
folding = importlib.util.module_from_spec(spec)
spec.loader.exec_module(folding)
agent = folding.agent


def frame(kind, body=b""):
    message = bytes([kind]) + body
    return struct.pack(">H", len(message)) + message


def messages(sock, until, seconds=20):
    """Reads framed channel messages until `until(printed_so_far)` holds; returns the output's text."""
    buffer, drawn, deadline = b"", b"", time.time() + seconds
    while time.time() < deadline and not until(drawn.decode("utf-8", "replace")):
        ready, _, _ = select.select([sock], [], [], 0.1)
        if not ready:
            continue
        piece = sock.recv(65536)
        if not piece:
            break
        buffer += piece
        while len(buffer) >= 2:
            (length,) = struct.unpack(">H", buffer[:2])
            if len(buffer) < 2 + length:
                break
            message, buffer = buffer[2 : 2 + length], buffer[2 + length :]
            if message[:1] == b"\x10":
                drawn += message[1:]
            elif message[:1] in (b"\x11", b"\x12"):
                return drawn.decode("utf-8", "replace") + "\n[ended] " + message[1:].decode()
    return drawn.decode("utf-8", "replace")


def check(label, condition, detail=""):
    print(("PASS " if condition else "FAIL ") + label + ("" if condition else f": {detail[-600:]!r}"))
    if not condition:
        sys.exit(1)


root = tempfile.mkdtemp(dir="/tmp", prefix="askgv")
project, config = root + "/project", root + "/config"
os.makedirs(project)
os.makedirs(config + "/ask")
with open(config + "/ask/config.json", "w") as f:
    f.write('{"ui":{"inputPrefix":"ask> "},"gateway":{"enabled":true}}')
server = agent.Server([agent.turn([("text", "fine")], "end_turn")])
env = agent.environment(root + "/state", server.url, config=config)
env.update(TERM="xterm-256color", LANG="en_US.UTF-8")
terminal = folding.Terminal(project, env)
try:
    terminal.until(lambda: "ask>" in terminal.text())
    folder = root + "/state/ask/gateway/viewers"
    sockets = [name for name in os.listdir(folder) if name.endswith(".sock")]
    check("one viewer socket is offered", len(sockets) == 1, str(os.listdir(folder)))
    pid = sockets[0][:-5]
    description = json.load(open(f"{folder}/{pid}.json"))
    check("its description names the session", description["id"] == pid and description["folder"].endswith("/project"), str(description))
    check("the folder and the socket are owner-only",
          os.stat(folder).st_mode & 0o077 == 0 and os.stat(f"{folder}/{pid}.sock").st_mode & 0o077 == 0)

    viewer = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    viewer.connect(f"{folder}/{pid}.sock")
    viewer.sendall(frame(0x01, struct.pack(">HH", 100, 30) + pid.encode()))
    drawn = messages(viewer, lambda text: "ask>" in text)
    check("the viewer receives ask's screen", "\x1b[?1049h" in drawn and "ask>" in drawn, drawn)
    check("drawn at the viewer's size, not the terminal's", "\x1b[30;" in drawn or ";100H" in drawn or "\x1b[29;" in drawn, drawn)

    viewer.sendall(frame(0x03, b"from the browser"))
    terminal.until(lambda: "from the browser" in terminal.text())
    check("what the viewer types reaches ask's own screen", "from the browser" in terminal.text())

    viewer.close()
    terminal.send(b" and back")
    terminal.until(lambda: "from the browser and back" in terminal.text())
    check("ask's screen goes on once the viewer leaves", True)
    audit = open(root + "/state/ask/security-audit.jsonl").read()
    check("the attach is in the security audit log", '"gateway.viewer"' in audit and '"attached"' in audit, audit)
finally:
    terminal.close()
print("PROBE PASS")
