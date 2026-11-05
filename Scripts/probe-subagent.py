#!/usr/bin/env python3
"""Probe subagents (roadmap 0063, ADR-0146) through the real binary, a PTY and a local fake provider.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-subagent.py .build/release/ask

Off, the default: no request offers the `agent` tool. On (`agents.enabled`): main's model calls it; the subagent's first request holds
its task and nothing of main's conversation, and offers no `agent` tool (depth 1); its write is refused, since subagents are read-only;
its summary comes back as the call's result, labelled as a subagent's report, and main goes on. Hermetic.
"""
import importlib.util
import json
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
spec = importlib.util.spec_from_file_location("fold_probe", os.path.join(HERE, "probe-folding.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
checks = []
TASK = {"task": "Write the word ok to made.txt", "context": "The project root is the working directory.",
        "done": "Say whether the file was written."}


def check(label, condition):
    probe.check(label, condition)
    checks.append(label)


def tools(request):
    return [tool["name"] for tool in request["body"].get("tools", [])]


def run(agents, script, body):
    with tempfile.TemporaryDirectory() as root:
        config, state = root + "/config", root + "/state"
        # The project outside the temporary directories, which the sandbox's base profile always lets commands write: there a
        # read-only subagent's write would pass, and the check would mean nothing.
        project = tempfile.mkdtemp(prefix="probe-subagent-", dir=os.path.join(HERE, "..", ".build"))
        os.makedirs(config + "/ask")
        settings = {"ui": {"inputPrefix": "ask> "}, "threads": {"names": "numbered"}}
        if agents:
            settings["agents"] = {"enabled": True}
        with open(config + "/ask/config.json", "w") as file:
            json.dump(settings, file)
        server = probe.agent.Server(script)
        environment = probe.agent.environment(state, server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
        for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
            environment.pop(key, None)
        terminal = None
        try:
            terminal = probe.Terminal(project, environment, rows=40)
            terminal.until(lambda: "ask>" in terminal.text())
            body(terminal, server, project)
        except AssertionError:
            if terminal:
                print(terminal.text(), file=sys.stderr)
            raise
        finally:
            if terminal:
                terminal.close()
            server.httpd.shutdown()
            shutil.rmtree(project, ignore_errors=True)


def off(terminal, server, project):
    terminal.send(b"hello\r")
    terminal.until(lambda: "MAIN ONE" in terminal.text())
    check("off, the default: no agent tool is offered", "agent" not in tools(server.requests[0]))


def on(terminal, server, project):
    terminal.send(b"remember MAIN-SECRET, then delegate\r")
    terminal.until(lambda: "MAIN DONE" in terminal.text())
    first, child = server.requests[0], server.requests[1]
    check("on, main's model is offered the agent tool", "agent" in tools(first))
    sent = json.dumps(child["body"])
    check("the subagent's first request holds its task and nothing of main's conversation",
          "Write the word ok to made.txt" in sent and "MAIN-SECRET" not in sent)
    check("and offers no agent tool: a subagent cannot start one", "agent" not in tools(child))
    check("its write is refused: subagents are read-only", not os.path.exists(os.path.join(project, "made.txt")))
    after = json.dumps(server.requests[-1]["body"])
    check("its summary comes back as the call's result, labelled as a subagent's report",
          "subagent thread-1's report" in after and "CHILD SUMMARY" in after)


def main():
    turn = probe.agent.turn
    run(False, [turn([("text", "MAIN ONE")], "end_turn")], off)
    run(True, [
        turn([("call", "a1", "agent", TASK)], "tool_use"),          # 0 main asks for a subagent
        turn([("tool", "c1", "echo ok > made.txt")], "tool_use"),   # 1 the subagent tries to write
        turn([("text", "CHILD COULD NOT WRITE")], "end_turn"),      # 2 and says so
        turn([("text", "CHILD SUMMARY: read-only")], "end_turn"),   # 3 its summary
        turn([("text", "MAIN DONE")], "end_turn"),                  # 4 main goes on
    ], on)
    print(f"{len(checks)} checks passed")


if __name__ == "__main__":
    main()
