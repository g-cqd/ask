#!/usr/bin/env python3
"""Probe agent definitions (roadmap 0063 phase 3, ADR-0146) through the real binary, a PTY and a local fake provider.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-subagent-definitions.py .build/release/ask

A definition in the person's own `agents` directory is named in the `agent` tool's description; a call naming it starts a subagent
whose first request holds the definition's instructions before its task, and whose tools are only those the definition keeps. Hermetic.
"""
import importlib.util
import json
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("fold_probe", os.path.join(HERE, "probe-folding.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
checks = []
TASK = {"task": "Look at the change", "context": "The diff is in HEAD.", "done": "Report what you found.", "agent": "reviewer"}


def check(label, condition):
    probe.check(label, condition)
    checks.append(label)


def tools(request):
    return [tool["name"] for tool in request["body"].get("tools", [])]


def main():
    root = tempfile.mkdtemp()
    config, state = root + "/config", root + "/state"
    project = tempfile.mkdtemp(prefix="probe-subagent-definitions-", dir=os.path.join(HERE, "..", ".build"))
    os.makedirs(config + "/ask/agents")
    with open(config + "/ask/config.json", "w") as file:
        json.dump({"ui": {"inputPrefix": "ask> "}, "threads": {"names": "numbered"}, "agents": {"enabled": True}}, file)
    with open(config + "/ask/agents/reviewer.md", "w") as file:
        file.write("---\ndescription: Reviews a change, reading only.\ntools: Read\n---\nREVIEWER-INSTRUCTIONS: be thorough.\n")
    turn = probe.agent.turn
    server = probe.agent.Server([
        turn([("call", "a1", "agent", TASK)], "tool_use"),
        turn([("text", "CHILD DONE")], "end_turn"),
        turn([("text", "CHILD SUMMARY")], "end_turn"),
        turn([("text", "MAIN DONE")], "end_turn"),
    ])
    environment = probe.agent.environment(state, server.url, config=config)
    environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
    for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
        environment.pop(key, None)
    terminal = None
    try:
        terminal = probe.Terminal(project, environment, rows=40)
        terminal.until(lambda: "ask>" in terminal.text())
        terminal.send(b"have it reviewed\r")
        terminal.until(lambda: "MAIN DONE" in terminal.text())
        offered = next(t for t in server.requests[0]["body"]["tools"] if t["name"] == "agent")
        check("the definition is named in the agent tool's description", "reviewer: Reviews a change" in offered["description"])
        child = json.dumps(server.requests[1]["body"])
        check("the subagent is told the definition's instructions before its task",
              "REVIEWER-INSTRUCTIONS" in child and child.index("REVIEWER-INSTRUCTIONS") < child.index("Look at the change"))
        check(f"and keeps only the tools the definition names: {tools(server.requests[1])}", tools(server.requests[1]) == ["read"])
    except AssertionError:
        if terminal:
            print(terminal.text(), file=sys.stderr)
        raise
    finally:
        if terminal:
            terminal.close()
        server.httpd.shutdown()
        shutil.rmtree(project, ignore_errors=True)
    print(f"{len(checks)} checks passed")


if __name__ == "__main__":
    main()
