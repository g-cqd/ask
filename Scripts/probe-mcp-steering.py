#!/usr/bin/env python3
"""Probe `@server:uri` in a message typed during a turn (roadmap 0067) through the real binary, a PTY, a local fake provider and the
fixture server in its `resources` mode.

Scripts/probe-mcp-steering.py .build/release/ask

A slow call to the fixture's echo holds the turn; meanwhile a steering message names `@fx:note://a`. The next request carries the
note's text after the typed line, and the screen shows the typed line alone.
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("mcp_screen", os.path.join(HERE, "probe-mcp-screen.py"))
saved = sys.argv
sys.argv = [saved[0], saved[1]]
ms = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ms)
sys.argv = saved
pp = ms.pp


def servers(project):
    return {"mcp": {"fx": {"command": "python3", "args": [ms.FIXTURE, "resources"]}}}


def main():
    binary = os.path.abspath(sys.argv[1])
    turns = [
        pp.probe.agent.turn([("call", "p1", "mcp__fx__echo", {"message": "hi", "slow": 4})], "tool_use"),
        pp.short_answer("Read it."),
    ]
    with pp.Session(binary, turns, settings=servers) as session:
        terminal = session.terminal
        ms.send(session, "Echo slowly.", "echo")
        ms.send(session, "Also look at @fx:note://a please", "Also look at")
        terminal.until(lambda: "Read it." in terminal.text())
        texts = session.sent_texts()
        steering = next((text for text in texts if text.startswith("Also look at @fx:note://a please")), "")
        pp.check("the steering message reached the model", bool(steering))
        pp.check("with the resource read from its server after the typed line",
                 "--- resource fx:note://a ---" in steering and "the note's text" in steering)
        shown = ms.screen(terminal)
        pp.check("the screen shows the typed line, not the resource", "Also look at @fx:note://a please" in shown
                 and "the note's text" not in shown)
    print(f"{len(pp.checks)} checks passed")


if __name__ == "__main__":
    main()
