#!/usr/bin/env python3
"""`/tree` opens a picker of the session's prompts (roadmap 0093) through the real binary, a scripted provider and a PTY.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-tree-picker.py .build/release/ask

After two prompts, `/tree` lists both, newest first; choosing the older one goes back to before it and puts its text in the input.
pyte, not a physical terminal.
"""
import importlib.util
import os
import sys
import tempfile

spec = importlib.util.spec_from_file_location("pf", os.path.join(os.path.dirname(os.path.abspath(__file__)), "probe-folding.py"))
pf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pf)
agent, check = pf.agent, pf.check

with tempfile.TemporaryDirectory() as root:
    project, config = root + "/p", root + "/c"
    os.makedirs(project)
    os.makedirs(config + "/ask")
    open(config + "/ask/config.json", "w").write('{"ui":{"prompt":"ask> ","separator":"off"}}')
    server = agent.Server([agent.turn([("text", f"ANSWER {n}")], "end_turn") for n in (1, 2)])
    env = agent.environment(root + "/s", server.url, config=config)
    env.update(TERM="xterm-256color", TERM_PROGRAM="ghostty", LANG="en_US.UTF-8")
    t = pf.Terminal(project, env)
    try:
        t.until(lambda: "ask>" in t.text())
        t.send(b"first question\r")
        t.until(lambda: "ANSWER 1" in t.text())
        t.send(b"second question\r")
        t.until(lambda: "ANSWER 2" in t.text())
        t.send(b"/tree\r")
        t.until(lambda: "branch" in t.text() or "first question" in t.text().split("ANSWER 2")[-1])
        t.repaint()
        screen = t.screen.display
        picker = [line for line in screen if line.lstrip().startswith(("2", "1")) and "question" in line]
        check("the picker lists both prompts, newest first",
              len(picker) == 2 and "second question" in picker[0] and "first question" in picker[1])
        t.send(b"\x1b[B")  # Down: the older prompt
        t.send(b"\r")
        t.until(lambda: "ask> first question" in t.text())
        check("choosing the older one puts its text back in the input", "ask> first question" in t.text())
        t.repaint()
        check("and the conversation is back before it", "ANSWER 1" not in t.text() and "ANSWER 2" not in t.text())
    except (AssertionError, StopIteration):
        print(t.text(), file=sys.stderr)
        raise
    finally:
        t.close()
        server.httpd.shutdown()
