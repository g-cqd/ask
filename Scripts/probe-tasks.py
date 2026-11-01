#!/usr/bin/env python3
"""Does the model keep a task list through the `tasks` tool, kept beside the session? (roadmap 0179, ADR-0140)

Usage: Scripts/probe-tasks.py .build/release/ask

A local fake Anthropic server has the model add two tasks, the second blocked by the first, start the first and list them; the probe reads
the tool results from the next request. No network, no real credentials. Two runs:

  session    the tool is offered, the list is never sent unasked, the results read "t1 [in progress] …" and "t2 [open, blocked by t1] …",
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

MAKE = [
    ("call", "c1", "tasks", {"action": "add", "title": "write the parser", "detail": "recursive descent"}),
    ("call", "c2", "tasks", {"action": "add", "title": "ship it", "blocked_by": "t1"}),
    ("call", "c3", "tasks", {"action": "start", "id": "t1"}),
    ("call", "c4", "tasks", {"action": "list"}),
]
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
        bad = check("the list reads as made: %r" % (seen[-1:]), seen[-1:] == [LISTING], bad)
        lists = files(state, ".tasks")
        sessions = files(state, ".jsonl")
        beside = len(lists) == 1 and len(sessions) == 1 and lists[0][:-6] == sessions[0][:-6]
        bad = check("one .tasks file beside the session", beside, bad)
        records = [json.loads(line) for line in open(lists[0])] if lists else []
        bad = check("kept as its changes: %s" % [record.get("kind") for record in records],
                    [record.get("kind") for record in records] == ["add", "add", "state"], bad)

    with tempfile.TemporaryDirectory() as root:
        project, state, configuration = root + "/project", root + "/state", root + "/config"
        os.makedirs(project)
        os.makedirs(configuration + "/ask")
        with open(configuration + "/ask/config.json", "w") as file:
            json.dump({"taskScope": "workspace"}, file)
        run(project, state, configuration, [agent.turn(MAKE[:3], "tool_use")])
        requests = run(project, state, configuration, [agent.turn([("call", "c9", "tasks", {"action": "list"})], "tool_use")])
        print("workspace")
        seen = results(requests[1]) if len(requests) > 1 else []
        bad = check("a second session lists the first one's tasks: %r" % seen, seen == [LISTING], bad)
        bad = check("kept in tasks.ask, no .tasks file", len(files(state, "tasks.ask")) == 1 and not files(state, ".tasks"), bad)
    return 1 if bad else 0


sys.exit(main())
