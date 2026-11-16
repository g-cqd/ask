#!/usr/bin/env python3
"""Roadmap 0234 step 2: `ask serve` judged by a client that is not ask's own, ACP's Test Compatibility Kit
(github.com/agentclientprotocol/acp-tck), at the commit named here. The kit starts `ask serve` once per test and speaks the protocol
to it; the model is the local fake server, which answers any prompt, and slowly the one the kit cancels.

Not a gate: it needs `uv` and the network (the kit is fetched), and the kit says of itself that it is experimental and no statement
of conformance. It is an oracle ask did not write: a FAIL is a disagreement to read, in the report it leaves.

    python3 Scripts/probe-acp-tck.py .build/release/ask [REPORT.json] [-- kit options]
"""
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
spec = importlib.util.spec_from_file_location("agent_probe", os.path.join(here, "probe-agent-run.py"))
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)

KIT = "git+https://github.com/agentclientprotocol/acp-tck@f050441441ca4faafd1d4e58761125304d06743d"  # v0.3.0
SLOW = "Take your time over this one."


def answer(body):
    """The fake model's answer: after a while for the prompt the kit cancels, so that the cancellation finds a turn running."""
    if SLOW in json.dumps(body.get("messages", [])[-1:]):
        time.sleep(8)
    return None


def main():
    if not shutil.which("uvx"):
        print("FAIL: uvx is not installed (https://docs.astral.sh/uv/)")
        return 1
    options = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    named = sys.argv[1:sys.argv.index("--")] if "--" in sys.argv else sys.argv[1:]
    binary = os.path.abspath(named[0])
    root = os.path.realpath(tempfile.mkdtemp())
    report = os.path.abspath(named[1]) if len(named) > 1 else os.path.join(root, "report.json")
    work = os.path.join(root, "work")
    os.makedirs(work)
    server = agent.Server([], route=answer)
    # Only what the probe's environment adds or changes: the kit lays it over its own.
    environment = agent.environment(os.path.join(root, "state"), server.url)
    command = ["uvx", "--from", KIT, "acp-tck", "--agent-cwd", work, "--report-json", report, "--cancel-prompt", SLOW]
    for name, value in environment.items():
        if os.environ.get(name) != value:
            command += ["--agent-env", f"{name}={value}"]
    kept = {name: value for name, value in os.environ.items() if not name.startswith("ASK_")}
    ran = subprocess.run(command + options + ["--", binary, "serve"], env=kept, capture_output=True, text=True)
    try:
        with open(report) as file:
            judged = json.load(file)
    except (OSError, ValueError):
        print(ran.stdout[-1500:], ran.stderr[-1500:])
        print("FAIL: the kit left no report")
        return 1
    for requirement in judged["requirements"]:
        if requirement["status"] == "FAIL":
            said = [(test.get("message") or "").strip().splitlines()[-3:] for test in requirement["tests"] if test["status"] == "FAIL"]
            print(f"  FAIL {requirement['id']} ({requirement['tier']}): {said}"[:900])
    for tier, counts in judged["verdict"]["tier_counts"].items():
        print(f"  {tier}: " + ", ".join(f"{count} {status}" for status, count in counts.items() if count))
    skipped = [r["id"] for r in judged["requirements"] if r["status"] != "PASS" and r["tier"] == "MANDATORY"]
    print(f"  mandatory and not passed: {skipped}; the model was asked {len(server.requests)} times; the report is {report}")
    conformant = judged["verdict"]["conformant"]
    print("PASS" if conformant else "FAIL")
    return 0 if conformant else 1


if __name__ == "__main__":
    sys.exit(main())
