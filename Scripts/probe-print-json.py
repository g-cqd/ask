#!/usr/bin/env python3
"""Roadmap 0234: `ask -p --json` writes every line of standard output as one JSON object with a version: the text, the tool call with
its input as JSON, the tool's result, each response, the finish and an end line naming the session; nothing else on standard output.

Scripts/probe-print-json.py .build/release/ask
"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("agent_probe", os.path.join(here, "probe-agent-run.py"))
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)


def main():
    binary = os.path.abspath(sys.argv[1])
    root = tempfile.mkdtemp()
    project = os.path.join(root, "project")
    os.mkdir(project)
    server = agent.Server([agent.turn([("tool", "t1", "echo json-probe")], "tool_use"),
                           agent.turn([("text", "Done: json-probe.")], "end_turn")])
    run = subprocess.run([binary, "-p", "Run it.", "--json", "--yes"], cwd=project, env=agent.environment(os.path.join(root, "state"), server.url),
                         capture_output=True, text=True, timeout=120)
    lines = [line for line in run.stdout.split("\n") if line]
    try:
        parsed = [json.loads(line) for line in lines]
    except json.JSONDecodeError as error:
        parsed = []
        print("not JSON:", error)
    types = [p.get("type") for p in parsed]
    call = next((p for p in parsed if p.get("type") == "tool_call"), {})
    result = next((p for p in parsed if p.get("type") == "tool_result"), {})
    end = parsed[-1] if parsed else {}
    results = [
        agent.check("exits 0", run.returncode == 0, run.stderr[-500:]),
        agent.check("every line is JSON with v 1", bool(parsed) and len(parsed) == len(lines) and all(p.get("v") == 1 for p in parsed), run.stdout[:500]),
        agent.check("the tool call's input is JSON", call.get("input", {}).get("command") == "echo json-probe", call),
        agent.check("the tool's result carries its output", "json-probe" in result.get("content", ""), result),
        agent.check("the text arrives as text events", "".join(p.get("text", "") for p in parsed if p.get("type") == "text") == "Done: json-probe.", types),
        agent.check("two responses, a finish, and the end last", types.count("response") == 2 and "finished" in types and end.get("type") == "end", types),
        agent.check("the end names the session and the tokens", end.get("session", "").endswith(".jsonl") and end.get("usage", {}).get("output", 0) > 0, end),
    ]
    server.httpd.shutdown()
    print("PASS" if all(results) else "FAIL")
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
