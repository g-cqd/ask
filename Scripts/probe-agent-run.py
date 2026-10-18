#!/usr/bin/env python3
"""End-to-end probe of `ask -p` against a local fake Anthropic server, with no network and no credentials.

A: a tool round trip. The model calls bash, the result reaches the second request, the answer reaches stdout,
   and the session records user, response, tool result, response.
B: SIGINT while a command runs. ask exits 130, and the command's backgrounded child dies with it.

Usage: Scripts/probe-agent-run.py .build/release/ask
"""
import json, os, signal, subprocess, sys, tempfile, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ASK = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".build/release/ask")
CANONICAL = "You are a Claude agent, built on Anthropic's Claude Agent SDK."


def sse(events):
    return "".join(f"event: {e['type']}\ndata: {json.dumps(e)}\n\n" for e in events).encode()


def turn(blocks, stop):
    events = [{"type": "message_start", "message": {"id": "m", "model": "fake", "usage": {"input_tokens": 1, "output_tokens": 1}}}]
    for i, block in enumerate(blocks):
        if block[0] == "text":
            events += [{"type": "content_block_start", "index": i, "content_block": {"type": "text", "text": ""}},
                       {"type": "content_block_delta", "index": i, "delta": {"type": "text_delta", "text": block[1]}}]
        else:
            events += [{"type": "content_block_start", "index": i, "content_block": {"type": "tool_use", "id": block[1], "name": "bash", "input": {}}},
                       {"type": "content_block_delta", "index": i, "delta": {"type": "input_json_delta", "partial_json": json.dumps({"command": block[2]})}}]
        events.append({"type": "content_block_stop", "index": i})
    events += [{"type": "message_delta", "delta": {"stop_reason": stop}, "usage": {"output_tokens": 5}},
               {"type": "message_stop"}]
    return sse(events)


class Server:
    def __init__(self, responses):
        self.responses, self.requests = list(responses), []
        outer = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["content-length"])))
                outer.requests.append({"body": body, "headers": {k.lower(): v for k, v in self.headers.items()}})
                payload = outer.responses.pop(0) if outer.responses else turn([("text", "out of script")], "end_turn")
                self.send_response(200)
                self.send_header("content-type", "text/event-stream")
                self.end_headers()
                self.wfile.write(payload)

        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.url = f"http://127.0.0.1:{self.httpd.server_address[1]}"


def environment(state, url):
    env = dict(os.environ, ANTHROPIC_API_KEY="sk-ant-api-fake", ANTHROPIC_BASE_URL=url, XDG_STATE_HOME=state)
    env.pop("XDG_CONFIG_HOME", None)
    return env


def sessions(state):
    found = []
    for root, _, files in os.walk(state):
        found += [os.path.join(root, f) for f in files if f.endswith(".jsonl")]
    return found


def check(label, condition, detail=""):
    print(f"  {'ok  ' if condition else 'FAIL'} {label}" + (f": {detail}" if detail and not condition else ""))
    return condition


def probe_round_trip():
    print("A: tool round trip")
    project, state = tempfile.mkdtemp(), tempfile.mkdtemp()
    server = Server([turn([("tool", "t1", "echo probe-ok > out.txt && cat out.txt")], "tool_use"),
                     turn([("text", "Done.")], "end_turn")])
    run = subprocess.run([ASK, "-p", "Write out.txt"], cwd=project, env=environment(state, server.url),
                         capture_output=True, text=True, timeout=60)
    results = [run.returncode == 0,
               check("exit 0", run.returncode == 0, run.stderr),
               check("answer on stdout", run.stdout == "Done.\n", repr(run.stdout)),
               check("tool shown on stderr", "▸ bash" in run.stderr, run.stderr),
               check("file written", open(os.path.join(project, "out.txt")).read() == "probe-ok\n"),
               check("two requests", len(server.requests) == 2, len(server.requests))]
    if len(server.requests) == 2:
        first, second = server.requests[0]["body"], server.requests[1]["body"]
        results.append(check("system is the canonical line", first["system"] == [{"type": "text", "text": CANONICAL}], first["system"]))
        results.append(check("prompt leads the first user message", "You are ask" in first["messages"][0]["content"][0]["text"]))
        results.append(check("tools offered", [t["name"] for t in first["tools"]] == ["read", "write", "edit", "bash"]))
        last = second["messages"][-1]["content"][0]
        results.append(check("tool result sent back", last["type"] == "tool_result" and "probe-ok" in last["content"], last))
        results.append(check("user-agent is ask", server.requests[0]["headers"].get("user-agent") == "ask"))
    files = sessions(state)
    if check("one session file", len(files) == 1, files):
        kinds = [json.loads(l)["payload"]["kind"] for l in open(files[0]) if '"type":"entry"' in l]
        results.append(check("session records the run", kinds == ["user", "response", "tool_result", "response"], kinds))
    server.httpd.shutdown()
    return all(results)


def probe_interrupt():
    print("B: SIGINT during a command")
    project, state = tempfile.mkdtemp(), tempfile.mkdtemp()
    server = Server([turn([("tool", "t1", "sleep 300 & echo $! > child.pid; wait")], "tool_use")])
    process = subprocess.Popen([ASK, "-p", "Run it"], cwd=project, env=environment(state, server.url),
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    pid_file, deadline = os.path.join(project, "child.pid"), time.time() + 30
    while not (os.path.exists(pid_file) and open(pid_file).read().strip()) and time.time() < deadline:
        time.sleep(0.02)
    child = int(open(pid_file).read())
    process.send_signal(signal.SIGINT)
    try:
        _, stderr = process.communicate(timeout=15)
    except subprocess.TimeoutExpired:
        process.kill()
        return check("ask exits after SIGINT", False, "still running after 15 s")
    deadline = time.time() + 5
    alive = True
    while alive and time.time() < deadline:
        try:
            os.kill(child, 0)
            time.sleep(0.02)
        except ProcessLookupError:
            alive = False
    results = [check("exit 130", process.returncode == 130, f"{process.returncode} {stderr}"),
               check("backgrounded child stopped", not alive, f"pid {child} still alive")]
    if alive:
        os.kill(child, signal.SIGKILL)
    files = sessions(state)
    if files:
        kinds = [json.loads(l)["payload"]["kind"] for l in open(files[0]) if '"type":"entry"' in l]
        results.append(check("aborted result recorded", kinds == ["user", "response", "tool_result"], kinds))
    server.httpd.shutdown()
    return all(results)


if __name__ == "__main__":
    ok = probe_round_trip() & probe_interrupt()
    print("PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)
