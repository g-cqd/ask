#!/usr/bin/env python3
"""Probe threads named by a provider's model (`threads.names` "model", `threads.namesModel`; roadmap 0195, note n20) through the real
binary, a PTY and a local fake provider.

Scripts/probe-thread-model-names.py .build/release/ask

With no `namesModel`, the conversation's own model is asked for the name, from the task, and the thread is listed by the name it gives.
With `namesModel` "anthropic/claude-probe-namer", that model is asked. The naming request is answered by its content (it races the
thread's own turns), and the thread works meanwhile. Hermetic: no window, credentials or clipboard.
"""
import importlib.util
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import probe_runner_list as runners  # noqa: E402
spec = importlib.util.spec_from_file_location("fold_probe", os.path.join(HERE, "probe-folding.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
checks = []


def check(label, condition):
    probe.check(label, condition)
    checks.append(label)


def is_naming(body):
    # Anywhere in it: the Claude provider carries instructions in the first user message.
    return "Reply with a name of two to four" in json.dumps(body)


def run(names_model, name):
    with tempfile.TemporaryDirectory() as root:
        project, config, state = root + "/project", root + "/config", root + "/state"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        threads = {"names": "model"}
        if names_model:
            threads["namesModel"] = names_model
        with open(config + "/ask/config.json", "w") as file:
            json.dump({"ui": {"inputPrefix": "ask> "}, "threads": threads}, file)
        turn = probe.agent.turn
        named = []

        def route(body):
            if not is_naming(body):
                return None
            named.append(body)
            return turn([("text", name)], "end_turn")

        server = probe.agent.Server([turn([("tool", "c1", "sleep 30")], "tool_use")], route=route)
        environment = probe.agent.environment(state, server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
        for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
            environment.pop(key, None)
        terminal = None
        try:
            terminal = probe.Terminal(project, environment, rows=40)
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.send(b"/thread tidy up the documentation folder\r")
            # Listed once the status line counts it: /jobs before that finds nothing to show.
            terminal.until(lambda: "started here" in terminal.text() and "1 thread" in terminal.text())
            runners.show(terminal)
            terminal.until(lambda: runners.row(terminal, name) is not None)
            asked = named[0] if named else {}
            label = names_model or "the conversation's model"
            check(f"{label}: asked from the task, and the thread is listed by the name it gives",
                  "tidy up the documentation folder" in json.dumps(asked.get("messages", ""))
                  and runners.state(terminal, name) == "running")
            return asked
        except AssertionError:
            if terminal:
                print(terminal.text(), file=sys.stderr)
            raise
        finally:
            if terminal:
                terminal.close()
            server.httpd.shutdown()


def main():
    own = run(None, "docs tidy")
    chosen = run("anthropic/claude-probe-namer", "folder cleanup")
    check("namesModel's model is the one asked", chosen.get("model") == "claude-probe-namer" and own.get("model") != "claude-probe-namer")
    print(f"{len(checks)} checks passed")


if __name__ == "__main__":
    main()
