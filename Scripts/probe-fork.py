#!/usr/bin/env python3
"""Probe `/fork` (ADR-0094) through the real binary, a PTY and a local fake provider.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-fork.py .build/release/ask [--control OLDER_BINARY]

Two prompts, a fork of the whole conversation, a fork from before the second prompt, and a look at the files: the original is byte for
byte what it was, the forks are files of their own, and what the provider is sent after a fork is its branch. With --control, a binary
that predates `/fork` must not know the command.
"""
import hashlib
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
check, press, type_text, rows, prompt_row = pp.check, pp.press, pp.type_text, pp.rows, pp.prompt_row


def screen(terminal):
    terminal.repaint()
    return "\n".join(rows(terminal))


def send(session, text, expect):
    terminal = session.terminal
    type_text(terminal, text)
    press(terminal, b"\r")
    terminal.until(lambda: expect in terminal.text())


def files(session):
    state = session.root.name + "/state"
    return sorted(pp.probe.agent.sessions(state), key=os.path.getmtime)


def digest(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def said(body):
    return [block["text"] for message in body["messages"] for block in message["content"] if block.get("type") == "text"]


def main():
    binary = os.path.abspath(sys.argv[1])
    turns = [pp.short_answer("ANSWER ONE"), pp.short_answer("ANSWER TWO"), pp.short_answer("ANSWER THREE"),
             pp.short_answer("ANSWER FOUR")]
    if "--control" in sys.argv:
        with pp.Session(os.path.abspath(sys.argv[sys.argv.index("--control") + 1]), turns) as session:
            send(session, "first question", "ANSWER ONE")
            send(session, "/fork", "There is no command /fork")
            check("control (a binary before /fork): the command is not known", "There is no command /fork" in screen(session.terminal))

    with pp.Session(binary, turns) as session:
        terminal = session.terminal
        send(session, "first question", "ANSWER ONE")
        send(session, "second question", "ANSWER TWO")
        original = files(session)[0]
        before = digest(original)

        send(session, "/fork", "Forked into session")
        shown = screen(terminal)
        check("a fork keeps the whole conversation on screen and names both sessions",
              "ANSWER ONE" in shown and "ANSWER TWO" in shown and "is unchanged and still saved" in shown)
        check("it is a file of its own, and the original is byte for byte what it was",
              len(files(session)) == 2 and digest(original) == before)

        send(session, "third question", "ANSWER THREE")
        check("a prompt after the fork goes to the fork, not to the original",
              digest(original) == before and len(files(session)) == 2)
        sent = said(session.server.requests[-1]["body"])
        check("and the provider is sent the whole branch it was forked from",
              sent[-5:] == ["first question", "ANSWER ONE", "second question", "ANSWER TWO", "third question"])

        send(session, "/fork 2", "Forked into session")
        shown = screen(terminal)
        check("a fork from before prompt 2 shows only what came before it and returns the prompt to the editor",
              "ANSWER ONE" in shown and "ANSWER TWO" not in shown and prompt_row(terminal) == "ask> second question")
        check("it is a third file, and the original is still untouched", len(files(session)) == 3 and digest(original) == before)

        type_text(terminal, " but shorter")
        press(terminal, b"\r")
        terminal.until(lambda: "ANSWER FOUR" in terminal.text())
        sent = said(session.server.requests[-1]["body"])
        check("what the provider is sent from the second fork is its own branch, with nothing of the first turns' second prompt",
              sent[-3:] == ["first question", "ANSWER ONE", "second question but shorter"]
              and "ANSWER TWO" not in sent and "third question" not in sent)

        press(terminal, b"\x18")
        send(session, "/fork 9", "Usage: /fork")
        check("a number that is not a prompt is refused with the range", "1 to" in screen(terminal))
    print(f"{len(pp.checks)} checks passed")


if __name__ == "__main__":
    main()
