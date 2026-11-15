#!/usr/bin/env python3
"""Roadmap 0012, ADR-0156: codemode through the real binary. The model (the local fake) calls `codemode` with a script; the
script runs in a child `ask codemode`, and its calls come back through the loop.

A: `ask -p`: a script reads two files at once, runs a command, filters, and returns one line. The model's next request holds
   that line and none of what the tools returned; the files' whole text never reached it.
B: the limits, through the real process: a script that spins is stopped at its deadline, one that allocates without end at
   its memory, and neither leaves a process behind.
C: the sandbox holds inside a script: a write in the workspace lands, one outside it is refused, and the script is told.
D: through `ask serve`, where a person is asked: one question for the script, with the script shown; the write it makes is
   not asked about again; denied, nothing runs.

Scripts/probe-codemode.py .build/release/ask
"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import time

here = os.path.dirname(os.path.abspath(__file__))


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, os.path.join(here, file))
    module = importlib.util.module_from_spec(spec)
    saved, sys.argv = sys.argv, sys.argv[:1]
    spec.loader.exec_module(module)
    sys.argv = saved
    return module


serve = load("serve_probe", "probe-serve.py")
agent = serve.agent

READ_AND_FILTER = """const [a, b] = await Promise.all([tools.read({ path: "a.txt" }), tools.read({ path: "b.txt" })]);
const made = await tools.bash({ command: 'echo "built in $(basename "$PWD")"' });
const errors = (a + b).split("\\n").filter((line) => line.includes("ERROR"));
return `${errors.length} errors; ${made.trim().split("\\n")[0]}`;"""

SPIN = '// @options: {"timeout_ms": 700}\nwhile (true) {}'
ALLOCATE = "const big = []; for (;;) big.push(new Array(1 << 17).fill(1));"
WRITES = """const inside = await tools.write({ path: "made.txt", content: "made by a script\\n" });
let outside;
try { outside = await tools.write({ path: "/etc/ask-probe.txt", content: "no\\n" }); } catch (e) { outside = "refused: " + e.message; }
return [inside.split("\\n")[0], outside];"""


def last_result(server):
    """The tool result in the model's latest request, as text."""
    for block in reversed(server.requests[-1]["body"]["messages"][-1]["content"]):
        if block.get("type") == "tool_result":
            content = block.get("content")
            return content if isinstance(content, str) else "".join(c.get("text", "") for c in content)
    return ""


def run_print(binary, project, script, extra=()):
    server = agent.Server([agent.turn([("call", "c1", "codemode", {"code": script})], "tool_use"),
                           agent.turn([("text", "Done.")], "end_turn")])
    state = tempfile.mkdtemp()
    started = time.monotonic()
    run = subprocess.run([binary, "-p", "Go.", *extra], cwd=project, env=agent.environment(state, server.url),
                         capture_output=True, text=True, timeout=120)
    took = time.monotonic() - started
    result = last_result(server) if len(server.requests) >= 2 else "(the model was not asked again) " + run.stderr[-300:]
    server.httpd.shutdown()
    return result, took, json.dumps(server.requests[-1]["body"]) if server.requests else ""


def hosts():
    return subprocess.run(["pgrep", "-f", "ask codemode"], capture_output=True, text=True).stdout.split()


def main():
    binary = os.path.abspath(sys.argv[1])
    project = os.path.realpath(tempfile.mkdtemp())
    noise = "\n".join(f"line {i} of a long log, nothing to see" for i in range(400))
    for name, errors in (("a.txt", 2), ("b.txt", 3)):
        with open(os.path.join(project, name), "w") as file:
            file.write(noise + "\n" + "\n".join(f"ERROR {name} {i}" for i in range(errors)) + "\n")

    print("A: one script in place of three calls")
    result, took, request = run_print(binary, project, READ_AND_FILTER)
    results = [
        agent.check("the script completed, and what it returned is the result",
                    result.startswith("Script completed in ") and result.endswith(f"5 errors; built in {os.path.basename(project)}"),
                    result[:300]),
        agent.check("what the tools returned never reached the model", "nothing to see" not in request, len(request)),
    ]

    print("B: the limits")
    spun, took, _ = run_print(binary, project, SPIN)
    results.append(agent.check("a script that spins is stopped at its deadline, and says so",
                               "ran past its deadline of 0.7 s" in spun and 0.7 <= took < 15, (spun[:200], round(took, 1))))
    grown, took, _ = run_print(binary, project, ALLOCATE)
    results.append(agent.check("a script that allocates without end is stopped at its memory, and says so",
                               "took more than 256 MiB of memory" in grown and took < 30, (grown[:200], round(took, 1))))
    results.append(agent.check("neither left a process behind", not hosts(), hosts()))

    print("C: the sandbox, inside a script")
    wrote, _, _ = run_print(binary, project, WRITES)
    results += [
        agent.check("a write in the workspace lands", os.path.exists(os.path.join(project, "made.txt")), wrote[:300]),
        agent.check("a write outside it is refused, and the script is told",
                    "refused: " in wrote and not os.path.exists("/etc/ask-probe.txt"), wrote[:300]),
    ]

    print("D: asked once, through ask serve")
    os.remove(os.path.join(project, "made.txt"))
    server = agent.Server([
        agent.turn([("call", "c1", "codemode", {"code": WRITES})], "tool_use"), agent.turn([("text", "Wrote it.")], "end_turn"),
        agent.turn([("call", "c2", "codemode", {"code": 'await tools.write({ path: "never.txt", content: "x" });'})], "tool_use"),
        agent.turn([("text", "Not allowed.")], "end_turn"),
    ])
    state = tempfile.mkdtemp()
    client = serve.Client(binary, project, agent.environment(state, server.url))
    client.request("initialize", {"protocolVersion": 1})
    session = client.request("session/new", {"cwd": project})[0]["result"]["sessionId"]
    answer, _ = client.request("session/prompt", serve.prompt(session, "Write it."))
    asked = client.asked[:]
    client.choices = ["deny"]
    denied, _ = client.request("session/prompt", serve.prompt(session, "And another."))
    told = last_result(server)
    results += [
        agent.check("the person is asked once, about the script, with the script shown",
                    len(asked) == 1 and asked[0]["toolCall"]["toolCallId"] == "c1"
                    and "script of 4 lines calling write" in asked[0]["toolCall"]["title"]
                    and "made.txt" in json.dumps(asked[0]["toolCall"].get("content", "")), asked),
        agent.check("allowed, its write ran without another question",
                    answer.get("result") == {"stopReason": "end_turn"} and os.path.exists(os.path.join(project, "made.txt")), answer),
        agent.check("denied, nothing ran, and the model is told", len(client.asked) == 2
                    and not os.path.exists(os.path.join(project, "never.txt")) and "did not allow" in told, (denied, told[:200])),
    ]
    status, said = client.close()
    results.append(agent.check("ask ends with 0, with no host left", status == 0 and not hosts(), (status, hosts(), said[-200:])))
    server.httpd.shutdown()
    print("PASS" if all(results) else "FAIL")
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
