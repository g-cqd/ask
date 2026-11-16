#!/usr/bin/env python3
"""Roadmap 0012, ADR-0156: codemode through the real binary. The model (the local fake) calls `codemode` with a script; the
script runs in a child `ask codemode`, and its calls come back through the loop.

A: `ask -p`: a script reads two files at once, runs a command, filters, and returns one line. The model's next request holds
   that line and none of what the tools returned; the files' whole text never reached it.
B: the limits, through the real process: a script that spins is stopped at its deadline, one that allocates without end at
   its memory, each keeps what it had said, and neither leaves a process behind. A script that asks for more output than a
   tool is cut at gets it whole.
C: the sandbox holds inside a script: a write in the workspace lands, one outside it is refused, and the script is told.
E: the same in Python: a script on the first python3 of the PATH calls the tools, reaches nothing by itself (no file of the
   person's, no write, no network, no program), and is stopped at its memory: one allocation of 3 GiB as it grows, its
   peak read from outside the process.
D: through `ask serve`, where a person is asked: one question for the script, with the script shown; the write it makes is
   not asked about again; denied, nothing runs.

Scripts/probe-codemode.py .build/release/ask
"""
import ctypes
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import threading
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

PYTHON_READ_AND_FILTER = """import asyncio
a, b = await asyncio.gather(tools.read(path="a.txt"), tools.read(path="b.txt"))
made = await tools.bash(command='echo "built in $(basename "$PWD")"')
errors = [line for line in (a + b).split("\\n") if "ERROR" in line]
return str(len(errors)) + " errors; " + made.strip().splitlines()[0]
"""

PYTHON_REACH = """import os, socket, subprocess
tried = {}
for name, attempt in {
    "home": lambda: os.listdir(HOME), "passwd": lambda: open("/etc/passwd").read(),
    "write": lambda: open(WORKSPACE + "/python-wrote.txt", "w").write("x"),
    "network": lambda: socket.create_connection(("1.1.1.1", 80), 2), "program": lambda: subprocess.run(["/bin/ls"]),
}.items():
    try:
        attempt(); tried[name] = "REACHED"
    except OSError as error:
        tried[name] = type(error).__name__
through = await tools.write(path="python-made.txt", content="made by a Python script\\n")
return [tried, through.splitlines()[0]]"""

PYTHON_ALLOCATE = "text('said before')\nbig = []\nwhile True: big.append([0] * (1 << 16))"

# One allocation, twelve times the limit: made under the interpreter's lock, so nothing inside the process sees it grow.
PYTHON_ONE_ALLOCATION = ("import time\ntext('said before')\nawait tools.read(path='a.txt')\ntime.sleep(1)\n"
                         "big = [0] * (3 << 27)\nreturn len(big)")

SPIN = '// @options: {"timeout_ms": 700}\ntext("said before"); console.log("a line");\nwhile (true) {}'
ALLOCATE = 'text("said before"); await tools.read({ path: "a.txt" });\nconst big = []; for (;;) big.push(new Array(1 << 17).fill(1));'
LARGE = '// @options: {"max_output_tokens": 80000}\nfor (let i = 0; i < 3000; i++) text("row " + i + " " + "x".repeat(60)); return "end";'
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


def run_print(binary, project, script, extra=(), language=None):
    arguments = {"code": script, **({"language": language} if language else {})}
    server = agent.Server([agent.turn([("call", "c1", "codemode", arguments)], "tool_use"),
                           agent.turn([("text", "Done.")], "end_turn")])
    state = tempfile.mkdtemp()
    started = time.monotonic()
    run = subprocess.run([binary, "-p", "Go.", *extra], cwd=project, env=agent.environment(state, server.url),
                         capture_output=True, text=True, timeout=120)
    took = time.monotonic() - started
    result = last_result(server) if len(server.requests) >= 2 else "(the model was not asked again) " + run.stderr[-300:]
    server.httpd.shutdown()
    return result, took, json.dumps(server.requests[-1]["body"]) if server.requests else ""


def python_peak(done):
    """The most a script's Python took, in MiB, read from outside it every millisecond: a list that holds it, and the thread."""
    proc, usage, peak = ctypes.CDLL("/usr/lib/libproc.dylib"), (ctypes.c_uint64 * 64)(), [0]

    def watch():
        found = []
        while not done.is_set() and not found:
            found = subprocess.run(["pgrep", "-f", "codemode.py"], capture_output=True, text=True).stdout.split()
        # rusage_info_v4: sixteen bytes of identifier, then 64-bit fields, of which the eighth is the physical footprint.
        while found and not done.is_set() and proc.proc_pid_rusage(int(found[0]), 4, ctypes.byref(usage)) == 0:
            peak[0] = max(peak[0], usage[9] >> 20)
            time.sleep(0.001)

    thread = threading.Thread(target=watch, daemon=True)
    thread.start()
    return peak, thread


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
    results.append(agent.check("and keeps what it had said",
                               spun.endswith("\nsaid before\n<console_output>\na line\n</console_output>"), spun[-200:]))
    grown, took, _ = run_print(binary, project, ALLOCATE)
    results.append(agent.check("a script that allocates without end is stopped at its memory, says so, and keeps what it had said",
                               "took more than 256 MiB of memory" in grown and grown.endswith("\nsaid before") and took < 30,
                               (grown[:200], round(took, 1))))
    results.append(agent.check("neither left a process behind", not hosts(), hosts()))
    large, _, _ = run_print(binary, project, LARGE)
    results.append(agent.check("a script that asks to return more than a tool's 50 KiB and 2,000 lines is returned whole",
                               "row 1500 " in large and "row 2999 " in large and "omitted" not in large and len(large) > 200_000,
                               (len(large), large[:120])))

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

    print("E: the same in Python, on the first python3 of the PATH")
    result, took, request = run_print(binary, project, PYTHON_READ_AND_FILTER, language="python")
    home = os.path.expanduser("~")
    reach = PYTHON_REACH.replace("HOME", json.dumps(home)).replace("WORKSPACE", json.dumps(project))
    reached, _, _ = run_print(binary, project, reach, language="python")
    refused = {"home": "PermissionError", "passwd": "PermissionError", "write": "PermissionError",
               "network": "PermissionError", "program": "PermissionError"}
    grown, grew, _ = run_print(binary, project, PYTHON_ALLOCATE, language="python")
    done = threading.Event()
    peak, watching = python_peak(done)
    once, _, _ = run_print(binary, project, PYTHON_ONE_ALLOCATION, language="python")
    done.set()
    watching.join()
    left = subprocess.run(["pgrep", "-f", "codemode.py"], capture_output=True, text=True).stdout.split()
    results += [
        agent.check("a Python script completed, and what it returned is the result",
                    result.startswith("Script completed in ") and result.endswith(f"5 errors; built in {os.path.basename(project)}"),
                    result[:300]),
        agent.check("what the tools returned never reached the model", "nothing to see" not in request, len(request)),
        agent.check("by itself it reaches no file, no network and no program", json.dumps(refused) in reached, reached[:400]),
        agent.check("and wrote nothing by itself, but writes through the tool",
                    not os.path.exists(os.path.join(project, "python-wrote.txt"))
                    and os.path.exists(os.path.join(project, "python-made.txt")), os.listdir(project)),
        agent.check("a Python script that allocates without end is stopped at its memory, and keeps what it had said",
                    "took more than 256 MiB of memory" in grown and grown.endswith("\nsaid before") and grew < 30,
                    (grown[:200], round(grew, 1))),
        agent.check(f"one allocation of 3 GiB is stopped as it grows, long before it is made (its peak: {peak[0]} MiB)",
                    "took more than 256 MiB of memory" in once and once.endswith("\nsaid before") and 200 < peak[0] < 1024,
                    once[:200]),
        agent.check("no Python is left behind", not left, left),
    ]
    server.httpd.shutdown()
    print("PASS" if all(results) else "FAIL")
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
