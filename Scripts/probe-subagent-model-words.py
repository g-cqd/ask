#!/usr/bin/env python3
"""Probe the model-assisted resolution of a definition's model word (roadmap 0063 phase 4, ADR-0146) through the real binary, a PTY and
a local fake provider.

Scripts/probe-subagent-model-words.py .build/release/ask

A definition asks for "Storyteller", which no listed id matches. The connection's cheap listed model is asked which listed id that
means, given the word and the ids only, and answers one; the subagent runs on it. A second session asks nothing: the answer was kept.
Hermetic.
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
TASK = {"task": "Tell it", "context": "Nothing else.", "done": "Say it.", "agent": "teller"}
ASKED = "A configuration file names a model as"


def check(label, condition):
    probe.check(label, condition)
    checks.append(label)


def main():
    root = tempfile.mkdtemp()
    config = root + "/config"
    project = tempfile.mkdtemp(prefix="probe-subagent-model-words-", dir=os.path.join(HERE, "..", ".build"))
    os.makedirs(config + "/ask/agents")
    with open(config + "/ask/config.json", "w") as file:
        json.dump({"ui": {"inputPrefix": "ask> "}, "threads": {"names": "numbered"}, "agents": {"enabled": True}}, file)
    with open(config + "/ask/agents/teller.md", "w") as file:
        file.write("---\ndescription: Tells stories.\nmodel: Storyteller\n---\nTELLER\n")
    catalog = [{"id": model, "max_input_tokens": 200000, "max_tokens": 64000}
               for model in ("claude-sonnet-5-5", "claude-haiku-probe", "claude-probe-child")]
    turn = probe.agent.turn
    resolutions = []

    def route(body):
        if ASKED not in json.dumps(body):
            return None
        resolutions.append(body)
        return turn([("text", "claude-probe-child")], "end_turn")

    script = [turn([("call", "a1", "agent", TASK)], "tool_use"), turn([("text", "TOLD")], "end_turn"),
              turn([("text", "SUMMARY")], "end_turn"), turn([("text", "MAIN DONE")], "end_turn")]
    server = probe.agent.Server(script + script, catalog=catalog, route=route)
    try:
        for run in (1, 2):
            environment = probe.agent.environment(root + f"/state{run}", server.url, config=config)
            environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
            for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
                environment.pop(key, None)
            terminal = probe.Terminal(project, environment, rows=40)
            try:
                terminal.until(lambda: "ask>" in terminal.text())
                start = len(server.requests)
                terminal.send(b"tell a story\r")
                terminal.until(lambda: "MAIN DONE" in terminal.text())
                models = [request["body"].get("model") for request in server.requests[start:]]
                if run == 1:
                    asked = json.dumps(resolutions[0]) if resolutions else ""
                    check("the cheap listed model is asked, with the word and the ids",
                          len(resolutions) == 1 and resolutions[0].get("model") == "claude-haiku-probe"
                          and "Storyteller" in asked and "claude-probe-child" in asked and "TELLER" not in asked)
                    check(f"and the subagent runs on the id it answered: {models}", "claude-probe-child" in models)
                else:
                    check("a second session asks nothing: the answer was kept", len(resolutions) == 1
                          and "claude-probe-child" in models)
            finally:
                terminal.close()
    except AssertionError:
        raise
    finally:
        server.httpd.shutdown()
        shutil.rmtree(project, ignore_errors=True)
    print(f"{len(checks)} checks passed")


if __name__ == "__main__":
    main()
