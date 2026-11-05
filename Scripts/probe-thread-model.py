#!/usr/bin/env python3
"""Probe `threads.model` (roadmap 0195) through the real binary, a PTY and a local fake provider.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-thread-model.py .build/release/ask

With `threads.model` "anthropic/claude-probe-thread", main keeps its model while a thread's requests, and the request for its
summary, go to that one. A model that does not resolve (a provider with no key) refuses `/thread`, saying why, and main goes on.
Hermetic.
"""
import importlib.util
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
spec = importlib.util.spec_from_file_location("fold_probe", os.path.join(HERE, "probe-folding.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
checks = []


def check(label, condition):
    probe.check(label, condition)
    checks.append(label)


def session(model, script):
    root = tempfile.mkdtemp()
    project, config, state = root + "/project", root + "/config", root + "/state"
    os.makedirs(project)
    os.makedirs(config + "/ask")
    with open(config + "/ask/config.json", "w") as file:
        json.dump({"ui": {"inputPrefix": "ask> "}, "threads": {"names": "numbered", "model": model}}, file)
    server = probe.agent.Server(script)
    environment = probe.agent.environment(state, server.url, config=config)
    environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
    for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID", "OPENROUTER_API_KEY"):
        environment.pop(key, None)
    return project, environment, server


def run(model, script, body):
    project, environment, server = session(model, script)
    terminal = None
    try:
        terminal = probe.Terminal(project, environment, rows=40)
        terminal.until(lambda: "ask>" in terminal.text())
        body(terminal, server)
    except AssertionError:
        if terminal:
            print(terminal.text(), file=sys.stderr)
        raise
    finally:
        if terminal:
            terminal.close()
        server.httpd.shutdown()


def chosen(terminal, server):
    terminal.send(b"hello\r")
    terminal.until(lambda: "MAIN ONE" in terminal.text())
    terminal.send(b"/thread look around\r")
    terminal.until(lambda: "merged · look around" in terminal.text())
    models = [request["body"].get("model") for request in server.requests]
    check("main keeps its own model", models[0] != "claude-probe-thread")
    check("the thread works with threads.model", models[1] == "claude-probe-thread")
    check("and writes its summary with it", len(models) > 2 and models[2] == "claude-probe-thread"
          and "merging back" in json.dumps(server.requests[2]["body"]))


def unknown(terminal, server):
    terminal.send(b"/thread look around\r")
    terminal.until(lambda: "Cannot start a thread" in terminal.text())
    check("a model that does not resolve refuses the thread, saying why",
          "threads.model" in terminal.text() and "openrouter" in terminal.text() and not server.requests
          and "started here" not in terminal.text())
    terminal.send(b"hello\r")
    terminal.until(lambda: "MAIN ONE" in terminal.text())
    check("and main goes on", len(server.requests) == 1)


def main():
    turn = probe.agent.turn
    run("anthropic/claude-probe-thread", [
        turn([("text", "MAIN ONE")], "end_turn"),
        turn([("text", "THREAD DONE")], "end_turn"),
        turn([("text", "THREAD SUMMARY")], "end_turn"),
    ], chosen)
    run("openrouter/some-model", [turn([("text", "MAIN ONE")], "end_turn")], unknown)
    print(f"{len(checks)} checks passed")


if __name__ == "__main__":
    main()
