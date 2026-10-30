#!/usr/bin/env python3
"""Probe the `/` command picker (roadmap 0048, ADR-0066) through the real binary, a PTY and a local fake provider.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-picker.py .build/release/ask [--control OLDER_BINARY]

Reuses the folding probe's PTY/emulator harness; no window, credentials or clipboard. With --control, the first scenario also
runs against a binary that predates the picker and must show NO picker: a probe that cannot fail is not a probe.
"""
import importlib.util
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("fold_probe", os.path.join(HERE, "probe-folding.py"))
probe = importlib.util.module_from_spec(spec)
saved = sys.argv
spec.loader.exec_module(probe)
checks = []


def check(label, condition):
    probe.check(label, condition)
    checks.append(label)


def long_answer():
    return probe.agent.turn([("text", "\n".join(f"ANSWER LINE {n}" for n in range(1, 61)))], "end_turn")


def short_answer(text):
    return probe.agent.turn([("text", text)], "end_turn")


def rows(terminal):
    return [line.rstrip() for line in terminal.screen.display]


def title_row(terminal):
    return next((i for i, line in enumerate(rows(terminal)) if line.startswith("commands")), None)


def listed(terminal):
    """The commands the picker lists, in order, and the index of its title row."""
    shown, top = rows(terminal), title_row(terminal)
    if top is None:
        return [], None
    names = []
    for line in shown[top + 1:]:
        if not line.startswith("/"):
            # A category heading ("session", "tools") is not a match; the prompt or a blank row ends the list.
            if line.startswith("ask>") or not line:
                break
            continue
        names.append(line.split()[0])
    return names, top


def prompt_row(terminal):
    return next(line for line in reversed(rows(terminal)) if line.startswith("ask>"))


def type_text(terminal, text):
    """One character per frame, each followed by a full repaint: the emulator cannot apply the terminal's scroll-region
    diffs, so a snapshot taken between a typed character and its frame would show a mix of two layouts."""
    for character in text:
        terminal.draw(lambda: terminal.send(character.encode()))


def press(terminal, data):
    terminal.draw(lambda: terminal.send(data))


class Session:
    """One ask in a PTY against a fake provider, torn down on exit."""

    def __init__(self, binary, turns, columns=100, height=30, prepare=None, settings=None, approvals=False):
        self.root = tempfile.TemporaryDirectory()
        project, config, state = self.root.name + "/project", self.root.name + "/config", self.root.name + "/state"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        self.project = os.path.realpath(project)
        # The prompt has no marker by default; the probes read the prompt row by one, so every session sets it unless the probe chose its own.
        chosen = settings(self.project) if settings is not None else {}
        chosen.setdefault("ui", {}).setdefault("inputPrefix", "ask> ")
        with open(config + "/ask/config.json", "w") as file:
            json.dump(chosen, file)
        if prepare is not None:
            prepare(self.project)
        self.server = probe.agent.Server(turns)
        environment = probe.agent.environment(state, self.server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
        for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
            environment.pop(key, None)
        probe.BINARY = os.path.abspath(binary)
        self.terminal = probe.Terminal(project, environment, columns=columns, rows=height, approvals=approvals)
        self.terminal.until(lambda: "ask>" in self.terminal.text() or "✓ ·" in self.terminal.text() or "! ·" in self.terminal.text())

    def requests(self):
        return len(self.server.requests)

    def sent_texts(self):
        out = []
        for request in self.server.requests:
            for message in request["body"].get("messages", []):
                for block in message.get("content", []):
                    if block.get("type") == "text":
                        out.append(block.get("text"))
        return out

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        if exc[0]:
            print(self.terminal.text(), file=sys.stderr)
        self.terminal.close()
        self.server.httpd.shutdown()
        self.server.httpd.server_close()
        self.root.cleanup()


def control(binary, settings):
    with Session(binary, [], columns=100, height=30, settings=settings) as session:
        type_text(session.terminal, "/")
        check("control (a binary without the picker): a slash opens no list", title_row(session.terminal) is None)


def main():
    binary = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".build/release/ask")
    settings = lambda project: {"ui": {"inputPrefix": "ask> "}}
    if "--control" in sys.argv:
        control(sys.argv[sys.argv.index("--control") + 1], settings=settings)

    turns = [long_answer(), short_answer("GOT PATH"), short_answer("GOT ESCAPED"), short_answer("GOT PLAIN")]
    with Session(binary, turns, settings=settings) as session:
        terminal = session.terminal
        # A transcript taller than the screen, so there is something for the wheel to scroll.
        type_text(terminal, "fill")
        press(terminal, b"\r")
        terminal.until(lambda: "ANSWER LINE 60" in terminal.text())
        terminal.repaint()
        baseline = session.requests()

        type_text(terminal, "/")
        names, top = listed(terminal)
        check("a slash opens a list of every command, titled and above the prompt", top is not None and len(names) >= 6
              and names[:4] == ["/help", "/quit", "/continue", "/follow-up"] and prompt_row(terminal) == "ask> /")
        check("commands group under dim category headings",
              rows(terminal)[top + 1] == "session" and not terminal.screen.buffer[top + 1][0].bold)
        check("the title names the keys", "Enter" in rows(terminal)[top] and "Esc" in rows(terminal)[top])
        check("the list sits between the transcript and the prompt, in text only",
              rows(terminal)[top - 1].startswith("─") or rows(terminal)[top - 1].startswith("ANSWER LINE"))

        type_text(terminal, "co")
        names, top = listed(terminal)
        check("typing filters it, keeping the category's prefix matches first",
              names[:2] == ["/continue", "/compact"] and rows(terminal)[top + 1] == "session")
        check("the filter is the draft itself", prompt_row(terminal) == "ask> /co")

        press(terminal, b"\x1b[B")
        names, top = listed(terminal)
        buffer = terminal.screen.buffer
        check("Down moves the choice: a command row turns bold and the heading does not",
              buffer[top + 3][0].bold and not buffer[top + 2][0].bold and not buffer[top + 1][0].bold)

        before = terminal.text()
        press(terminal, b"\x1b[<64;10;3M")
        names_after, top_after = listed(terminal)
        check("the wheel scrolls the transcript and leaves the list, the choice and the draft alone",
              names_after == names and top_after == top and buffer[top + 3][0].bold
              and prompt_row(terminal) == "ask> /co" and terminal.text() != before)
        press(terminal, b"\x1b[<65;10;3M")

        inserted = names[1]
        press(terminal, b"\r")
        check("Enter inserts the chosen command and does not send it",
              prompt_row(terminal) == "ask> " + inserted and title_row(terminal) is None and session.requests() == baseline)
        press(terminal, b"\x18")  # Ctrl-X clears the draft

        type_text(terminal, "/re")
        first = listed(terminal)[0][0]
        press(terminal, b"\t")
        check("Tab completes exactly as Enter does, to the first match",
              first.startswith("/re") and prompt_row(terminal) == "ask> " + first and session.requests() == baseline)
        press(terminal, b"\x18")

        type_text(terminal, "/co")
        press(terminal, b"\x1b")
        check("Escape closes it and keeps what was typed",
              title_row(terminal) is None and prompt_row(terminal) == "ask> /co")
        type_text(terminal, "n")
        check("more typing in the same word does not reopen it", title_row(terminal) is None)
        press(terminal, b"\x18")

        type_text(terminal, "please /co")
        check("a command is offered only as the first word", title_row(terminal) is None)
        press(terminal, b"\x18")

        type_text(terminal, "/config")
        check("a name typed in full closes the list", title_row(terminal) is None)
        press(terminal, b"\r")
        terminal.until(lambda: "config ·" in terminal.text() and "user" in terminal.text())
        check("submitting a choice-taking command opens its choices without a prompt",
              session.requests() == baseline)
        press(terminal, b"\x1b")
        press(terminal, b"\x18")

        type_text(terminal, "/etc/hosts what is this")
        check("a path is not a command word", title_row(terminal) is None)
        press(terminal, b"\r")
        terminal.until(lambda: "GOT PATH" in terminal.text())
        check("and Enter sends it as a prompt, exactly as typed", "/etc/hosts what is this" in session.sent_texts())

        type_text(terminal, "//config")
        check("a doubled slash is not a command word either", title_row(terminal) is None)
        press(terminal, b"\r")
        terminal.until(lambda: "GOT ESCAPED" in terminal.text())
        check("and sends the prompt with one slash", "/config" in session.sent_texts())

        # An open list while a prompt is in flight is the same list: no request is made until Enter on a full line.
        type_text(terminal, "/")
        check("the list reopens for a fresh slash after a turn", title_row(terminal) is not None)
        press(terminal, b"\x1b")
        press(terminal, b"\x18")

    with Session(binary, [], settings=settings) as session:
        terminal = session.terminal
        type_text(terminal, "/co")
        names, top = listed(terminal)
        shrunk = (80, 13)
        terminal.resize(*shrunk)
        type_text(terminal, "m")
        names, top = listed(terminal)
        check("after a resize the next key sizes the list to the screen (three rows at 13)", 1 <= len(names) <= 3)
        check("and the prompt stays on the last row", prompt_row(terminal) == "ask> /com")

    with Session(binary, [], columns=80, height=11, settings=settings) as session:
        terminal = session.terminal
        type_text(terminal, "/co")
        check("a screen too short for the list does not show one", title_row(terminal) is None)
        press(terminal, b"\r")
        terminal.until(lambda: "There is no command /co" in terminal.text())
        check("and Enter keeps its ordinary meaning there", session.requests() == 0)

    print(f"{len(checks)} checks passed")


if __name__ == "__main__":
    main()
