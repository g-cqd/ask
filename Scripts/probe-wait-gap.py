#!/usr/bin/env python3
"""Probe that `wait` does not find text a command never printed (roadmap 0057, ADR-0083), through the real binary.

Scripts/probe-wait-gap.py .build/release/ask [--control OLDER_BINARY]

A job prints 1.5 MiB while the model is busy with a foreground command: `Re` ends the first 512 KiB that ask keeps, `ad` starts the last
512 KiB, and a megabyte it drops lies between. The model then waits for `Read`. The stream never contained it; the buffer used to join
its two ends and say it did. With --control, a binary that predates the fix must report the text found: a probe that cannot fail is not
a probe.
"""
import importlib.util
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("agent_probe", os.path.join(HERE, "probe-agent-run.py"))
saved = sys.argv
sys.argv = [saved[0], saved[1]]
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)
sys.argv = saved
KEPT = 512 * 1024
JOB = ("sleep 2; python3 -c \"import sys; "
       f"sys.stdout.write('x' * ({KEPT} - 2) + 'Re' + 'z' * {KEPT} + 'ad' + 'y' * ({KEPT} - 2))\"; sleep 60")


def run(binary):
    project, state = tempfile.mkdtemp(), tempfile.mkdtemp()
    server = agent.Server([
        agent.turn([("call", "t1", "bash", {"command": JOB, "yield_seconds": 1})], "tool_use"),
        agent.turn([("tool", "t2", "sleep 4")], "tool_use"),  # the job prints its 1.5 MiB meanwhile
        agent.turn([("call", "t3", "job", {"job": "job-1", "action": "wait", "wait_for_output": "Read", "timeout_seconds": 2})], "tool_use"),
        agent.turn([("call", "t4", "job", {"job": "job-1", "action": "stop"})], "tool_use"),
        agent.turn([("text", "Done.")], "end_turn")])
    try:
        ran = subprocess.run([binary, "-p", "Wait for Read."], cwd=project, env=agent.environment(state, server.url),
                             capture_output=True, text=True, timeout=120)
        return ran.returncode, agent.tool_results(server) if len(server.requests) == 5 else {}
    finally:
        server.httpd.shutdown()


def check(label, condition, detail=""):
    print(("PASS " if condition else "FAIL ") + label + ("" if condition else f": {detail!r}"), flush=True)
    checks.append(label)
    if not condition:
        raise AssertionError(label)


checks = []


def main():
    binary = os.path.abspath(sys.argv[1])
    if "--control" in sys.argv:
        code, got = run(os.path.abspath(sys.argv[sys.argv.index("--control") + 1]))
        check("control (a binary before the fix): wait reports Read found, though it was never printed",
              code == 0 and 'printed "Read"' in got.get("t3", ""))
    code, got = run(binary)
    check("candidate: the run completed", code == 0 and "t3" in got)
    check("candidate: wait does not report Read found", "printed \"Read\"" not in got["t3"], got["t3"][-200:])
    check("candidate: it times out instead, as a text that never came", "nothing happened within" in got["t3"], got["t3"][-200:])
    print(f"{len(checks)} checks passed")


if __name__ == "__main__":
    main()
