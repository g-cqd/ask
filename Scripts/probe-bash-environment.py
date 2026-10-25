#!/usr/bin/env python3
"""Does a command the model runs inherit ask's secrets? (roadmap 0072, ADR-0106)

Usage: Scripts/probe-bash-environment.py .build/release/ask

A local fake Anthropic server asks `bash` to echo seven variables, and the probe reads the tool result that comes back in the second request. No network,
no real credentials. Two runs:

  defaults   the variables ask itself reads credentials from are withheld (the Anthropic key, a preset's key variable, a variable providers.json
             names for a key, a variable an MCP server's settings name, and the ASK_ prefix); a variable ask does not read
             (MY_SERVICE_TOKEN) and HOME are inherited;
  configured `environment.pass` lets a preset's key variable through, `environment.withhold` hides MY_SERVICE_TOKEN, and the Anthropic key
             stays withheld.

It exits 0 when both runs are as above, 1 when a secret is exposed or a setting does not take, 2 when the probe could not see the result.
Before ADR-0106 every variable was inherited and this exited 1.
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

VALUES = {
    "ANTHROPIC_API_KEY": "sk-ant-api-ENVPROBE-0001", "BASETEN_API_KEY": "preset-ENVPROBE-0002", "GW_KEY": "gateway-ENVPROBE-0003",
    "ASK_PROBE_VALUE": "ask-ENVPROBE-0004", "MY_SERVICE_TOKEN": "token-ENVPROBE-0005",
    "MCP_PROBE_TOKEN": "mcp-ENVPROBE-0006",
}
COMMAND = ('echo "ANTHROPIC_API_KEY=[$ANTHROPIC_API_KEY] BASETEN_API_KEY=[$BASETEN_API_KEY] GW_KEY=[$GW_KEY] '
           'ASK_PROBE_VALUE=[$ASK_PROBE_VALUE] MY_SERVICE_TOKEN=[$MY_SERVICE_TOKEN] MCP_PROBE_TOKEN=[$MCP_PROBE_TOKEN] HOME=[$HOME]"')


def run(config):
    """What a command saw, by name, for a run with this `config.json` (or none)."""
    with tempfile.TemporaryDirectory() as root:
        project, configuration = root + "/project", root + "/config"
        os.makedirs(project)
        os.makedirs(configuration + "/ask")
        with open(configuration + "/ask/providers.json", "w") as file:
            json.dump({"providers": {"gw": {"api": "openai-completions", "baseUrl": "http://127.0.0.1:1/v1", "apiKey": "${GW_KEY}"}}}, file)
        # A server that is switched off starts nothing, and its settings still name a variable ask reads.
        config = dict(config or {}, mcp={"off": {"command": "/nonexistent/mcp-server", "enabled": False, "env": {"T": "${MCP_PROBE_TOKEN}"}}})
        with open(configuration + "/ask/config.json", "w") as file:
            json.dump(config, file)
        server = agent.Server([agent.turn([("tool", "t1", COMMAND)], "tool_use"), agent.turn([("text", "done")], "end_turn")])
        environment = agent.environment(root + "/state", server.url, config=configuration)
        environment.update(VALUES)
        subprocess.run([BINARY, "-p", "run it"], cwd=project, env=environment, capture_output=True, text=True, timeout=60,
                       stdin=subprocess.DEVNULL)
        if len(server.requests) < 2:
            return None
        # Only the tool result of the second request: the command text itself names every variable.
        blocks = [block for message in server.requests[1]["body"]["messages"]
                  for block in (message["content"] if isinstance(message["content"], list) else []) if block.get("type") == "tool_result"]
        text = json.dumps(blocks)
        return {name: (re.search(r"%s=\[([^\]]*)\]" % name, text) or [None, None])[1] for name in list(VALUES) + ["HOME"]}


def report(title, seen, expectations):
    print(title)
    bad = 0
    for name, should in expectations.items():
        got = seen[name]
        reached = got == VALUES.get(name)
        ok = reached == should
        bad += not ok
        print("  %-9s %-17s %s" % ("ok" if ok else "WRONG", name, "given to the command" if reached else "withheld"))
    return bad


def main():
    defaults = run(None)
    if defaults is None or not defaults["HOME"]:
        print("the probe could not read a tool result from the default run (or a command lost HOME)")
        return 2
    bad = report("defaults", defaults, {
        "ANTHROPIC_API_KEY": False, "BASETEN_API_KEY": False, "GW_KEY": False, "ASK_PROBE_VALUE": False, "MCP_PROBE_TOKEN": False,
        "MY_SERVICE_TOKEN": True})
    configured = run({"environment": {"pass": ["BASETEN_API_KEY"], "withhold": ["MY_SERVICE_TOKEN"]}})
    if configured is None or not configured["HOME"]:
        print("configured: the run did not complete (a binary that does not know the `environment` setting refuses its file)")
        return 1
    bad += report("configured: pass BASETEN_API_KEY, withhold MY_SERVICE_TOKEN", configured, {
        "ANTHROPIC_API_KEY": False, "BASETEN_API_KEY": True, "GW_KEY": False, "ASK_PROBE_VALUE": False, "MCP_PROBE_TOKEN": False,
        "MY_SERVICE_TOKEN": False})
    print("HOME is given in both (a command still has the ordinary environment)")
    return 1 if bad else 0


sys.exit(main())
