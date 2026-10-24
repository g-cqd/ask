#!/usr/bin/env python3
"""Probe a click on a picker row (roadmap 0048, ADR-0070) through the real binary, a PTY and a local fake provider.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-picker-click.py .build/release/ask [--control OLDER_BINARY]

Reuses the command picker probe's harness. With --control, a binary that predates clickable rows must leave the draft as it was after
the same click: a probe that cannot fail is not a probe.
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("picker_probe", os.path.join(HERE, "probe-picker.py"))
saved = sys.argv
sys.argv = [saved[0], saved[1]]
pp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pp)
sys.argv = saved
check, type_text, press, rows, prompt_row = pp.check, pp.type_text, pp.press, pp.rows, pp.prompt_row


def click(terminal, row, col=10):
    """A left press and release at zero-based cells, each followed by a full repaint."""
    press(terminal, f"\x1b[<0;{col + 1};{row + 1}M".encode())
    press(terminal, f"\x1b[<0;{col + 1};{row + 1}m".encode())


def row_of(terminal, prefix):
    return next((i for i, line in enumerate(rows(terminal)) if line.startswith(prefix)), None)


def prepare(project):
    for name in ("alpha.txt", "beta.txt", "gamma.txt"):
        with open(os.path.join(project, name), "w") as file:
            file.write(name + "\n")


def main():
    binary = os.path.abspath(sys.argv[1])
    if "--control" in sys.argv:
        with pp.Session(sys.argv[sys.argv.index("--control") + 1], []) as session:
            type_text(session.terminal, "/")
            target = row_of(session.terminal, "/quit")
            click(session.terminal, target)
            check("control (a binary without clickable rows): a click on a row leaves the draft as it was",
                  prompt_row(session.terminal) == "ask> /")

    with pp.Session(binary, [pp.short_answer("GOT PROMPT")], prepare=prepare) as session:
        terminal = session.terminal
        baseline = session.requests()
        type_text(terminal, "/")
        title = pp.title_row(terminal)
        for label, row in (("the title", title), ("the status line", title - 1), ("the transcript", 2)):
            click(terminal, row)
            check(f"a click on {label} chooses nothing and keeps the list", prompt_row(terminal) == "ask> /"
                  and pp.title_row(terminal) == title)

        click(terminal, row_of(terminal, "/quit"), col=30)
        check("a click on a command row inserts it, wherever along the row, and sends nothing",
              prompt_row(terminal) == "ask> /quit" and pp.title_row(terminal) is None and session.requests() == baseline)
        press(terminal, b"\x18")

        type_text(terminal, "/re")
        first, second = pp.listed(terminal)[0][:2]
        click(terminal, row_of(terminal, second))
        check("a click on the second row inserts the second match, not the chosen one",
              prompt_row(terminal) == f"ask> {second}" and first != second)
        press(terminal, b"\x18")

        type_text(terminal, "@")
        deadline = 0
        while not any(line.startswith("beta.txt") for line in rows(terminal)) and deadline < 40:
            terminal.pump()
            terminal.repaint()
            deadline += 1
        click(terminal, row_of(terminal, "beta.txt"))
        check("a click on a file row inserts @path with the space after, and sends nothing",
              prompt_row(terminal) == "ask> @beta.txt" and session.requests() == baseline)
        press(terminal, b"\x18")

    print(f"{len(pp.checks)} checks passed")


if __name__ == "__main__":
    main()
