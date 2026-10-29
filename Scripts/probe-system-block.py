#!/usr/bin/env python3
"""ask's own messages are purple blocks and the user's are blue (roadmaps 0106 and 0129) through the real binary and a PTY.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-system-block.py .build/release/ask

`/help` prints ask's own message: its rows must have a purple background (more red than green than the blue user block's). The echoed
command is the user's block. pyte, not a physical terminal.
"""
import importlib.util
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("probe_folding", os.path.join(HERE, "probe-folding.py"))
folding = importlib.util.module_from_spec(spec)
spec.loader.exec_module(folding)
agent, check = folding.agent, folding.check


def rgb(cell):
    return tuple(int(cell.bg[i:i + 2], 16) for i in (0, 2, 4)) if len(cell.bg) == 6 else None


def main():
    with tempfile.TemporaryDirectory() as root:
        project, config = os.path.realpath(root) + "/p", root + "/c"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        open(config + "/ask/config.json", "w").write('{"ui":{"separator":"off","appearance":"dark"}}')
        server = agent.Server([])
        environment = agent.environment(root + "/state", server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty", LANG="en_US.UTF-8")
        terminal = folding.Terminal(project, environment, columns=100, rows=30)
        try:
            terminal.until(lambda: "✓ ·" in terminal.text())
            terminal.send(b"/help\r")
            terminal.until(lambda: "/quit" in terminal.text())
            terminal.repaint()
            display, buffer = terminal.screen.display, terminal.screen.buffer
            user = next(i for i, line in enumerate(display) if line.strip() == "/help")
            system = next(i for i, line in enumerate(display) if "/quit" in line)
            u, s = rgb(buffer[user][0]), rgb(buffer[system][0])
            check("the user's echoed command has a blue background", u is not None and u[2] > u[0] + 10 and u[2] > u[1])
            check("ask's own message has a purple background: red and blue above green", s is not None and s[0] > s[1] + 5 and s[2] > s[1] + 5)
            check("the tint reaches the edge of the screen", all(rgb(buffer[system][c]) == s for c in range(100)))
        except (AssertionError, StopIteration):
            print(terminal.text(), file=sys.stderr)
            raise
        finally:
            terminal.close()
            server.httpd.shutdown()


if __name__ == "__main__":
    main()
