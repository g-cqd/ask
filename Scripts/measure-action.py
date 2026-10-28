#!/usr/bin/env python3
"""The action-to-action budget's real action (roadmap 0007): the model asks for a tool, ask runs it, and the result
is on screen and the next request is on its way.

Usage: Scripts/measure-action.py .build/release/ask [runs] [history-turns] [narrow|warm]

One process, one clock. A fake Anthropic server answers with a tool call and notes when it finished sending; a PTY
reader notes when the frame showing the tool's ✓ is drawn; the server notes when the next request arrives. Measured:

  shown: last byte of the tool-call response  ->  the frame showing the tool finished
  next:  last byte of the tool-call response  ->  the next request received

for `read` of a small file (in-process: ask's own work) and for `bash echo` (adds the sandboxed spawn). Isolated
configuration and state, no credentials. With history-turns, every run resumes a session of that many turns.
With narrow, the model first narrows the session to network none; timing starts at the subsequent tool response.
With warm, a distinct read runs first instead, for a matched warm-transport control without session narrowing.
"""
import fcntl
import json
import os
import pty
import struct
import termios
import select
import statistics
import sys
import tempfile
import threading
import time
import importlib.util
import math
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("agent_probe", os.path.join(here, "probe-agent-run.py"))
agent = importlib.util.module_from_spec(spec)
sys.argv, saved = [sys.argv[0]], sys.argv
spec.loader.exec_module(agent)
sys.argv = saved
BINARY = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".build/release/ask")
RUNS = int(sys.argv[2]) if len(sys.argv) > 2 else 15
HISTORY = int(sys.argv[3]) if len(sys.argv) > 3 else 0
NARROW = len(sys.argv) > 4 and sys.argv[4] == "narrow"
WARM = len(sys.argv) > 4 and sys.argv[4] == "warm"
FRAME_END = b"\x1b[?2026l"


class TimedServer:
    """Answers with the scripted turns and records, by monotonic clock, when each response was fully sent and when
    each request arrived."""

    def __init__(self, responses):
        self.responses, self.sent, self.arrived = list(responses), [], []
        outer = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, *args):
                pass

            def do_POST(self):
                self.rfile.read(int(self.headers["content-length"]))
                outer.arrived.append(time.monotonic())
                payload = outer.responses.pop(0) if outer.responses else agent.turn([("text", "done")], "end_turn")
                self.send_response(200)
                self.send_header("content-type", "text/event-stream")
                self.send_header("content-length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
                self.wfile.flush()
                outer.sent.append(time.monotonic())

        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.url = f"http://127.0.0.1:{self.httpd.server_address[1]}"


def history_file(state, project, turns):
    """A session of `turns` exchanges in the project's session directory, for resuming."""
    directory = os.path.join(state, "ask", "sessions", project.replace("/", "-").lstrip("-"))
    os.makedirs(directory, exist_ok=True)
    path = os.path.join(directory, "history.jsonl")
    with open(path, "w") as archive:
        archive.write('{"type":"session","version":1}\n')
        for index in range(turns * 2):
            record = {"type": "entry", "id": str(index), "payload": {
                "kind": "user" if index % 2 == 0 else "assistant",
                "text": ("Step " if index % 2 == 0 else "Reply ") + str(index) + ", a sentence of ordinary length."}}
            if index:
                record["parent"] = str(index - 1)
            archive.write(json.dumps(record, separators=(",", ":")) + "\n")
    return path


def one_run(tool):
    project, state = tempfile.mkdtemp(), tempfile.mkdtemp()
    open(os.path.join(project, "note.txt"), "w").write("a small file\n")
    call = ("call", "t1", "read", {"path": "note.txt"}) if tool == "read" else ("tool", "t1", "echo ok")
    responses = [agent.turn([call], "tool_use"), agent.turn([("text", "Finished.")], "end_turn")]
    offset = int(NARROW or WARM)
    if NARROW:
        responses.insert(0, agent.turn([("call", "n", "narrow_sandbox", {"sandbox": {"network": "none"}})], "tool_use"))
    elif WARM:
        open(os.path.join(project, "warm.txt"), "w").write("warm transport\n")
        responses.insert(0, agent.turn([("call", "warm", "read", {"path": "warm.txt"})], "tool_use"))
    server = TimedServer(responses)
    arguments = [BINARY]
    if HISTORY:
        arguments += ["--resume", history_file(state, os.path.realpath(project), HISTORY)]
    pid, fd = pty.fork()
    if pid == 0:
        # The size is set before exec: ask reads it at once, and setting it from the parent races that read.
        fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))  # the size the probe emulator models
        os.chdir(project)
        os.execve(BINARY, arguments, agent.environment(state, server.url))
    screen = b""
    mark = ("read · note.txt" if tool == "read" else "echo ok").encode()
    shown = None
    try:
        deadline = time.monotonic() + 15
        while "────".encode() not in screen and time.monotonic() < deadline:
            if select.select([fd], [], [], 0.05)[0]:
                screen += os.read(fd, 65536)
        os.write(fd, b"Go\r")
        emulator = agent_screen()
        emulator.feed(screen)
        tail = b""
        while time.monotonic() < deadline:
            if select.select([fd], [], [], 0.01)[0]:
                chunk = os.read(fd, 65536)
                now = time.monotonic()
                emulator.feed(chunk)
                tail = (tail + chunk)[-64:]
                if tail.endswith(FRAME_END) and any(mark.decode() in row and "✓" in row for row in emulator.text().splitlines()):
                    shown = now
                    break
        while len(server.arrived) < offset + 2 and time.monotonic() < deadline:
            time.sleep(0.005)
        if shown is None or len(server.sent) < offset + 1 or len(server.arrived) < offset + 2:
            return None
        return (shown - server.sent[offset]) * 1000, (server.arrived[offset + 1] - server.sent[offset]) * 1000
    finally:
        try:
            os.write(fd, b"\x03")
        except OSError:
            pass
        os.close(fd)
        os.waitpid(pid, 0)
        server.httpd.shutdown()


def agent_screen():
    spec = importlib.util.spec_from_file_location("interactive_probe", os.path.join(here, "probe-interactive.py"))
    module = importlib.util.module_from_spec(spec)
    sys.argv, saved = [sys.argv[0], BINARY], sys.argv
    spec.loader.exec_module(module)
    sys.argv = saved
    return module.Emulator()


def summary(values):
    values = sorted(values)
    quartiles = statistics.quantiles(values, n=4)
    return f"p50 {statistics.median(values):7.2f} ms  [p25 {quartiles[0]:.2f} – p75 {quartiles[2]:.2f}]  p95 {values[math.ceil(len(values) * 0.95) - 1]:.2f}"


if __name__ == "__main__":
    mode = "narrowed" if NARROW else "warm control" if WARM else "unchanged"
    print(f"ask — the action: a tool call to its result on screen and the next request; {RUNS} runs, history {HISTORY} turns, session {mode}")
    for tool in ("read", "bash"):
        results = [r for r in (one_run(tool) for _ in range(RUNS)) if r]
        if len(results) < max(4, RUNS // 2):
            print(f"  {tool}: only {len(results)} of {RUNS} runs completed")
            continue
        print(f"  {tool:4}  shown  {summary([r[0] for r in results])}")
        print(f"  {tool:4}  next   {summary([r[1] for r in results])}")
