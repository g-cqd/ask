#!/usr/bin/env python3
"""Note n13 through the real binary, a scripted provider and a PTY: in the padded look, the pointer over a tool block lights its header,
every row of a wrapped one, and turns the pointer into a hand (OSC 22); off it, the arrow again; and ask leaves the terminal's own
pointer when it quits with the hand shown.

Scripts/probe-hover.py .build/release/ask

Requires pyte. This reads ask's bytes through an emulator, not a physical terminal's pointer.
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
HAND = b"\x1b]22;pointer\x1b\\"
ARROW = b"\x1b]22;default\x1b\\"
LONG = "deep/" * 30 + "note.txt"


def check(label, condition):
    if not condition:
        raise AssertionError(label)
    checks.append(label)
    print("PASS " + label, flush=True)


def move(terminal, row, col):
    """A motion report with no button held, at 0-based `row`, `col`."""
    terminal.send(f"\x1b[<35;{col + 1};{row + 1}M".encode())


def bold_rows(terminal, rows):
    return [any(cell.bold for cell in terminal.screen.buffer[row].values() if cell.data.strip()) for row in rows]


def main():
    root = tempfile.mkdtemp()
    config, state = root + "/config", root + "/state"
    project = tempfile.mkdtemp(prefix="probe-hover-")
    os.makedirs(os.path.join(project, os.path.dirname(LONG)))
    with open(os.path.join(project, LONG), "w") as file:
        file.write("ONE\nTWO\n")
    os.makedirs(config + "/ask")
    with open(config + "/ask/config.json", "w") as file:
        json.dump({"ui": {"inputPrefix": "ask> ", "fold": {"tools": False}}}, file)
    turn = probe.agent.turn
    server = probe.agent.Server([turn([("call", "r1", "read", {"path": LONG})], "tool_use"),
                                 turn([("text", "READ IT")], "end_turn")])
    environment = probe.agent.environment(state, server.url, config=config)
    environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
    terminal = None
    try:
        terminal = probe.Terminal(project, environment, columns=80, rows=30)
        terminal.until(lambda: "ask>" in terminal.text())
        terminal.send(b"Go\r")
        terminal.until(lambda: "READ IT" in terminal.text())
        terminal.repaint()
        display = terminal.screen.display
        # The header's rows: the one that names the tool, and those its path wraps onto; the input shown under it is not the header.
        first = next(index for index, line in enumerate(display) if "read · deep/" in line)
        rows = [first]
        while "deep/" in display[rows[-1] + 1] and "note.txt" not in display[rows[-1]]:
            rows.append(rows[-1] + 1)
        check("the header wraps", len(rows) >= 2)
        check("nothing is lit before the pointer moves", not any(bold_rows(terminal, rows)))
        terminal.draw(lambda: move(terminal, rows[0], 4))
        check("over the block, every row of its header is lit", all(bold_rows(terminal, rows)))
        output = next(index for index, line in enumerate(terminal.screen.display) if "ONE" in line)
        check("and not its output", not any(bold_rows(terminal, [output])))
        check("and the pointer is a hand", bytes(terminal.raw).endswith(HAND) or HAND in bytes(terminal.raw))
        sent = len(terminal.raw)
        terminal.draw(lambda: move(terminal, 0, 30))  # an empty row; its last column is the sidebar toggle
        check("off it, the arrow again, and the header dims", ARROW in bytes(terminal.raw)[sent:]
              and not any(bold_rows(terminal, rows)))
        terminal.draw(lambda: move(terminal, rows[1], 10))
        sent = len(terminal.raw)
        terminal.send(b"/quit")
        probe.time.sleep(0.5)
        # The picker takes the first Enter, inserting the command; the second runs it.
        for _ in range(2):
            terminal.send(b"\r")
            probe.time.sleep(0.5)
        deadline = probe.time.monotonic() + 5
        while ARROW not in bytes(terminal.raw)[sent:] and probe.time.monotonic() < deadline:
            try:
                terminal.pump()
            except OSError:
                break
        check("quitting with the hand shown gives the terminal its own pointer back", ARROW in bytes(terminal.raw)[sent:])
    except AssertionError:
        if terminal:
            print(terminal.text(), file=sys.stderr)
        raise
    finally:
        if terminal:
            terminal.close()
        server.httpd.shutdown()
        shutil.rmtree(project, ignore_errors=True)
    print(f"{len(checks)} checks passed")


if __name__ == "__main__":
    main()
