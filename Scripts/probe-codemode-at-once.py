#!/usr/bin/env python3
"""Roadmap 0012, ADR-0156: the calls a script makes at once, beyond reads and commands, through the real binary. The model
(the local fake) calls `codemode` with a script that makes sixteen or eight calls with `Promise.all`.

A: sixteen edits at once to one file are all made (two or three were: each read the same text and wrote over the others).
B: sixteen writes at once, each to its own file, all land; sixteen at once to one file leave one of them, whole.
C: eight commands left running as jobs at once are eight jobs, and each wait returns its own job's output.
D: eight calls at once to one MCP server reach it together, and each gets its own answer.
E: sixteen tasks added at once are sixteen tasks, each with an id of its own.

Scripts/probe-codemode-at-once.py .build/release/ask
"""
import importlib.util
import json
import os
import sys
import tempfile

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("codemode_probe", os.path.join(here, "probe-codemode.py"))
codemode = importlib.util.module_from_spec(spec)
spec.loader.exec_module(codemode)
agent = codemode.agent

# An MCP server that answers each call from a thread of its own, after `slow` seconds, and says when the call arrived.
SERVER = """import json, sys, threading, time
lock = threading.Lock()
def send(m):
    with lock:
        sys.stdout.write(json.dumps(m) + "\\n"); sys.stdout.flush()
def call(m, arrived):
    a = m["params"].get("arguments") or {}
    time.sleep(float(a.get("slow", 0)))
    text = "%s arrived %.3f" % (a.get("message"), arrived)
    send({"jsonrpc": "2.0", "id": m["id"], "result": {"content": [{"type": "text", "text": text}]}})
for line in sys.stdin:
    m = json.loads(line)
    if m.get("id") is None: continue
    if m["method"] == "initialize":
        r = {"protocolVersion": m["params"]["protocolVersion"], "capabilities": {"tools": {}},
             "serverInfo": {"name": "at-once", "version": "1"}}
    elif m["method"] == "tools/list":
        r = {"tools": [{"name": "echo", "description": "Echoes.", "inputSchema": {"type": "object"},
                        "annotations": {"readOnlyHint": True}}]}
    elif m["method"] == "tools/call":
        threading.Thread(target=call, args=(m, time.monotonic())).start(); continue
    else:
        r = {}
    send({"jsonrpc": "2.0", "id": m["id"], "result": r})
"""

EACH = "[...Array(N).keys()].map"
EDITS = f"""const made = await Promise.all({EACH}(i =>
  tools.write({{ path: "one.txt", old_text: "marker-" + i + "-old", new_text: "marker-" + i + "-new" }})));
return made.filter(m => m.startsWith("Replaced 1 occurrence")).length;"""
WRITES = f"""await Promise.all({EACH}(i => tools.write({{ path: "own-" + i + ".txt", content: "file " + i + "\\n" }})));
await Promise.all({EACH}(i => tools.write({{ path: "same.txt", content: String.fromCharCode(97 + i).repeat(400000) }})));
return "written";"""
JOBS = f"""const started = await Promise.all({EACH}(i =>
  tools.bash({{ command: "sleep 1; echo out-" + i, yield_seconds: 1 }})));
const ids = started.map(s => (s.match(/job-\\d+/) || ["none"])[0]);
const waited = await Promise.all(ids.map(id => tools.job({{ job: id, action: "wait", timeout_seconds: 30 }})));
return [new Set(ids).size, waited.filter((w, i) => w.includes("out-" + i + "\\n")).length];"""
MCP = f"""const began = Date.now();
const said = await Promise.all({EACH}(i => tools.mcp__once__echo({{ message: "m" + i, slow: 0.5 }})));
const arrived = said.map(s => Number(s.split(" ").pop()));
return [said.filter((s, i) => s.includes("m" + i + " ")).length, Math.max(...arrived) - Math.min(...arrived) < 0.25,
        Date.now() - began];"""
TASKS = f"""await Promise.all({EACH}(i => tools.tasks({{ changes: [{{ op: "add", title: "task-" + i + "." }}] }})));
const all = await tools.tasks({{ read: {{ view: "all" }} }});
return [new Set(all.match(/task-\\d+\\./g)).size, new Set(all.match(/^t\\d+/gm)).size];"""


def run(binary, project, script, count, config=None):
    """Runs `script` with `count` for N; what it returned, as JSON."""
    saved = agent.environment
    if config:
        agent.environment = lambda state, url: saved(state, url, config)
    try:
        result, took, _ = codemode.run_print(binary, project, script.replace("Array(N)", f"Array({count})"))
    finally:
        agent.environment = saved
    try:
        return json.loads(result.split("\n", 1)[1]), took, result
    except (IndexError, ValueError):
        return None, took, result


def read(path):
    """The file's text; nothing when there is no file."""
    if not os.path.exists(path):
        return ""
    with open(path) as file:
        return file.read()


def main():
    binary = os.path.abspath(sys.argv[1])
    project = os.path.realpath(tempfile.mkdtemp())
    path = lambda name: os.path.join(project, name)  # noqa: E731

    print("A: edits at once to one file")
    with open(path("one.txt"), "w") as file:
        file.write("".join(f"marker-{i}-old\n" for i in range(16)))
    said, _, raw = run(binary, project, EDITS, 16)
    with open(path("one.txt")) as file:
        made = sum(line.endswith("-new\n") for line in file)
    results = [agent.check("sixteen edits at once to one file are all made, as each said", (said, made) == (16, 16),
                           (said, made, raw[:200]))]

    print("B: writes at once")
    _, _, raw = run(binary, project, WRITES, 16)
    own = sum(read(path(f"own-{i}.txt")) == f"file {i}\n" for i in range(16))
    same = read(path("same.txt"))
    results += [
        agent.check("sixteen writes at once, each to its own file, all land", own == 16, (own, raw[:200])),
        agent.check("sixteen at once to one file leave one of them, whole", len(same) == 400000 and len(set(same)) == 1,
                    (len(same), sorted(set(same)))),
    ]

    print("C: jobs at once")
    jobs, took, raw = run(binary, project, JOBS, 8)
    results.append(agent.check("eight jobs started at once are eight, and each wait returns its own job's output",
                               jobs == [8, 8] and took < 6, (jobs, round(took, 1), raw[:300])))

    print("D: an MCP server's tool, called at once")
    config = tempfile.mkdtemp()
    os.makedirs(os.path.join(config, "ask"))
    with open(path("server.py"), "w") as file:
        file.write(SERVER)
    with open(os.path.join(config, "ask", "config.json"), "w") as file:
        json.dump({"mcp": {"once": {"command": sys.executable, "args": [path("server.py")]}}}, file)
    mcp, _, raw = run(binary, project, MCP, 8, config)
    results.append(agent.check("eight calls at once reach the server together, and each gets its own answer",
                               mcp is not None and mcp[:2] == [8, True] and mcp[2] < 2000, (mcp, raw[:300])))

    print("E: tasks at once")
    tasks, _, raw = run(binary, project, TASKS, 16)
    results.append(agent.check("sixteen tasks added at once are sixteen, each with an id of its own", tasks == [16, 16],
                               (tasks, raw[:300])))
    print("PASS" if all(results) else "FAIL")
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
