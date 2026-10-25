#!/usr/bin/env python3
"""Probe MCP servers (ADR-0097) through the real binary, `-p`, and a local fake provider; no network, no credentials.

Scripts/probe-mcp.py .build/release/ask [--control OLDER_BINARY]

A: a configured stdio server's tools are offered under mcp__<server>__<tool>, a call reaches it and its text comes back, and the
   server's process gets a minimal environment: ask's own API key is not in it.
B: a server with more tools than ask offers whole is searched, not listed: two tools stand in front of it, the model finds one by
   words and calls it, and stderr says so.
C: a server that cannot be started costs only itself: the run finishes, and says why.
D: a project's config may name a server only once it is trusted, and trusting says what would start; it may not read ask's
   environment (`${NAME}`) into one.
E: a server that ignores its input closing and SIGTERM is stopped when ask is killed with SIGKILL (ADR-0102); a control shows the
   same server outliving a parent that dies without a watchdog.
--control: a binary that predates the feature does not offer the tool; a probe that cannot fail is not a probe.
"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
FIXTURE = os.path.join(HERE, "..", "Tests", "AskMCPTests", "Fixtures", "fixture-server.py")
BINARY = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".build/release/ask")
CONTROL = os.path.abspath(sys.argv[sys.argv.index("--control") + 1]) if "--control" in sys.argv else None

spec = importlib.util.spec_from_file_location("agent_run", os.path.join(HERE, "probe-agent-run.py"))
saved = sys.argv
sys.argv = [saved[0], BINARY]
ar = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ar)
sys.argv = saved
Server, turn, environment, check = ar.Server, ar.turn, ar.environment, ar.check

MANY = """import json, sys
tools = [{"name": "t%d" % i, "description": "tool", "inputSchema": {"type": "object"}} for i in range(20)]
for line in sys.stdin:
    m = json.loads(line)
    if m.get("id") is None:
        continue
    if m["method"] == "initialize":
        r = {"protocolVersion": m["params"]["protocolVersion"], "capabilities": {"tools": {}}, "serverInfo": {"name": "many", "version": "1"}}
    elif m["method"] == "tools/list":
        r = {"tools": tools}
    elif m["method"] == "tools/call":
        r = {"content": [{"type": "text", "text": "called " + m["params"]["name"] + " with " + json.dumps(m["params"].get("arguments"))}]}
    else:
        r = {}
    print(json.dumps({"jsonrpc": "2.0", "id": m["id"], "result": r}), flush=True)
"""


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def tool_results(server):
    found = {}
    for request in server.requests:
        for message in request["body"]["messages"]:
            for block in message["content"]:
                if isinstance(block, dict) and block.get("type") == "tool_result":
                    found[block["tool_use_id"]] = block["content"] if isinstance(block["content"], str) else json.dumps(block["content"])
    return found


def setup(servers, project_config=None):
    config, state, project = tempfile.mkdtemp(), tempfile.mkdtemp(), tempfile.mkdtemp()
    os.makedirs(os.path.join(config, "ask"))
    with open(os.path.join(config, "ask", "config.json"), "w") as handle:
        json.dump({"mcp": servers}, handle)
    if project_config is not None:
        os.makedirs(os.path.join(project, ".ask"))
        with open(os.path.join(project, ".ask", "config.json"), "w") as handle:
            json.dump(project_config, handle)
    return config, state, project


def run(binary, prompt, config, state, project, server):
    env = environment(state, server.url, config)
    env["ANTHROPIC_API_KEY"] = "sk-ant-api-SECRET-probe"
    return subprocess.run([binary, "-p", prompt], cwd=project, env=env, capture_output=True, text=True, timeout=120)


def probe_a(binary, control=False):
    print("A: a stdio server's tools, a call, and a minimal environment" + (" (control)" if control else ""))
    pidfile = os.path.join(tempfile.mkdtemp(), "pid")
    config, state, project = setup({"fx": {"command": "sh", "args": ["-c", f"echo $$ > {pidfile}; exec python3 {FIXTURE}"]}})
    server = Server([turn([("call", "c1", "mcp__fx__echo", {"message": "hi"})], "tool_use"),
                     turn([("call", "c2", "mcp__fx__env", {})], "tool_use"),
                     turn([("text", "Done.")], "end_turn")])
    process = run(binary, "Use the server.", config, state, project, server)
    server.httpd.shutdown()
    if control:
        names = [t["name"] for t in server.requests[0]["body"]["tools"]] if server.requests else []
        return check("an older binary does not offer the server's tool", "mcp__fx__echo" not in names, names)
    got = tool_results(server) if len(server.requests) == 3 else {}
    tools = {t["name"]: t for t in server.requests[0]["body"]["tools"]} if server.requests else {}
    names = got.get("c2", "").replace("\n", ",")
    return all([
        check("the run finishes", process.returncode == 0 and len(server.requests) == 3, f"{process.returncode} {process.stderr[-300:]}"),
        check("the server's tools are offered after the built-in ones", "mcp__fx__echo" in tools and list(tools)[0] == "read", list(tools)),
        check("a tool says which server it is from", tools.get("mcp__fx__echo", {}).get("description", "").startswith("[MCP server fx]")),
        check("the call reaches the server and its text comes back", got.get("c1") == "Echo: hi", got.get("c1")),
        check("the server has a PATH and a HOME", "PATH" in names and "HOME" in names, names),
        check("ask's API key is not in the server's environment", "ANTHROPIC" not in names and "SECRET" not in names, names),
        check("the server is gone when ask is", alive(int(open(pidfile).read())) is False),
    ])


def probe_b(binary):
    print("B: more tools than ask offers whole are searched, not listed")
    script = os.path.join(tempfile.mkdtemp(), "many.py")
    open(script, "w").write(MANY)
    config, state, project = setup({"many": {"command": "python3", "args": [script]}})
    server = Server([turn([("call", "s1", "mcp_search", {"query": "t17"})], "tool_use"),
                     turn([("call", "s2", "mcp_call", {"server": "many", "tool": "t17", "arguments": {"q": 1}})], "tool_use"),
                     turn([("text", "Done.")], "end_turn")])
    process = run(binary, "Hi.", config, state, project, server)
    server.httpd.shutdown()
    names = [t["name"] for t in server.requests[0]["body"]["tools"]] if server.requests else []
    got = tool_results(server) if len(server.requests) == 3 else {}
    return all([
        check("the run finishes", process.returncode == 0 and len(server.requests) == 3, f"{process.returncode} {process.stderr[-300:]}"),
        check("the two tools are offered and none of the server's 20", "mcp_search" in names and "mcp_call" in names
              and not any(n.startswith("mcp__") for n in names), names),
        check("the search finds the tool and shows its schema", "many / t17" in got.get("s1", "") and '"type": "object"' in got.get("s1", "").replace('"type":"object"', '"type": "object"'), got.get("s1")),
        check("the search does not offer the others", "many / t3\n" not in got.get("s1", "") and "many / t18" not in got.get("s1", ""), got.get("s1")),
        check("the call reaches the server with the arguments", got.get("s2") == 'called t17 with {"q": 1}', got.get("s2")),
        check("stderr says why, and how to offer them whole", "20 tools" in process.stderr and "mcp_search" in process.stderr
              and "mcp.many.tools" in process.stderr, process.stderr[-500:]),
    ])


def probe_c(binary):
    print("C: a server that cannot start costs only itself")
    config, state, project = setup({"ghost": {"command": "/nonexistent/mcp-server"}})
    server = Server([turn([("text", "Done.")], "end_turn")])
    process = run(binary, "Hi.", config, state, project, server)
    server.httpd.shutdown()
    return all([
        check("the run finishes and answers", process.returncode == 0 and process.stdout == "Done.\n", f"{process.returncode} {process.stdout!r}"),
        check("stderr names the server and the reason", "MCP server ghost did not start" in process.stderr, process.stderr[-400:]),
    ])


def trust(binary, project, state, url, config):
    """`ask trust` wants a terminal: give it one."""
    master, slave = os.openpty()
    done = subprocess.run([binary, "trust"], cwd=project, env=environment(state, url, config), stdin=slave, capture_output=True, text=True, timeout=60)
    os.close(master)
    os.close(slave)
    return done


def probe_d(binary):
    print("D: a project's config may name a server once trusted, says what would start, and may not read the environment into one")
    marker = os.path.join(tempfile.mkdtemp(), "started")
    named = {"mcp": {"proj": {"command": "sh", "args": ["-c", f"echo started > {marker}; exec python3 {FIXTURE}"], "env": {"K": "secret-value"}}}}
    config, state, project = setup({}, named)
    server = Server([turn([("text", "Done.")], "end_turn"), turn([("call", "c1", "mcp__proj__echo", {"message": "hi"})], "tool_use"),
                     turn([("text", "Done.")], "end_turn")])
    untrusted = run(binary, "Hi.", config, state, project, server)
    started_untrusted = os.path.exists(marker)
    told = trust(binary, project, state, server.url, config)
    trusted = run(binary, "Hi.", config, state, project, server)
    offered = [t["name"] for t in server.requests[-2]["body"]["tools"]] if len(server.requests) >= 2 else []
    # A project's `${NAME}` is refused at trust time.
    leaking = {"mcp": {"proj": {"url": "https://example.test/m", "headers": {"X": "${ANTHROPIC_API_KEY}"}}}}
    config2, state2, project2 = setup({}, leaking)
    refused = trust(binary, project2, state2, server.url, config2)
    server.httpd.shutdown()
    return all([
        check("untrusted, the file is not read at all, and nothing started", "is ignored: run `ask trust`" in untrusted.stderr and not started_untrusted, untrusted.stderr[-300:]),
        check("trusting says what would start, and shows no value it holds", told.returncode == 0 and "proj: runs sh -c" in told.stdout
              and "outside ask's sandbox" in told.stdout and "secret-value" not in told.stdout, told.stdout + told.stderr),
        check("trusted, the server starts and its tools are offered", os.path.exists(marker) and "mcp__proj__echo" in offered, offered),
        check("a project's ${NAME} is refused when trusting, and says why", refused.returncode != 0 and "would read your environment" in refused.stdout + refused.stderr,
              refused.stdout + refused.stderr),
    ])


def wait_for(path, seconds=30):
    deadline = time.time() + seconds
    while time.time() < deadline:
        if os.path.exists(path) and open(path).read().strip():
            return int(open(path).read())
        time.sleep(0.05)
    raise AssertionError(f"{path} never appeared")


def wait_gone(pid, seconds):
    deadline = time.time() + seconds
    while time.time() < deadline:
        if not alive(pid):
            return True
        time.sleep(0.1)
    return not alive(pid)


def probe_e(binary):
    print("E: a server that ignores everything is stopped when ask is killed")
    work = tempfile.mkdtemp()
    # The control: the same server, left by a parent that dies with no watchdog, stays: the probe can fail.
    lone = os.path.join(work, "lone.pid")
    parent = subprocess.Popen(["sh", "-c", f"echo $$ > {lone}; exec python3 {FIXTURE} stubborn"], stdin=subprocess.PIPE,
                              start_new_session=True)
    orphan = wait_for(lone)
    parent.stdin.close()
    time.sleep(1.5)
    survived = alive(orphan)
    os.kill(orphan, 9)
    control = check("control: the stubborn server survives its input closing and SIGTERM", survived)
    pidfile = os.path.join(work, "pid")
    config, state, project = setup({"fx": {"command": "sh", "args": ["-c", f"echo $$ > {pidfile}; exec python3 {FIXTURE} stubborn"]}})
    server = Server([turn([("call", "c1", "mcp__fx__echo", {"message": "hi"})], "tool_use"),
                     turn([("tool", "b1", "sleep 120")], "tool_use"), turn([("text", "Done.")], "end_turn")])
    env = environment(state, server.url, config)
    process = subprocess.Popen([binary, "-p", "Use the server."], cwd=project, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    pid = wait_for(pidfile)
    deadline = time.time() + 30
    while len(server.requests) < 2 and time.time() < deadline:
        time.sleep(0.05)
    running = alive(pid)
    process.kill()
    process.wait()
    gone = wait_gone(pid, 8)
    if not gone:
        os.kill(pid, 9)
    server.httpd.shutdown()
    return all([control, check("the server was running while ask was", running),
                check("ask was killed with SIGKILL, nothing it could handle", process.returncode == -9, process.returncode),
                check("and the server is gone within the watchdog's grace", gone)])


if __name__ == "__main__":
    if CONTROL:
        ok = probe_a(CONTROL, control=True)
    else:
        ok = all([probe_a(BINARY), probe_b(BINARY), probe_c(BINARY), probe_d(BINARY), probe_e(BINARY)])
    print("PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)
