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


def turn(blocks, stop, input_tokens=1):
    events = [{"type": "message_start", "message": {"id": "m", "model": "fake", "usage": {"input_tokens": input_tokens, "output_tokens": 1}}}]
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


def entry_kinds(path):
    return [json.loads(l)["payload"]["kind"] for l in open(path) if '"type":"entry"' in l]


def probe_resume():
    print("C: resume, and one writer per session")
    project, state = tempfile.mkdtemp(), tempfile.mkdtemp()
    server = Server([turn([("text", "First answer.")], "end_turn"), turn([("text", "Second answer.")], "end_turn")])
    env = environment(state, server.url)

    def ask(*arguments):
        return subprocess.run([ASK, *arguments], cwd=project, env=env, capture_output=True, text=True, timeout=60)

    first = ask("-p", "Remember the word KIWI.")
    second = ask("-p", "What was the word?", "--continue")
    files = sessions(state)
    results = [check("first run exits 0", first.returncode == 0, first.stderr),
               check("continued run exits 0", second.returncode == 0, second.stderr),
               check("continued answer on stdout", second.stdout == "Second answer.\n", repr(second.stdout)),
               check("still one session file", len(files) == 1, files)]
    if len(server.requests) >= 2:
        texts = [b.get("text", "") for m in server.requests[1]["body"]["messages"] for b in m["content"]]
        results.append(check("the earlier exchange is sent again",
                             any("KIWI" in t for t in texts) and "First answer." in texts, texts))
    if len(files) != 1:
        server.httpd.shutdown()
        return False
    session = files[0]
    results.append(check("both runs recorded in it", entry_kinds(session) == ["user", "response"] * 2,
                         entry_kinds(session)))
    listing = ask("sessions")
    results.append(check("ask sessions lists it with its first prompt",
                         listing.returncode == 0 and os.path.basename(session) in listing.stdout
                         and "Remember the word KIWI." in listing.stdout, listing.stdout + listing.stderr))
    # Another process holds the session: a continued run must refuse, not write beside it.
    holder = subprocess.Popen([sys.executable, "-c", "import fcntl, os, sys, time\n"
                               "fd = os.open(sys.argv[1], os.O_RDONLY); fcntl.flock(fd, fcntl.LOCK_EX)\n"
                               "print('held', flush=True); time.sleep(60)", session],
                              stdout=subprocess.PIPE, text=True)
    holder.stdout.readline()
    before = open(session, "rb").read()
    refused = ask("-p", "Again.", "--continue")
    holder.kill()
    holder.wait()
    results += [check("refused while another process holds it", refused.returncode == 75
                      and "open in another ask" in refused.stderr, f"{refused.returncode} {refused.stderr}"),
                check("the held session is untouched", open(session, "rb").read() == before),
                check("no session was started instead", len(sessions(state)) == 1, sessions(state))]
    named = ask("-p", "By name.", "--resume", os.path.basename(session)[:12])
    results.append(check("--resume finds it by a name prefix", named.returncode == 0
                         and entry_kinds(session) == ["user", "response"] * 3, f"{named.stderr} {entry_kinds(session)}"))
    server.httpd.shutdown()
    return all(results)


def probe_crash_resume():
    print("D: --continue after ask was killed mid-command")
    project, state = tempfile.mkdtemp(), tempfile.mkdtemp()
    server = Server([turn([("tool", "t1", "sleep 300 & echo $! > child.pid; wait")], "tool_use"),
                     turn([("text", "Recovered.")], "end_turn")])
    env = environment(state, server.url)
    process = subprocess.Popen([ASK, "-p", "Run it"], cwd=project, env=env,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    pid_file = os.path.join(project, "child.pid")
    deadline = time.time() + 15
    while not os.path.exists(pid_file) and time.time() < deadline:
        time.sleep(0.02)
    process.kill()
    process.communicate(timeout=15)
    try:
        os.kill(int(open(pid_file).read()), signal.SIGKILL)  # SIGKILL gives ask no chance to stop its children.
    except (OSError, ValueError):
        pass
    files = sessions(state)
    results = [check("killed with the call unanswered", len(files) == 1 and entry_kinds(files[0]) == ["user", "response"],
                     files and entry_kinds(files[0]))]
    resumed = subprocess.run([ASK, "-p", "Go on.", "--continue"], cwd=project, env=env,
                             capture_output=True, text=True, timeout=60)
    results.append(check("the continued run exits 0", resumed.returncode == 0, resumed.stderr))
    results.append(check("and answers", resumed.stdout == "Recovered.\n", repr(resumed.stdout)))
    if check("two requests", len(server.requests) == 2, len(server.requests)):
        blocks = [b for m in server.requests[1]["body"]["messages"] for b in m["content"]]
        answered = [b for b in blocks if b["type"] == "tool_result" and b["tool_use_id"] == "t1"]
        results.append(check("the unanswered call is answered as interrupted",
                             len(answered) == 1 and answered[0].get("is_error") and "interrupted" in answered[0]["content"],
                             answered))
    server.httpd.shutdown()
    return all(results)


def probe_compaction():
    print("E: a context past the default threshold is compacted before the next request")
    project, state = tempfile.mkdtemp(), tempfile.mkdtemp()
    server = Server([turn([("text", "Noted.")], "end_turn", input_tokens=200_000),
                     turn([("text", "SUMMARY: the vault code is HERON-4412.")], "end_turn"),
                     turn([("text", "Done.")], "end_turn")])
    env = environment(state, server.url)

    def ask(*arguments):
        return subprocess.run([ASK, *arguments], cwd=project, env=env, capture_output=True, text=True, timeout=60)

    first = ask("-p", "The vault code is HERON-4412.")
    # Larger than the 80 KB kept tail, so the tail starts at this prompt and everything before it is summarised.
    second = ask("-p", "Background notes: " + "lorem ipsum " * 7_500 + "Now say Done.", "--continue")
    results = [check("both runs exit 0", first.returncode == 0 and second.returncode == 0, first.stderr + second.stderr),
               check("compaction reported", "Compacted the conversation" in second.stderr, second.stderr[-400:]),
               check("answer on stdout", second.stdout == "Done.\n", repr(second.stdout)),
               check("three requests", len(server.requests) == 3, len(server.requests))]
    if len(server.requests) == 3:
        def texts(index):
            return [b.get("text", "") for m in server.requests[index]["body"]["messages"] for b in m["content"]]
        results.append(check("the summary request carries the old context and asks for a summary",
                             any("HERON-4412" in t for t in texts(1)) and "compacted" in texts(1)[-1], texts(1)[-1][:80]))
        # ask's own prompt leads the first user message (ADR-0007); the summary follows it, before the kept tail.
        summary = "Summary of the conversation so far:\nSUMMARY: the vault code is HERON-4412."
        later = texts(2)
        kept = next((i for i, t in enumerate(later) if t.startswith("Background notes:")), -1)
        results.append(check("the next request carries the summary before the kept tail",
                             summary in later and later.index(summary) < kept, [t[:40] for t in later]))
        results.append(check("and no longer carries what it summarised",
                             not any(t == "The vault code is HERON-4412." for t in texts(2)), texts(2)[:3]))
    files = sessions(state)
    if check("one session file", len(files) == 1, files):
        kinds = entry_kinds(files[0])
        results.append(check("the full history is kept, with the compaction in it",
                             kinds == ["user", "response", "user", "compaction", "response"], kinds))
    server.httpd.shutdown()
    return all(results)


if __name__ == "__main__":
    ok = probe_round_trip() & probe_interrupt() & probe_resume() & probe_crash_resume() & probe_compaction()
    print("PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)
