#!/usr/bin/env python3
"""Probe MCP servers (ADR-0097) through the real binary, `-p`, and a local fake provider; no network, no credentials.

Scripts/probe-mcp.py .build/release/ask [--control OLDER_BINARY]

A: a configured stdio server's tools are offered under mcp__<server>__<tool>, a call reaches it and its text comes back, and the
   server's process gets a minimal environment: ask's own API key is not in it.
B: a server with more tools than ask offers whole offers none, and says so on stderr.
C: a server that cannot be started costs only itself: the run finishes, and says why.
D: a project's own config file may not name a server: it is refused, and nothing is started.
E: a server's process is gone when ask is.
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
    print("B: more tools than ask offers whole")
    script = os.path.join(tempfile.mkdtemp(), "many.py")
    open(script, "w").write(MANY)
    config, state, project = setup({"many": {"command": "python3", "args": [script]}})
    server = Server([turn([("text", "Done.")], "end_turn")])
    process = run(binary, "Hi.", config, state, project, server)
    server.httpd.shutdown()
    names = [t["name"] for t in server.requests[0]["body"]["tools"]] if server.requests else []
    return all([
        check("the run finishes", process.returncode == 0, process.stderr[-300:]),
        check("none of its 20 tools is offered", not any(n.startswith("mcp__") for n in names), names),
        check("stderr says why and how to choose", "20 tools" in process.stderr and "mcp.many.tools" in process.stderr, process.stderr[-400:]),
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


def probe_d(binary):
    print("D: a project's own config may not name a server, trusted or not")
    marker = os.path.join(tempfile.mkdtemp(), "started")
    config, state, project = setup({}, {"mcp": {"evil": {"command": "sh", "args": ["-c", f"touch {marker}"]}}})
    server = Server([turn([("text", "Done.")], "end_turn")] * 2)
    untrusted = run(binary, "Hi.", config, state, project, server)
    # `ask trust` wants a terminal, and it parses the file as a project's: it must refuse this one.
    master, slave = os.openpty()
    trust = subprocess.run([binary, "trust"], cwd=project, env=environment(state, server.url, config), stdin=slave,
                           capture_output=True, text=True, timeout=60)
    os.close(master)
    os.close(slave)
    server.httpd.shutdown()
    said = trust.stderr + trust.stdout
    return all([
        check("untrusted, the file is not read at all", "is ignored: run `ask trust`" in untrusted.stderr, untrusted.stderr[-300:]),
        check("trusting it is refused, and says why", trust.returncode != 0 and "can only be set in your own config file" in said, said[-400:]),
        check("the server was never started", not os.path.exists(marker)),
    ])


if __name__ == "__main__":
    if CONTROL:
        ok = probe_a(CONTROL, control=True)
    else:
        ok = all([probe_a(BINARY), probe_b(BINARY), probe_c(BINARY), probe_d(BINARY)])
    print("PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)
