#!/usr/bin/env python3
"""Does a command the model runs inherit ask's environment, secrets included? (roadmap 0072)

Usage: Scripts/probe-bash-environment.py .build/release/ask

A local fake Anthropic server asks `bash` to echo two variables that hold a stand-in key and a stand-in token; the probe reads the tool result
that comes back in the second request. No network, no real credentials. It exits 1 while the secrets are exposed, which is the state it was
written to show (2026-10-25), and 0 once they are not: it is the acceptance probe of 0072, red until that work lands.
"""
import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
BINARY = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".build/release/ask")
sys.argv = [sys.argv[0], BINARY]
spec = importlib.util.spec_from_file_location("agent_probe", os.path.join(HERE, "probe-agent-run.py"))
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)

KEY, TOKEN = "sk-ant-api-ENVPROBE-0001", "token-ENVPROBE-0002"


def result(body, name):
    found = re.search(r"%s=\[([^\]]*)\]" % name, body)
    return found.group(1) if found else None


def main():
    with tempfile.TemporaryDirectory() as root:
        project = root + "/project"
        os.makedirs(project)
        command = 'echo "KEY=[$ANTHROPIC_API_KEY] TOKEN=[$MY_SERVICE_TOKEN] HOME=[$HOME]"'
        server = agent.Server([agent.turn([("tool", "t1", command)], "tool_use"), agent.turn([("text", "done")], "end_turn")])
        environment = agent.environment(root + "/state", server.url)
        environment.update(ANTHROPIC_API_KEY=KEY, MY_SERVICE_TOKEN=TOKEN)
        subprocess.run([BINARY, "-p", "run it"], cwd=project, env=environment, capture_output=True, text=True, timeout=60,
                       stdin=subprocess.DEVNULL)
        if len(server.requests) < 2:
            print("FAIL: the tool result never reached a second request")
            return 2
        # Only the tool result block of the second request: the command text itself names the variables.
        blocks = [block for message in server.requests[1]["body"]["messages"] for block in (message["content"] if isinstance(message["content"], list) else [])
                  if block.get("type") == "tool_result"]
        text = json.dumps(blocks)
        seen = {"ANTHROPIC_API_KEY": result(text, "KEY"), "MY_SERVICE_TOKEN": result(text, "TOKEN"), "HOME": result(text, "HOME")}
        exposed = [name for name, value in (("ANTHROPIC_API_KEY", KEY), ("MY_SERVICE_TOKEN", TOKEN)) if seen[name] == value]
        for name in ("ANTHROPIC_API_KEY", "MY_SERVICE_TOKEN"):
            print(("EXPOSED  " if name in exposed else "withheld ") + name)
        print("HOME is %s (a command still has the ordinary environment)" % ("set" if seen["HOME"] else "MISSING"))
        if not seen["HOME"]:
            return 2
        return 1 if exposed else 0


sys.exit(main())
