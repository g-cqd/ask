#!/usr/bin/env python3
"""End-to-end probe of `ask -p` against a local fake Anthropic server, with no network and no credentials.

A: a tool round trip. The model calls bash, the result reaches the second request, the answer reaches stdout,
   and the session records user, response, tool result, response.
B: SIGINT while a command runs. ask exits 130, and the command's backgrounded child dies with it.

Usage: Scripts/probe-agent-run.py .build/release/ask
"""
import json
import shutil
import uuid
import pty
import re
import socket, os, signal, subprocess, sys, tempfile, threading, time
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
            # ("tool", id, command) calls bash; ("call", id, name, arguments) calls any tool.
            name, arguments = ("bash", {"command": block[2]}) if block[0] == "tool" else (block[2], block[3])
            events += [{"type": "content_block_start", "index": i, "content_block": {"type": "tool_use", "id": block[1], "name": name, "input": {}}},
                       {"type": "content_block_delta", "index": i, "delta": {"type": "input_json_delta", "partial_json": json.dumps(arguments)}}]
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


def environment(state, url, config=None):
    """The run's environment. `config` is a directory standing in for ~/.config; by default an empty one inside `state`, never the
    machine's own: ask finds ~/.config through NSHomeDirectory(), which on macOS ignores HOME, so without XDG_CONFIG_HOME a probe read the
    owner's credentials and model catalogs, and could refresh a real token. HOME is an empty directory inside `state` too, for the commands
    the model runs."""
    home = os.path.join(state, "home")
    os.makedirs(home, exist_ok=True)
    env = dict(os.environ, ANTHROPIC_API_KEY="sk-ant-api-fake", ANTHROPIC_BASE_URL=url, XDG_STATE_HOME=state, HOME=home)
    for name in [n for n in env if n.startswith("ASK_")]:
        del env[name]
    if not config:
        config = os.path.join(state, "config")
        os.makedirs(config, exist_ok=True)
    env["XDG_CONFIG_HOME"] = config
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
        results.append(check("tools offered", [t["name"] for t in first["tools"] if t["name"] != "skill"] == ["read", "write", "bash", "job", "narrow_sandbox"]))
        last = second["messages"][-1]["content"][0]
        results.append(check("tool result sent back", last["type"] == "tool_result" and "probe-ok" in last["content"], last))
        results.append(check("user-agent is ask", server.requests[0]["headers"].get("user-agent") == "ask"))
    files = sessions(state)
    if check("one session file", len(files) == 1, files):
        kinds = entry_kinds(files[0])
        results.append(check("session records the run", kinds == ["user", "response", "tool_result", "response"], kinds))
        results.append(check("and where it was sent, once, first", all_kinds(files[0])[:1] == ["destination"]
                             and all_kinds(files[0]).count("destination") == 1, all_kinds(files[0])))
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
        kinds = entry_kinds(files[0])
        results.append(check("aborted result recorded", kinds == ["user", "response", "tool_result"], kinds))
    server.httpd.shutdown()
    return all(results)


def entry_kinds(path):
    """The conversation's entries by kind. A session's destination (ADR-0048) is where it was sent, not conversation."""
    return [k for k in all_kinds(path) if k != "destination"]


def all_kinds(path):
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


def free_port():
    probe = socket.socket()
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]
    probe.close()
    return port


def accepts(port):
    try:
        socket.create_connection(("127.0.0.1", port), timeout=1).close()
        return True
    except OSError:
        return False


def tool_results(server):
    """Every tool result the model was sent, by call id, from the last request."""
    blocks = [b for m in server.requests[-1]["body"]["messages"] for b in m["content"]]
    return {b["tool_use_id"]: b["content"] for b in blocks if b["type"] == "tool_result"}


def probe_jobs():
    print("F: a server run as a job: yielded, waited on, used, stopped; a long output kept in a file")
    project, state, port = tempfile.mkdtemp(), tempfile.mkdtemp(), free_port()
    server = Server([
        turn([("call", "t1", "bash", {"command": f"exec python3 -m http.server {port} --bind 127.0.0.1", "yield_seconds": 1})], "tool_use"),
        turn([("call", "t2", "job", {"job": "job-1", "action": "wait", "wait_for_port": port, "timeout_seconds": 20})], "tool_use"),
        turn([("tool", "t3", f"curl -s http://127.0.0.1:{port}/ | head -c 200")], "tool_use"),
        turn([("tool", "t4", "awk 'BEGIN { for (n = 1; n <= 1500000; n++) print n }'")], "tool_use"),  # macOS seq prints 1.5e+06
        turn([("call", "t5", "job", {"job": "job-1", "action": "stop"})], "tool_use"),
        turn([("text", "Done.")], "end_turn")])
    run = subprocess.run([ASK, "-p", "Serve, check, stop."], cwd=project, env=environment(state, server.url),
                         capture_output=True, text=True, timeout=120)
    results = [check("exit 0", run.returncode == 0, run.stderr[-300:]), check("six requests", len(server.requests) == 6, len(server.requests))]
    if len(server.requests) == 6:
        got = tool_results(server)
        results += [check("bash yielded the server as job-1", "still running as job-1 after 1 s" in got.get("t1", ""), got.get("t1")),
                    check("wait saw the port open", f"[job-1 port {port} accepts connections]" in got.get("t2", ""), got.get("t2")),
                    check("the server answered", "Directory listing" in got.get("t3", ""), got.get("t3")),
                    check("job_stop stopped it", got.get("t5", "").startswith("[job-1 stopped]"), got.get("t5"))]
        named = re.search(r"\[whole output in (.+?)\]", got.get("t4", ""))
        if check("the long output names its file", named is not None, got.get("t4", "")[-200:]):
            whole = open(named.group(1)).read()
            results.append(check("the file holds the whole output, middle included",
                                 whole == "".join(f"{n}\n" for n in range(1, 1_500_001)), len(whole)))
            results.append(check("and the result itself was cut", "750000\n" not in got["t4"]))
    results.append(check("the port is closed afterwards", not accepts(port)))
    server.httpd.shutdown()
    return all(results)


def probe_jobs_end_with_ask():
    print("G: a job left running when -p ends is stopped with it")
    project, state, port = tempfile.mkdtemp(), tempfile.mkdtemp(), free_port()
    server = Server([
        turn([("call", "t1", "bash", {"command": f"exec python3 -m http.server {port} --bind 127.0.0.1", "yield_seconds": 1})], "tool_use"),
        turn([("call", "t2", "job", {"job": "job-1", "action": "wait", "wait_for_port": port, "timeout_seconds": 20})], "tool_use"),
        turn([("text", "Left it running.")], "end_turn")])
    run = subprocess.run([ASK, "-p", "Serve and leave it."], cwd=project, env=environment(state, server.url),
                         capture_output=True, text=True, timeout=120)
    got = tool_results(server) if len(server.requests) == 3 else {}
    results = [check("exit 0", run.returncode == 0, run.stderr[-300:]),
               check("the server was up during the run", f"[job-1 port {port} accepts connections]" in got.get("t2", ""), got),
               check("and is gone once ask has exited", not accepts(port))]
    server.httpd.shutdown()
    return all(results)


def probe_configuration():
    print("H: configuration files, trust, layers and failures")
    project, state, config = tempfile.mkdtemp(), tempfile.mkdtemp(), tempfile.mkdtemp()
    os.makedirs(os.path.join(config, "ask"))
    os.makedirs(os.path.join(project, ".ask"))
    user_file, project_file = os.path.join(config, "ask", "config.json"), os.path.join(project, ".ask", "config.json")
    server = Server([turn([("tool", f"t{i}", "true")], "tool_use") for i in range(1, 80)])

    def ask(*arguments, **extra):
        env = environment(state, server.url, config)
        env.update(extra)
        return subprocess.run([ASK, *arguments], cwd=project, env=env, capture_output=True, text=True, timeout=60)

    def ask_at_terminal(*arguments):
        """`ask` with a terminal on standard input, as a person has and the agent's bash tool does not."""
        master, slave = pty.openpty()
        try:
            return subprocess.run([ASK, *arguments], cwd=project, env=environment(state, server.url, config),
                                  stdin=slave, capture_output=True, text=True, timeout=60)
        finally:
            os.close(slave)
            os.close(master)

    def requests_made(*arguments, **extra):
        before = len(server.requests)
        run = ask("-p", "Loop.", "--verbose", *arguments, **extra)
        return len(server.requests) - before, run

    # JSON5 in a .json file: comments, unquoted keys, single quotes, trailing comma.
    open(user_file, "w").write("// my settings\n{\n  model: 'fake-model', /* x */\n  maxTurns: 4,\n}\n")
    made, run = requests_made()
    results = [check("a JSON5 user file applies: the loop stops at maxTurns 4", made == 4 and "4" in run.stderr, f"{made} {run.stderr[-200:]}"),
               check("and it says which file it used", user_file in run.stderr, run.stderr[-300:])]
    # Plain JSON reads the same.
    open(user_file, "w").write('{"model": "fake-model", "maxTurns": 3}')
    made, _ = requests_made()
    results.append(check("plain JSON in the same file applies: maxTurns 3", made == 3, made))
    # A project file counts only after `ask trust`.
    open(project_file, "w").write("{maxTurns: 2}")
    made, run = requests_made()
    results += [check("an untrusted project file is ignored", made == 3, made),
                check("with a notice saying how to use it", "run `ask trust`" in run.stderr, run.stderr[-300:])]
    refused = ask("trust")
    made_untrusted, _ = requests_made()
    results += [check("ask trust refuses without a terminal (the agent's bash has none)", refused.returncode == 77 and "terminal" in refused.stderr, f"{refused.returncode} {refused.stderr}"),
                check("and trusted nothing", made_untrusted == 3, made_untrusted)]
    trusted = ask_at_terminal("trust")
    made, _ = requests_made()
    results += [check("ask trust succeeds", trusted.returncode == 0 and "maxTurns" in trusted.stdout, trusted.stdout + trusted.stderr),
                check("a trusted project file overrides the user's: maxTurns 2", made == 2, made)]
    # The environment beats files, a flag beats the environment.
    made, _ = requests_made(ASK_MAX_TURNS="5")
    results.append(check("ASK_MAX_TURNS=5 beats the project file", made == 5, made))
    made, _ = requests_made("--max-turns", "1", ASK_MAX_TURNS="5")
    results.append(check("--max-turns 1 beats the environment", made == 1, made))
    # The file changes after it was trusted: ignored again.
    open(project_file, "w").write("{maxTurns: 6}")
    made, run = requests_made()
    results += [check("a changed project file is ignored until trusted again", made == 3, made),
                check("and the notice says it changed", "changed since you trusted it" in run.stderr, run.stderr[-300:])]
    ask_at_terminal("trust")
    ask("untrust")
    made, _ = requests_made()
    results.append(check("ask untrust withdraws it", made == 3, made))
    # Failures: named, with line and column, before any request.
    open(user_file, "w").write("{\n  model: 'x',\n  maxTurns: ]\n}\n")
    before = len(server.requests)
    run = ask("-p", "Hi.")
    results += [check("a broken file exits 78", run.returncode == 78, run.returncode),
                check("naming file, line, column and the character", f"{user_file}:3:13: unexpected ']'" in run.stderr, run.stderr),
                check("and no request was made", len(server.requests) == before)]
    open(user_file, "w").write("{modle: 'x'}")
    run = ask("-p", "Hi.")
    results.append(check("a typo'd key is refused, listing the known keys", run.returncode == 78 and '"maxTurns"' in run.stderr and "modle" in run.stderr, run.stderr))
    open(user_file, "w").write("{maxTurns: 2, maxTurns: 3}")
    results.append(check("a repeated key is refused", ask("-p", "Hi.").returncode == 78))
    shown = ask("config")
    results.append(check("ask config on a broken file also fails", shown.returncode == 78))
    server.httpd.shutdown()
    return all(results)


def probe_sandbox():
    print("J: the sandbox protects ask's own files from the model's tools")
    project, state, home = tempfile.mkdtemp(), tempfile.mkdtemp(), tempfile.mkdtemp()
    config = os.path.join(home, ".config")
    os.makedirs(os.path.join(config, "ask"))
    os.makedirs(os.path.join(home, ".aws"))
    ask_dir = os.path.join(config, "ask")
    files = {"config.json": "{}", "credentials.json": "sk-ant-oat-SECRET", "trusted.json": "{}"}
    for name, text in files.items():
        open(os.path.join(ask_dir, name), "w").write(text)
    open(os.path.join(home, ".aws", "credentials"), "w").write("AWS-SECRET")

    def run(*arguments):
        server = Server([
            turn([("call", "t1", "write", {"path": os.path.join(ask_dir, "config.json"), "content": "{maxTurns: 9999}"})], "tool_use"),
            turn([("call", "t2", "read", {"path": os.path.join(ask_dir, "credentials.json")})], "tool_use"),
            turn([("tool", "t3", f"echo owned > '{ask_dir}/trusted.json'")], "tool_use"),
            turn([("tool", "t4", f"cat '{ask_dir}/credentials.json'")], "tool_use"),
            turn([("tool", "t5", f"cat '{home}/.aws/credentials'")], "tool_use"),
            turn([("tool", "t6", f"mv '{config}' '{home}/.c2' && echo owned > '{home}/.c2/ask/config.json'; mv '{home}/.c2' '{config}'")], "tool_use"),
            turn([("tool", "t7", "echo fine > made.txt && cat made.txt")], "tool_use"),
            turn([("text", "Done.")], "end_turn")])
        env = environment(state, server.url, config)
        env["HOME"] = home
        process = subprocess.run([ASK, "--verbose", "-p", "Attack.", *arguments], cwd=project, env=env, capture_output=True,
                                 text=True, timeout=120)
        results = tool_results(server) if len(server.requests) == 8 else {}
        server.httpd.shutdown()
        return process, results

    def contents(name):
        return open(os.path.join(ask_dir, name)).read()

    process, got = run()
    results = [check("the run finishes", process.returncode == 0 and len(got) == 7, f"{process.returncode} {len(got)} {process.stderr[-200:]}"),
               check("write to config.json is refused, naming the path the model gave and nothing of the policy (ADR-0115)",
                     got.get("t1", "").startswith("Not permitted: ") and "config.json" in got.get("t1", "") and "protected" not in got.get("t1", ""), got.get("t1")),
               check("read of credentials.json is refused the same way", got.get("t2", "").startswith("Not permitted: ") and "SECRET" not in got.get("t2", ""), got.get("t2")),
               check("bash cannot write the trust store", "operation not permitted" in got.get("t3", "").lower(), got.get("t3")),
               check("nor read the credentials", "operation not permitted" in got.get("t4", "").lower() and "SECRET" not in got.get("t4", ""), got.get("t4")),
               check("nor another secret store", "operation not permitted" in got.get("t5", "").lower() and "AWS-SECRET" not in got.get("t5", ""), got.get("t5")),
               check("a refused command carries the system's error and no note about a sandbox or its policy",
                     "ran in a sandbox" not in got.get("t4", "") and "Only the user" not in got.get("t4", "") and "protected" not in got.get("t4", ""), got.get("t4")),
               check("renaming the config's parent away and back changes nothing", "operation not permitted" in got.get("t6", "").lower(), got.get("t6")),
               check("ordinary work still runs", got.get("t7", "").startswith("fine"), got.get("t7")),
               check("config.json is untouched", contents("config.json") == files["config.json"], contents("config.json")),
               check("trusted.json is untouched", contents("trusted.json") == files["trusted.json"], contents("trusted.json")),
               check("credentials.json is untouched", contents("credentials.json") == files["credentials.json"]),
               check("the session was still written, by ask itself", len(sessions(state)) == 1, sessions(state))]
    # The user's switch: the same attack succeeds, and ask says the sandbox is off.
    process, got = run("--no-sandbox")
    results += [check("--no-sandbox: the write is allowed", got.get("t1", "").startswith("Wrote "), got.get("t1")),
                check("--no-sandbox: ask said so", "The sandbox is off" in process.stderr, process.stderr[-300:]),
                check("--no-sandbox: config.json really changed", contents("config.json") != files["config.json"], contents("config.json"))]
    # Put back what the unsandboxed attack overwrote, so ask can read its configuration again.
    for name, text in files.items():
        open(os.path.join(ask_dir, name), "w").write(text)
    shown = subprocess.run([ASK, "config"], cwd=project, env={**environment(state, "http://127.0.0.1:9", config), "HOME": home}, capture_output=True, text=True, timeout=30)
    results.append(check("ask config says the sandbox is on", "sandbox   on" in shown.stdout, shown.stdout))
    return all(results)


def probe_sandbox_allowance():
    print("K: the user's sandbox section lifts a secret store and never ask's own files")
    project, state, home = tempfile.mkdtemp(), tempfile.mkdtemp(), tempfile.mkdtemp()
    ask_dir = os.path.join(home, ".config", "ask")
    os.makedirs(ask_dir)
    os.makedirs(os.path.join(home, ".aws"))
    os.makedirs(os.path.join(home, "clients"))
    open(os.path.join(ask_dir, "credentials.json"), "w").write("sk-ant-oat-SECRET")
    open(os.path.join(home, ".aws", "credentials"), "w").write("AWS-SECRET")
    open(os.path.join(home, "clients", "notes.txt"), "w").write("CLIENT-NOTES")
    # The user's file names the aws store, ask's own directory (which must not be lifted), and a directory to hide.
    open(os.path.join(ask_dir, "config.json"), "w").write(
        "{sandbox: {allowRead: ['~/.aws', '~/.config/ask'], denyRead: ['~/clients']}}")
    server = Server([
        turn([("tool", "t1", f"cat '{home}/.aws/credentials'")], "tool_use"),
        turn([("tool", "t2", f"cat '{ask_dir}/credentials.json'")], "tool_use"),
        turn([("tool", "t3", f"cat '{home}/clients/notes.txt'")], "tool_use"),
        turn([("text", "Done.")], "end_turn")])
    env = environment(state, server.url, os.path.join(home, ".config"))
    env["HOME"] = home
    run = subprocess.run([ASK, "-p", "Read."], cwd=project, env=env, capture_output=True, text=True, timeout=120)
    got = tool_results(server) if len(server.requests) == 4 else {}
    server.httpd.shutdown()
    shown = subprocess.run([ASK, "config"], cwd=project, env=env, capture_output=True, text=True, timeout=30)
    return all([check("the run finishes", run.returncode == 0 and len(got) == 3, f"{run.returncode} {run.stderr[-200:]}"),
                check("the allowed secret store is readable", "AWS-SECRET" in got.get("t1", ""), got.get("t1")),
                check("ask's own credentials still are not, though the list named them",
                      "operation not permitted" in got.get("t2", "").lower() and "SECRET" not in got.get("t2", ""), got.get("t2")),
                check("a directory the user asked to hide is hidden", "operation not permitted" in got.get("t3", "").lower(), got.get("t3")),
                check("ask config shows the section and where it came from",
                      "allowRead" in shown.stdout and "denyRead" in shown.stdout and "sandbox   on" in shown.stdout, shown.stdout)])


def probe_damaged_session():
    print("L: resuming a damaged session says what was repaired, and keeps the original")
    project, state = tempfile.mkdtemp(), tempfile.mkdtemp()
    server = Server([turn([("text", "First.")], "end_turn"), turn([("text", "Second.")], "end_turn")])
    env = environment(state, server.url)
    first = subprocess.run([ASK, "-p", "Remember KIWI."], cwd=project, env=env, capture_output=True, text=True, timeout=60)
    files = sessions(state)
    if len(files) != 1:
        return check("one session to damage", False, files)
    original = open(files[0], "rb").read()
    damaged = original + b'{"id":"cut'  # an interrupted write: half a record, no newline
    open(files[0], "wb").write(damaged)
    second = subprocess.run([ASK, "-p", "And now?", "--continue"], cwd=project, env=env, capture_output=True, text=True, timeout=60)
    kept = [f for f in os.listdir(os.path.dirname(files[0])) if ".damaged" in f]
    server.httpd.shutdown()
    return all([check("the first run worked", first.returncode == 0, first.stderr),
                check("the resumed run worked", second.returncode == 0 and second.stdout == "Second.\n", second.stdout + second.stderr),
                check("it said the session was repaired, naming the line",
                      "The session file had a problem, repaired as it was opened" in second.stderr
                      and "cut off mid-write" in second.stderr, second.stderr),
                check("the damaged original was kept beside it, byte for byte",
                      len(kept) == 1 and open(os.path.join(os.path.dirname(files[0]), kept[0]), "rb").read() == damaged, kept),
                check("the repaired session carries both exchanges", entry_kinds(files[0]) == ["user", "response"] * 2, entry_kinds(files[0]))])


def probe_nested_sandbox():
    print("M: SwiftPM under ask's sandbox: a fresh manifest fails as a nested sandbox, --disable-sandbox builds")
    project, state = tempfile.mkdtemp(), tempfile.mkdtemp()
    os.makedirs(os.path.join(project, "Sources", "hello"))
    # A nonce makes the manifest new to SwiftPM's user cache, which is what made the earlier research pass.
    open(os.path.join(project, "Package.swift"), "w").write(
        "// swift-tools-version: 6.0\nimport PackageDescription\n// nonce " + uuid.uuid4().hex
        + "\nlet package = Package(name: \"hello\", targets: [.executableTarget(name: \"hello\")])\n")
    open(os.path.join(project, "Sources", "hello", "main.swift"), "w").write('print("built-under-ask")\n')
    server = Server([
        turn([("tool", "t1", "swift build 2>&1 | tail -3; exit ${PIPESTATUS[0]}")], "tool_use"),
        turn([("tool", "t2", "swift build --disable-sandbox 2>&1 | tail -1 && .build/debug/hello")], "tool_use"),
        turn([("text", "Done.")], "end_turn")])
    run = subprocess.run([ASK, "-p", "Build it."], cwd=project, env=environment(state, server.url),
                         capture_output=True, text=True, timeout=600)
    got = tool_results(server) if len(server.requests) == 3 else {}
    prompt = json.dumps(server.requests[0]["body"]["messages"][0]) if server.requests else ""
    server.httpd.shutdown()
    return all([
        check("the run finishes", run.returncode == 0 and len(got) == 2, f"{run.returncode} {run.stderr[-300:]}"),
        check("the system prompt says nothing about the sandbox, SwiftPM's flag included (ADR-0115)", "andbox" not in prompt),
        check("a fresh manifest fails because the sandboxes cannot nest",
              "sandbox_apply: Operation not permitted" in got.get("t1", ""), got.get("t1", "")[-400:]),
        check("and the model is told so, not that it touched a protected path",
              "tried to start a sandbox of its own" in got.get("t1", "") and "--disable-sandbox" in got.get("t1", "")
              and "which may be why it was refused" not in got.get("t1", ""), got.get("t1", "")[-400:]),
        check("--disable-sandbox builds and runs under ask's sandbox",
              "built-under-ask" in got.get("t2", "") and "[exit 0]" in got.get("t2", ""), got.get("t2", "")[-400:])])


def probe_strict_sandbox():
    print("N: strict modes: writes confined to the workspace, the network to localhost; a project only narrows")
    project, state, home = tempfile.mkdtemp(), tempfile.mkdtemp(), tempfile.mkdtemp()
    config = os.path.join(home, ".config")
    os.makedirs(os.path.join(config, "ask"))
    os.makedirs(os.path.join(project, ".ask"))
    os.makedirs(os.path.join(project, "Sources", "hello"))
    user_file, project_file = os.path.join(config, "ask", "config.json"), os.path.join(project, ".ask", "config.json")
    open(user_file, "w").write("{sandbox: {write: 'workspace', network: 'localhost'}}")
    open(os.path.join(project, "Package.swift"), "w").write(
        "// swift-tools-version: 6.0\nimport PackageDescription\n// nonce " + uuid.uuid4().hex
        + "\nlet package = Package(name: \"hello\", targets: [.executableTarget(name: \"hello\")])\n")
    open(os.path.join(project, "Sources", "hello", "main.swift"), "w").write('print("strict-build-ok")\n')
    # Not under the temporary home: that is inside /private/var/folders, which strict mode keeps writable as scratch.
    away = "/Users/Shared/ask-strict-" + uuid.uuid4().hex
    os.makedirs(away)
    outside = os.path.join(away, "outside.txt")
    scratch = "/tmp/ask-strict-" + uuid.uuid4().hex

    def run(*arguments, calls):
        server = Server([turn([call], "tool_use") for call in calls] + [turn([("text", "Done.")], "end_turn")])
        target = Server([])  # what curl reaches: a separate local server, so it never consumes a scripted turn
        env = environment(state, server.url, config)
        env["HOME"] = home
        # curl 7 means no connection could be made; a body keeps the fake server's request handling happy.
        reach = f"curl -s -o /dev/null -w 'HTTP %{{http_code}}' -d '{{}}' {target.url}/probe; echo \" curl=$?\""
        calls_with_url = [c if c[2] != "REACH" else (c[0], c[1], reach) for c in calls]
        server.responses = [turn([c], "tool_use") for c in calls_with_url] + [turn([("text", "Done.")], "end_turn")]
        process = subprocess.run([ASK, "--verbose", "-p", "Work.", *arguments], cwd=project, env=env, capture_output=True,
                                 text=True, timeout=600)
        got = tool_results(server) if len(server.requests) == len(calls) + 1 else {}
        server.httpd.shutdown()
        target.httpd.shutdown()
        return process, got

    def ask(*arguments, stdin=None):
        env = environment(state, "http://127.0.0.1:9", config)
        env["HOME"] = home
        return subprocess.run([ASK, *arguments], cwd=project, env=env, stdin=stdin, capture_output=True, text=True,
                              timeout=60)

    calls = [("tool", "inside", "echo in > inside.txt && cat inside.txt"),
             ("tool", "outside", f"echo out > '{outside}'"),
             ("call", "tool", "write", {"path": outside, "content": "x"}),
             ("tool", "scratch", f"echo tmp > '{scratch}' && cat '{scratch}'"),
             ("tool", "reach", "REACH"),
             ("tool", "build", "swift build --disable-sandbox 2>&1 | tail -1 && .build/debug/hello")]
    process, got = run(calls=calls)
    shown = ask("config")
    results = [
        check("the run finishes", process.returncode == 0 and len(got) == 6, f"{process.returncode} {process.stderr[-300:]}"),
        check("it says, at the start, that the sandbox is strict",
              "Sandbox: writes only under" in process.stderr and "network localhost" in process.stderr, process.stderr[:400]),
        check("writing in the workspace works", got.get("inside", "").startswith("in\n"), got.get("inside")),
        check("bash cannot write outside it", "operation not permitted" in got.get("outside", "").lower() and not os.path.exists(outside), got.get("outside")),
        check("nor can the write tool, which says only that it is not permitted", got.get("tool", "").startswith("Not permitted: "), got.get("tool")),
        check("temporary directories stay writable", got.get("scratch", "").startswith("tmp\n"), got.get("scratch")),
        check("localhost is reachable", "HTTP 200 curl=0" in got.get("reach", ""), got.get("reach")),
        check("a Swift package builds and runs, confined to the workspace and localhost",
              "strict-build-ok" in got.get("build", "") and "[exit 0]" in got.get("build", ""), got.get("build", "")[-400:]),
        check("ask config shows the strict modes and their source",
              "write workspace, network localhost" in shown.stdout and "network: localhost" in shown.stdout, shown.stdout)]
    # A trusted project may narrow the network to none, and may not widen anything.
    open(project_file, "w").write("{sandbox: {network: 'none'}}")
    master, slave = pty.openpty()
    trusted = ask("trust", stdin=slave)
    os.close(slave)
    os.close(master)
    process, got = run(calls=[("tool", "reach", "REACH")])
    results += [check("the project file is trusted", trusted.returncode == 0, trusted.stderr),
                check("a project narrows the network to none: no connection at all", "curl=7" in got.get("reach", ""), got.get("reach"))]
    open(project_file, "w").write("{sandbox: {network: 'any', write: 'anywhere'}}")
    master, slave = pty.openpty()
    ask("trust", stdin=slave)
    os.close(slave)
    os.close(master)
    process, got = run(calls=[("tool", "outside", f"echo out > '{outside}'"), ("tool", "reach", "REACH")])
    results += [check("a project cannot widen writing", "operation not permitted" in got.get("outside", "").lower() and not os.path.exists(outside), got.get("outside")),
                check("and the network stays the user's localhost", "HTTP 200 curl=0" in got.get("reach", ""), got.get("reach")),
                check("and says the sandbox is still strict", "network localhost" in process.stderr, process.stderr[:400])]
    # Only the user widens: flags replace what the files say.
    process, got = run("--write", "anywhere", "--network", "any", calls=[("tool", "outside", f"echo out > '{outside}' && cat '{outside}'")])
    results += [check("the user's flags widen it", got.get("outside", "").startswith("out\n") and "Sandbox: writes" not in process.stderr, f"{got.get('outside')} {process.stderr[:300]}")]
    bad = ask("-p", "x", "--no-sandbox", "--network", "none")
    results.append(check("--no-sandbox with a strict flag is refused", bad.returncode != 0 and "need it on" in bad.stderr, bad.stderr))
    if os.path.exists(scratch):
        os.remove(scratch)
    shutil.rmtree(away, ignore_errors=True)
    return all(results)


def probe_session_sandbox():
    print("O: a session records its strict sandbox; resuming keeps it unless the user's flags change it")
    project, state = tempfile.mkdtemp(), tempfile.mkdtemp()

    def run(*arguments):
        target = Server([])
        reach = f"curl -s -o /dev/null -w 'HTTP %{{http_code}}' -d '{{}}' {target.url}/probe; echo \" curl=$?\""
        server = Server([turn([("tool", "reach", reach)], "tool_use"), turn([("text", "Done.")], "end_turn")])
        process = subprocess.run([ASK, "--verbose", "-p", "Reach.", *arguments], cwd=project, env=environment(state, server.url),
                                 capture_output=True, text=True, timeout=120)
        got = tool_results(server).get("reach", "") if len(server.requests) == 2 else ""
        server.httpd.shutdown()
        target.httpd.shutdown()
        return process, got

    def records(path):
        return [json.loads(line) for line in open(path) if '"type":"sandbox"' in line]

    process, got = run("--network", "none")
    files = sessions(state)
    results = [check("a strict run has no network", "curl=7" in got, got),
               check("and records its sandbox in the session", len(files) == 1 and records(files[0]) == [{"network": "none", "type": "sandbox", "write": []}],
                     records(files[0]) if files else files)]
    process, got = run("--continue")
    results += [check("continuing without flags keeps the session's sandbox", "curl=7" in got, got),
                check("and says so", "Keeping this session's sandbox" in process.stderr, process.stderr[-300:]),
                check("without recording it again", len(records(files[0])) == 1, records(files[0]))]
    process, got = run("--continue", "--network", "localhost")
    results += [check("the user's flag widens a resumed session", "HTTP 200 curl=0" in got, got),
                check("and the session now records that", records(files[0])[-1]["network"] == "localhost", records(files[0]))]
    process, got = run()
    fresh = [f for f in sessions(state) if f != files[0]]
    results += [check("a new session is not narrowed by another one's record", "HTTP 200 curl=0" in got, got),
                check("and a default run records nothing", len(fresh) == 1 and records(fresh[0]) == [], fresh)]
    return all(results)


def probe_read_allowlist():
    print("P: reads confined to the workspace, the system and developer tools; git includes followed; Swift builds")
    project, state = tempfile.mkdtemp(), tempfile.mkdtemp()
    # Outside /private/var/folders, which a restricted read keeps readable as scratch.
    base = "/Users/Shared/ask-read-" + uuid.uuid4().hex
    home, elsewhere = os.path.join(base, "home"), os.path.join(base, "elsewhere")
    config = os.path.join(home, ".config")
    for directory in [os.path.join(config, "ask"), elsewhere, os.path.join(project, "Sources", "hello")]:
        os.makedirs(directory)
    open(os.path.join(config, "ask", "config.json"), "w").write("{sandbox: {read: 'workspace', write: 'workspace', network: 'localhost'}}")
    open(os.path.join(home, "notes.txt"), "w").write("PRIVATE-NOTES")
    open(os.path.join(home, ".gitconfig"), "w").write(f'[include]\n\tpath = "{elsewhere}/included.gitconfig"\n')
    open(os.path.join(elsewhere, "included.gitconfig"), "w").write("[user]\n\tname = Included Name\n\temail = i@example.com\n")
    open(os.path.join(project, "Package.swift"), "w").write(
        "// swift-tools-version: 6.0\nimport PackageDescription\n// nonce " + uuid.uuid4().hex
        + "\nlet package = Package(name: \"hello\", targets: [.executableTarget(name: \"hello\")])\n")
    open(os.path.join(project, "Sources", "hello", "main.swift"), "w").write('print("read-build-ok")\n')
    open(os.path.join(project, "file.txt"), "w").write("workspace-text")
    notes = os.path.join(home, "notes.txt")

    def run(*arguments, calls):
        target = Server([])
        reach = f"curl -s -o /dev/null -w 'HTTP %{{http_code}}' -d '{{}}' {target.url}/probe; echo \" curl=$?\""
        calls = [c if c[2] != "REACH" else (c[0], c[1], reach) for c in calls]
        server = Server([turn([c], "tool_use") for c in calls] + [turn([("text", "Done.")], "end_turn")])
        env = environment(state, server.url, config)
        env["HOME"] = home
        process = subprocess.run([ASK, "--verbose", "-p", "Work.", *arguments], cwd=project, env=env, capture_output=True,
                                 text=True, timeout=600)
        got = tool_results(server) if len(server.requests) == len(calls) + 1 else {}
        server.httpd.shutdown()
        target.httpd.shutdown()
        return process, got

    calls = [("tool", "inside", "cat file.txt"),
             ("tool", "notes", f"cat '{notes}'"),
             ("call", "tool", "read", {"path": notes}),
             ("tool", "git", "git init -q . && git add file.txt && git -c commit.gpgsign=false commit -qm m && git log -1 --format=%an"),
             ("tool", "reach", "REACH"),
             ("tool", "build", "swift build --disable-sandbox 2>&1 | tail -1 && .build/debug/hello")]
    try:
        process, got = run(calls=calls)
        results = [
            check("the run finishes", process.returncode == 0 and len(got) == 6, f"{process.returncode} {process.stderr[-300:]}"),
            check("it says reads are restricted", "reads only the workspace" in process.stderr, process.stderr[:500]),
            check("the workspace is readable", got.get("inside", "").startswith("workspace-text"), got.get("inside")),
            check("the rest of the home is not, to bash", "operation not permitted" in got.get("notes", "").lower() and "PRIVATE" not in got.get("notes", ""), got.get("notes")),
            check("nor to the read tool, which says only that it is not permitted", got.get("tool", "").startswith("Not permitted: "), got.get("tool")),
            check("git commits, reading a config the global one includes", got.get("git", "").startswith("Included Name"), got.get("git")),
            check("localhost answers", "HTTP 200 curl=0" in got.get("reach", ""), got.get("reach")),
            check("a fresh Swift package builds and runs", "read-build-ok" in got.get("build", "") and "[exit 0]" in got.get("build", ""), got.get("build", "")[-400:])]
        os.makedirs(os.path.join(project, ".ask"), exist_ok=True)
        open(os.path.join(project, ".ask", "config.json"), "w").write("{sandbox: {read: 'anywhere'}}")
        master, slave = pty.openpty()
        env = environment(state, "http://127.0.0.1:9", config)
        env["HOME"] = home
        subprocess.run([ASK, "trust"], cwd=project, env=env, stdin=slave, capture_output=True, text=True, timeout=60)
        os.close(slave)
        os.close(master)
        process, got = run(calls=[("tool", "notes", f"cat '{notes}'")])
        results.append(check("a trusted project cannot widen reading", "PRIVATE" not in got.get("notes", "") and "operation not permitted" in got.get("notes", "").lower(), got.get("notes")))
        process, got = run("--read", "anywhere", calls=[("tool", "notes", f"cat '{notes}'")])
        results.append(check("the user's flag widens it", got.get("notes", "").startswith("PRIVATE-NOTES"), got.get("notes")))
        process, got = run("--continue", calls=[("tool", "notes", f"cat '{notes}'")])
        # A record only narrows (ADR-0045): the widening was the flag's, for that run; the files restrict again.
        results.append(check("continuing without the flag is restricted again", "PRIVATE" not in got.get("notes", "") and "operation not permitted" in got.get("notes", "").lower(), got.get("notes")))
        return all(results)
    finally:
        shutil.rmtree(base, ignore_errors=True)


def probe_call_sandbox():
    print("U: a tool call narrows its own sandbox; asking for more than the run allows is refused")
    # Outside /private/var/folders, which every sandbox keeps writable and readable as scratch.
    base = "/Users/Shared/ask-callsb-" + uuid.uuid4().hex
    project, elsewhere, state = os.path.join(base, "project"), os.path.join(base, "elsewhere"), tempfile.mkdtemp()
    os.makedirs(os.path.join(project, "sub"))
    os.makedirs(elsewhere)
    open(os.path.join(elsewhere, "notes.txt"), "w").write("ELSEWHERE-NOTES")

    def run(calls, *arguments):
        target = Server([])
        reach = f"curl -s -o /dev/null -w 'HTTP %{{http_code}}' -d '{{}}' {target.url}/probe; echo \" curl=$?\""
        calls = [(c[0], c[1], c[2], {**c[3], "command": reach} if c[3].get("command") == "REACH" else c[3]) for c in calls]
        server = Server([turn([c], "tool_use") for c in calls] + [turn([("text", "Done.")], "end_turn")])
        process = subprocess.run([ASK, "--verbose", "-p", "Work.", *arguments], cwd=project, env=environment(state, server.url),
                                 capture_output=True, text=True, timeout=180)
        got = tool_results(server) if len(server.requests) == len(calls) + 1 else {}
        tools = server.requests[0]["body"].get("tools", []) if server.requests else []
        server.httpd.shutdown()
        target.httpd.shutdown()
        return process, got, tools

    try:
        process, got, tools = run([
            ("call", "open", "bash", {"command": "REACH"}),
            ("call", "closed", "bash", {"command": "REACH", "sandbox": {"network": "none"}}),
            ("call", "inside", "bash", {"command": "echo in > sub/a.txt && cat sub/a.txt", "sandbox": {"write": ["sub"]}}),
            ("call", "beside", "bash", {"command": "echo out > b.txt", "sandbox": {"write": ["sub"]}}),
            ("call", "far", "read", {"path": os.path.join(elsewhere, "notes.txt"), "sandbox": {"read": ["."]}}),
            ("call", "near", "read", {"path": os.path.join(elsewhere, "notes.txt")})])
        bash = next((t for t in tools if t["name"] == "bash"), {})
        results = [
            check("the run finishes", process.returncode == 0 and len(got) == 6, f"{process.returncode} {process.stderr[-300:]}"),
            check("the model is told it may narrow a call", "sandbox" in json.dumps(bash.get("input_schema", {})), bash),
            check("the run reaches a local server", "HTTP 200 curl=0" in got.get("open", ""), got.get("open")),
            check("a call narrowed to no network cannot", "curl=7" in got.get("closed", ""), got.get("closed")),
            check("a call narrowed to sub writes there", got.get("inside", "").startswith("in\n"), got.get("inside")),
            check("and cannot write beside it", "operation not permitted" in got.get("beside", "").lower()
                  and not os.path.exists(os.path.join(project, "b.txt")), got.get("beside")),
            check("the read tool narrowed to the workspace cannot read elsewhere",
                  got.get("far", "").startswith("Not permitted: ") and "ELSEWHERE" not in got.get("far", ""), got.get("far")),
            check("which the run itself can", got.get("near", "").startswith("ELSEWHERE-NOTES"), got.get("near"))]
        process, got, _ = run([("call", "wider", "bash", {"command": "REACH", "sandbox": {"network": "any"}})], "--network", "localhost")
        results.append(check("asking for more than --network localhost is refused without telling the model the run's policy",
                             got.get("wider", "") == "Not permitted: that request is refused." and "localhost" not in got.get("wider", ""), got.get("wider")))
        return all(results)
    finally:
        shutil.rmtree(base, ignore_errors=True)


def probe_session_narrowing():
    print("X: the model narrows the whole session; under -p undoing it is refused")
    project, state = tempfile.mkdtemp(), tempfile.mkdtemp()
    target = Server([])
    reach = f"curl -s -o /dev/null -w 'HTTP %{{http_code}}' -d '{{}}' {target.url}/probe; echo ' curl='$?"
    calls = [("call", "before", "bash", {"command": reach}),
             ("call", "narrow", "narrow_sandbox", {"sandbox": {"network": "none"}}),
             ("call", "after", "bash", {"command": reach}),
             ("call", "reset", "narrow_sandbox", {"reset": True}),
             ("call", "still", "bash", {"command": reach})]
    server = Server([turn([c], "tool_use") for c in calls] + [turn([("text", "Done.")], "end_turn")])
    process = subprocess.run([ASK, "-p", "Work."], cwd=project, env=environment(state, server.url), capture_output=True,
                             text=True, timeout=180)
    got = tool_results(server) if len(server.requests) == len(calls) + 1 else {}
    server.httpd.shutdown()
    target.httpd.shutdown()
    return all([
        check("the run finishes", process.returncode == 0 and len(got) == 5, f"{process.returncode} {process.stderr[-300:]}"),
        check("before narrowing the network is reachable", "HTTP 200 curl=0" in got.get("before", ""), got.get("before")),
        check("narrow_sandbox only says it narrowed", got.get("narrow", "") == "Narrowed for the rest of the session.", got.get("narrow")),
        check("a later call, with no sandbox argument of its own, cannot connect", "curl=7" in got.get("after", ""), got.get("after")),
        check("undoing it under -p is refused", got.get("reset", "") == "Not permitted: that request is refused.", got.get("reset")),
        check("and the session stays narrowed", "curl=7" in got.get("still", ""), got.get("still"))])


if __name__ == "__main__":
    probes = [probe_round_trip, probe_interrupt, probe_resume, probe_crash_resume, probe_compaction, probe_jobs, probe_jobs_end_with_ask,
              probe_configuration, probe_sandbox, probe_sandbox_allowance, probe_damaged_session, probe_nested_sandbox, probe_strict_sandbox,
              probe_session_sandbox, probe_read_allowlist, probe_call_sandbox, probe_session_narrowing]
    # --only F,J runs the probes whose heading starts with those letters (each prints "F: …" first).
    wanted = sys.argv[sys.argv.index("--only") + 1].split(",") if "--only" in sys.argv else None
    ok = True
    for probe in probes:
        letter = next((c[0] for c in probe.__code__.co_consts if isinstance(c, str) and re.match(r"[A-Z]: ", c)), "?")
        if wanted is None or letter in wanted:
            ok = probe() and ok
    print("PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)
