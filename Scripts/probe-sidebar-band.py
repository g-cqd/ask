#!/usr/bin/env python3
"""Probe the sidebar in the bottom band (notes n39, n40; `ui.sidebarLayout`) through the real binary, a PTY and a local fake provider.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-sidebar-band.py .build/release/ask

At 120 by 40 with the sidebar open in the band: the transcript keeps the whole width, the input and the sidebar share six rows behind
a divider, the status line's counts sit at its trailing edge once a thread works, and a click on the thread's row in the band opens its
lane. PROBE_LAYOUT overrides the layout the config sets (`full` shows the probe failing as before). Hermetic.
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


def status(terminal):
    return next(line for line in terminal.screen.display if "anthropic/" in line).rstrip()


def main():
    with tempfile.TemporaryDirectory() as root:
        project, config, state = root + "/project", root + "/config", root + "/state"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        layout = os.environ.get("PROBE_LAYOUT", "bottom")
        with open(config + "/ask/config.json", "w") as file:
            json.dump({"ui": {"inputPrefix": "ask> ", "sidebar": "open", "sidebarLayout": layout},
                       "threads": {"names": "numbered"}}, file)
        turn = probe.agent.turn
        server = probe.agent.Server([turn([("tool", "c1", "sleep 30")], "tool_use")])
        environment = probe.agent.environment(state, server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
        for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
            environment.pop(key, None)
        terminal = None
        try:
            terminal = probe.Terminal(project, environment, columns=120, rows=40)
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.repaint()
            display = terminal.screen.display
            band = [index for index, line in enumerate(display) if len(line) > 89 and line[89] == "│"]
            check("the transcript keeps the whole width: no divider beside it", "│" not in display[0])
            check("the input and the sidebar share six rows behind the divider",
                  len(band) == 6 and display[band[0]].startswith("ask>") and any("◆ main" in display[i] for i in band))
            terminal.send(b"/thread wait a while\r")
            terminal.until(lambda: "1 thread" in status(terminal))
            check("the status line's counts sit at its trailing edge", status(terminal).endswith(("1 thread · 1 job", "1 thread")))
            # The band's row is cut to the panel's width: its start is enough.
            terminal.until(lambda: "thread-1 wait a" in terminal.text())
            # Where the row is: the shared click() takes column 4, which is the input here.
            row = terminal.row("thread-1 wait a")
            column = terminal.screen.display[row].index("thread-1") + 1
            terminal.draw(lambda: terminal.send(f"\x1b[<0;{column};{row + 1}M\x1b[<0;{column};{row + 1}m".encode()))
            # Main's row says the way back, cut to the band's width; the transcript is the thread's own.
            terminal.until(lambda: "◆ main  back to the" in terminal.text() and "shell · sleep 30" in terminal.text())
            check("a click on the thread's row in the band opens its lane",
                  "◆ main  back to the" in terminal.text() and "shell · sleep 30" in terminal.text())
        except AssertionError:
            if terminal:
                print(terminal.text(), file=sys.stderr)
            raise
        finally:
            if terminal:
                terminal.close()
            server.httpd.shutdown()
    print(f"{len(checks)} checks passed")


if __name__ == "__main__":
    main()
