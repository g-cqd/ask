#!/usr/bin/env python3
"""Probe other harnesses' agent definitions (roadmap 0063 phase 3, ADR-0146, `agents.otherHarnesses`) through the real binary, a PTY and
a local fake provider.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-subagent-harnesses.py .build/release/ask

In a throwaway home, one definition each in Claude's (`.claude/agents/*.md`), Codex's (`.codex/agents/*.toml`) and Copilot's
(`.copilot/agents/*.agent.md`) folders: with `agents.otherHarnesses` unset the agent tool names none of them; on, it names all three.
Hermetic: HOME is the probe's own.
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
FILES = {
    ".claude/agents/claude-helper.md": "---\ndescription: From Claude.\n---\nCLAUDE-INSTRUCTIONS\n",
    ".codex/agents/codex-helper.toml": 'description = "From Codex."\ndeveloper_instructions = "CODEX-INSTRUCTIONS"\n',
    ".copilot/agents/copilot-helper.agent.md": "---\ndescription: From Copilot.\n---\nCOPILOT-INSTRUCTIONS\n",
}


def check(label, condition):
    probe.check(label, condition)
    checks.append(label)


def offered(other_harnesses):
    root = tempfile.mkdtemp()
    config, state = root + "/config", root + "/state"
    project = tempfile.mkdtemp(prefix="probe-subagent-harnesses-", dir=os.path.join(HERE, "..", ".build"))
    os.makedirs(config + "/ask")
    agents = {"enabled": True}
    if other_harnesses:
        agents["otherHarnesses"] = True
    with open(config + "/ask/config.json", "w") as file:
        json.dump({"ui": {"inputPrefix": "ask> "}, "agents": agents}, file)
    server = probe.agent.Server([probe.agent.turn([("text", "ANSWER")], "end_turn")])
    environment = probe.agent.environment(state, server.url, config=config)
    environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
    for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
        environment.pop(key, None)
    for path, text in FILES.items():
        full = os.path.join(environment["HOME"], path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w") as file:
            file.write(text)
    terminal = None
    try:
        terminal = probe.Terminal(project, environment, rows=40)
        terminal.until(lambda: "ask>" in terminal.text())
        terminal.send(b"hello\r")
        terminal.until(lambda: "ANSWER" in terminal.text())
        tool = next(t for t in server.requests[0]["body"]["tools"] if t["name"] == "agent")
        return tool["description"]
    finally:
        if terminal:
            terminal.close()
        server.httpd.shutdown()
        shutil.rmtree(project, ignore_errors=True)


def main():
    off = offered(False)
    check("unset, no other harness's definition is offered", not any(word in off for word in ("claude-helper", "codex-helper", "copilot-helper")))
    on = offered(True)
    check("on, Claude's, Codex's and Copilot's are named",
          "claude-helper: From Claude." in on and "codex-helper: From Codex." in on and "copilot-helper: From Copilot." in on)
    print(f"{len(checks)} checks passed")


if __name__ == "__main__":
    main()
