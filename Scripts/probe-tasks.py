#!/usr/bin/env python3
"""Does the model keep a task list through the `tasks` tool, kept beside the session? (roadmap 0179, ADR-0140)

Usage: ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-tasks.py .build/release/ask

A local fake Anthropic server has the model add two tasks, the second blocked by the first, start the first and list them; the probe reads
the tool results from the next request. No network, no real credentials. Three runs:

  session    the tool is offered, the list is never sent unasked, one call (ADR-0141) adds both tasks, starts one and reads them,
             and `<session>.tasks` beside the session holds the changes, one record each;
  workspace  with `taskScope: "workspace"`, a second session lists the first one's tasks from `tasks.ask`;
  encrypted  with `ASK_SESSION_ENCRYPTION` not off, setting up encrypted sessions in a PTY writes `<session>.tasks` framed (`ASKF`)
             with no task titles in clear, and `--continue` reopens it and reads the tasks back through the tool.

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
fold_spec = importlib.util.spec_from_file_location("fold_probe", os.path.join(HERE, "probe-folding.py"))
fold = importlib.util.module_from_spec(fold_spec)
fold_spec.loader.exec_module(fold)

# One call (ADR-0141): two adds, the second waiting on the first through @1, the first started, then a read.
MAKE = [
    ("call", "c1", "tasks", {"changes": [
        {"op": "add", "title": "write the parser", "detail": "recursive descent"},
        {"op": "add", "title": "ship it", "blocked_by": "@1"},
        {"op": "state", "ids": "@1", "state": "in_progress"}], "read": {}}),
]
ANSWER = "added t1–t2 (2) · in progress t1\n\n"
LISTING = "t1 [in progress] write the parser\nt2 [open, blocked by t1] ship it"
PASSWORD = "a long enough password"


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


def choose(terminal, question, number):
    terminal.until(lambda: question in terminal.text())
    for key in (str(number).encode(), b"\r"):
        terminal.send(key)
        fold.time.sleep(0.15)
    terminal.until(lambda: question not in terminal.text())


def type_hidden(terminal, prompt, text):
    terminal.until(lambda: prompt in terminal.text())
    received = terminal.text().count("Received (hidden).")
    terminal.send(text.encode() + b"\r")
    terminal.until(lambda: terminal.text().count("Received (hidden).") > received)


def probe_encrypted(bad):
    print("encrypted")
    with tempfile.TemporaryDirectory() as root:
        project, state, configuration = root + "/project", root + "/state", root + "/config"
        os.makedirs(project)
        os.makedirs(configuration + "/ask")
        with open(configuration + "/ask/config.json", "w") as file:
            json.dump({"ui": {"inputPrefix": "ask> "}}, file)
        server = agent.Server([
            agent.turn(MAKE, "tool_use"),
            agent.turn([("text", "PLANNED")], "end_turn"),
            agent.turn([("call", "c2", "tasks", {"read": {}})], "tool_use"),
            agent.turn([("text", "REOPENED")], "end_turn"),
        ])
        environment = agent.environment(state, server.url, config=configuration)
        environment.pop("ASK_SESSION_ENCRYPTION", None)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")

        first = fold.Terminal(project, environment)
        choose(first, "Encrypt your ask sessions?", 1)
        choose(first, "Keep the key in your keychain", 2)
        type_hidden(first, "Password:", PASSWORD)
        type_hidden(first, "Again:", PASSWORD)
        first.until(lambda: "Press Return" in first.text())
        first.send(b"\r")
        first.until(lambda: "Press Return" not in first.text() and "ask>" in first.text())
        first.send(b"plan it\r")
        first.until(lambda: "PLANNED" in first.text())
        first.close()

        lists = files(state, ".tasks")
        raw = open(lists[0], "rb").read() if lists else b""
        bad = check("the encrypted .tasks file is framed with ASKF", raw.startswith(b"ASKF"), bad)
        bad = check("no task title or detail is in the .tasks file in clear",
                    b"write the parser" not in raw and b"recursive descent" not in raw, bad)

        second = fold.Terminal(project, environment, resume=True)
        second.until(lambda: b"Password for your encrypted ask sessions:" in bytes(second.raw))
        second.send(PASSWORD.encode() + b"\r")
        second.until(lambda: "PLANNED" in second.text() and "ask>" in second.text())
        second.send(b"check tasks\r")
        second.until(lambda: "REOPENED" in second.text())
        second.close()

        seen = results(server.requests[3]) if len(server.requests) > 3 else []
        bad = check("reopened encrypted session reads the tasks back: %r" % (seen[-1:],), seen[-1:] == [LISTING], bad)
    return bad


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

    bad = probe_encrypted(bad)
    return 1 if bad else 0


sys.exit(main())
