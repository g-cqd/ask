#!/usr/bin/env python3
"""Probe `/tree` (ADR-0093) through the real binary, a PTY and a local fake provider.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-tree.py .build/release/ask [--control OLDER_BINARY]

Two prompts, a listing, a step back to before the second with its text returned to the editor, a changed resend, and a look at what the
provider is then sent: the branch, with no trace of the turn that was set aside. With --control, a binary that predates `/tree` must
not know the command: a probe that cannot fail is not a probe.
"""
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("picker_probe", os.path.join(HERE, "probe-picker.py"))
saved = sys.argv
sys.argv = [saved[0], saved[1]]
pp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pp)
sys.argv = saved
check, press, type_text, rows, prompt_row = pp.check, pp.press, pp.type_text, pp.rows, pp.prompt_row


def screen(terminal):
    terminal.repaint()
    return "\n".join(rows(terminal))


def send(session, text, expect):
    terminal = session.terminal
    type_text(terminal, text)
    press(terminal, b"\r")
    terminal.until(lambda: expect in terminal.text())


def texts(body):
    out = []
    for message in body["messages"]:
        for block in message["content"]:
            if block.get("type") == "text":
                out.append((message["role"], block["text"]))
    return out


def main():
    binary = os.path.abspath(sys.argv[1])
    turns = [pp.short_answer("ANSWER ONE"), pp.short_answer("ANSWER TWO"), pp.short_answer("ANSWER THREE")]
    if "--control" in sys.argv:
        with pp.Session(os.path.abspath(sys.argv[sys.argv.index("--control") + 1]), turns) as session:
            send(session, "first question", "ANSWER ONE")
            send(session, "/tree", "There is no command /tree")
            check("control (a binary before /tree): the command is not known", "There is no command /tree" in screen(session.terminal))

    with pp.Session(binary, turns) as session:
        terminal = session.terminal
        send(session, "first question", "ANSWER ONE")
        send(session, "second question", "ANSWER TWO")

        send(session, "/tree", "> 2  second question")
        shown = screen(terminal)
        check("a listing numbers the prompts and marks the path", "> 1  first question" in shown and "> 2  second question" in shown)

        send(session, "/tree 2", "Went back to before prompt 2")
        shown = screen(terminal)
        check("going back clears what came after and keeps what came before", "ANSWER ONE" in shown and "ANSWER TWO" not in shown)
        check("the prompt is back in the editor to be changed", prompt_row(terminal) == "ask> second question")
        before = session.requests()

        type_text(terminal, " but shorter")
        press(terminal, b"\r")
        terminal.until(lambda: "ANSWER THREE" in terminal.text())
        sent = texts(session.server.requests[-1]["body"])
        said = [text for _, text in sent]
        check("the provider is sent the branch: the first turn and the changed prompt, nothing of the set-aside one",
              said[-3:] == ["first question", "ANSWER ONE", "second question but shorter"]
              and "ANSWER TWO" not in said and "second question" not in said and session.requests() == before + 1)

        send(session, "/tree", "(branch after 1)")
        shown = screen(terminal)
        check("the listing now shows the branch, and the set-aside turn off the path",
              "  2  second question" in shown and "> 3  second question but shorter  (branch after 1)" in shown)

        send_command = "/tree 1"
        type_text(terminal, send_command)
        press(terminal, b"\r")
        terminal.until(lambda: "Went back to before prompt 1" in terminal.text())
        check("going back to the first prompt starts from nothing and returns it to the editor",
              prompt_row(terminal) == "ask> first question" and "ANSWER ONE" not in screen(terminal))

        press(terminal, b"\x18")  # Ctrl-X clears the returned prompt
        send(session, "/tree 9", "Usage: /tree")
        check("a number that is not a prompt is refused with the range", "1 to 3" in screen(terminal))
    print(f"{len(pp.checks)} checks passed")


if __name__ == "__main__":
    main()
