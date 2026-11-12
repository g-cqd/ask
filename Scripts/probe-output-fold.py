#!/usr/bin/env python3
"""A long tool output folds its middle (roadmap 0078), through the real binary, a scripted provider and a PTY.

Scripts/probe-output-fold.py .build/release/ask

A read of a 300-line file under `ui.fold.outputLines` 10: the open block shows five lines from each end with a marker between, its
header still counts 300 lines, a click on the marker shows the middle and Ctrl+G folds it again. A write with old_text and replace_all then
says how many occurrences it replaced, live and after a resume, from the count the tool reported. Verifies ask's bytes through an
emulator, not a physical terminal.
"""
import importlib.util
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, file))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


folding = load("folding_probe", "probe-folding.py")
agent = folding.agent
check = folding.check


def read_turn():
    return agent.turn([("call", "t1", "read", {"path": "long.txt"})], "tool_use")


def edit_turn():
    arguments = {"path": "edit.txt", "old_text": "x", "new_text": "y", "replace_all": True}
    return agent.turn([("call", "t2", "write", arguments)], "tool_use")


def main():
    with tempfile.TemporaryDirectory() as root:
        project, config = root + "/project", root + "/config"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        with open(project + "/long.txt", "w") as file:
            file.write("".join(f"out {n}\n" for n in range(1, 301)))
        with open(project + "/edit.txt", "w") as file:
            file.write("x x x\n")
        with open(config + "/ask/config.json", "w") as file:
            file.write('{"ui":{"inputPrefix":"ask> ","fold":{"tools":false,"outputLines":10},"tint":"off",'
                       '"separator":"off"}}')
        server = agent.Server([read_turn(), edit_turn(), agent.turn([("text", "PROBE ANSWER")], "end_turn")])
        environment = agent.environment(root + "/state", server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
        for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
            environment.pop(key, None)
        terminal = None
        try:
            terminal = folding.Terminal(project, environment, columns=100, rows=40)
            terminal.until(lambda: "ask>" in terminal.text())
            beginning = len(terminal.raw)
            terminal.send(b"Go\r")
            terminal.until(lambda: b"PROBE ANSWER" in bytes(terminal.raw)[beginning:])
            terminal.repaint()
            shown = terminal.text()
            check("the open block keeps both ends and a marker", "⋯ 290 lines hidden" in shown
                  and "out 5" in shown and "out 296" in shown and "out 150" not in shown)
            check("the header still counts every line", "300 lines" in shown)
            terminal.draw(lambda: terminal.click("lines hidden"))
            check("a click on the marker shows the middle, not folding the block", "out 290" in terminal.text()
                  and "lines hidden" not in terminal.text())
            # Ctrl+G flips the default and forgets each block's choice: first every long block open, then every one folded.
            terminal.draw(lambda: terminal.send(b"\x07"))
            check("the first Ctrl+G opens every middle, this one included", "lines hidden" not in terminal.text())
            terminal.draw(lambda: terminal.send(b"\x07"))
            check("the second Ctrl+G folds the middle again", "⋯ 290 lines hidden" in terminal.text()
                  and "out 150" not in terminal.text())
            check("the edit's header counts its replacements", "3 replacements · ✓" in terminal.text())
            terminal.close()
            terminal = folding.Terminal(project, environment, resume=True, columns=100, rows=40)
            terminal.until(lambda: "PROBE ANSWER" in terminal.text())
            terminal.repaint()
            check("a resumed edit still counts them", "3 replacements · ✓" in terminal.text())
        except AssertionError:
            if terminal:
                print(terminal.text(), file=sys.stderr)
            raise
        finally:
            if terminal:
                terminal.close()
            server.httpd.shutdown()
            server.httpd.server_close()


if __name__ == "__main__":
    main()
