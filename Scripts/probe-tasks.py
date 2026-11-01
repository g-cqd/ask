#!/usr/bin/env python3
"""Does the model keep a task list through the `tasks` tool, kept beside the session? (roadmap 0179, ADR-0140)

Usage: Scripts/probe-tasks.py .build/release/ask

A local fake Anthropic server has the model add two tasks, the second blocked by the first, start the first and list them; the probe reads
the tool results from the next request. No network, no real credentials. Two runs:

  session    the tool is offered, the list is never sent unasked, one call (ADR-0141) adds both tasks, starts one and reads them,
             and `<session>.tasks` beside the session holds the changes, one record each;
  workspace  with `taskScope: "workspace"`, a second session lists the first one's tasks from `tasks.ask`.

It exits 0 when all of that holds, 1 when something does not, 2 when the probe could not see the results.
"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
BINARY = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".build/release/ask")
sys.argv = [sys.argv[0], BINARY]
spec = importlib.util.spec_from_file_location("agent_probe", os.path.join(HERE, "probe-agent-run.py"))
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)

# One call (ADR-0141): two adds, the second waiting on the first through @1, the first started, then a read.
MAKE = [
    ("call", "c1", "tasks", {"changes": [
        {"op": "add", "title": "write the parser", "detail": "recursive descent"},
        {"op": "add", "title": "ship it", "blocked_by": "@1"},
        {"op": "state", "ids": "@1", "state": "in_progress"}], "read": {}}),
]
ANSWER = "added t1–t2 (2) · in progress t1\n\n"
LISTING = "t1 [in progress] write the parser\nt2 [open, blocked by t1] ship it"


def results(request):
    """The tool results a request carries, as text."""
    texts = []
    for message in request["body"]["messages"]:
        for block in message["content"] if isinstance(message["content"], list) else []:
            if block.get("type") == "tool_result":
                content = block.get("content")
                texts.append(content if isinstance(content, str) else "".join(part.get("text", "") for part in content or []))
    return texts


def run(project, state, configuration, turns):
    server = agent.Server(turns + [agent.turn([("text", "done")], "end_turn")])
    environment = agent.environment(state, server.url, config=configuration)
    subprocess.run([BINARY, "-p", "plan it"], cwd=project, env=environment, capture_output=True, text=True, timeout=60,
                   stdin=subprocess.DEVNULL)
    return server.requests


def files(state, suffix):
    return [os.path.join(top, name) for top, _, names in os.walk(state) for name in names if name.endswith(suffix)]


def check(title, ok, bad):
    print("  %-5s %s" % ("ok" if ok else "WRONG", title))
    return bad + (not ok)


def main():
    bad = 0
    with tempfile.TemporaryDirectory() as root:
        project, state, configuration = root + "/project", root + "/state", root + "/config"
        os.makedirs(project)
        os.makedirs(configuration + "/ask")
        requests = run(project, state, configuration, [agent.turn(MAKE, "tool_use")])
        if len(requests) < 2:
            print("the probe could not read the tool results")
            return 2
        print("session")
        tools = [tool["name"] for tool in requests[0]["body"].get("tools", [])]
        bad = check("the tasks tool is offered", "tasks" in tools, bad)
        bad = check("nothing of the list is sent unasked", "write the parser" not in json.dumps(requests[0]["body"]), bad)
        seen = results(requests[1])
        bad = check("one call makes the batch and reads it: %r" % (seen[-1:]), seen[-1:] == [ANSWER + LISTING], bad)
        lists = files(state, ".tasks")
        sessions = files(state, ".jsonl")
        beside = len(lists) == 1 and len(sessions) == 1 and lists[0][:-6] == sessions[0][:-6]
        bad = check("one .tasks file beside the session", beside, bad)
        records = [json.loads(line) for line in open(lists[0])] if lists else []
        kinds = [record.get("kind") for record in records]
        inner = [change.get("kind") for change in records[0].get("changes", [])] if records else []
        bad = check("kept as one record of its changes: %s %s" % (kinds, inner), kinds == ["batch"] and inner == ["add", "add", "state"], bad)

    with tempfile.TemporaryDirectory() as root:
        project, state, configuration = root + "/project", root + "/state", root + "/config"
        os.makedirs(project)
        os.makedirs(configuration + "/ask")
        with open(configuration + "/ask/config.json", "w") as file:
            json.dump({"taskScope": "workspace"}, file)
        run(project, state, configuration, [agent.turn(MAKE, "tool_use")])
        requests = run(project, state, configuration, [agent.turn([("call", "c9", "tasks", {"read": {}})], "tool_use")])
        print("workspace")
        seen = results(requests[1]) if len(requests) > 1 else []
        bad = check("a second session lists the first one's tasks: %r" % seen, seen == [LISTING], bad)
        bad = check("kept in tasks.ask, no .tasks file", len(files(state, "tasks.ask")) == 1 and not files(state, ".tasks"), bad)
    return 1 if bad else 0


sys.exit(main())
