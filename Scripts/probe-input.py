#!/usr/bin/env python3
"""Probe bounded input, visual-row editing and resize through the real binary and a local fake provider.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-input.py .build/release/ask

Reuses the folding probe's PTY/emulator harness. No window, real credentials or host clipboard writes.
"""
import importlib.util
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("fold_probe", os.path.join(HERE, "probe-folding.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
checks = []


def check(label, condition):
    probe.check(label, condition)
    checks.append(label)


def rules(terminal):
    return [row for row, line in enumerate(terminal.screen.display) if line.startswith("\u2500" * 5)]


def prompt(terminal):
    """The prompt's rows: those between the last two rules. The prompt has no marker; the status is the row below them."""
    found = rules(terminal)
    return [terminal.screen.display[row].rstrip() for row in range(found[-2] + 1, found[-1])] if len(found) >= 2 else []


def status(terminal):
    return terminal.screen.display[terminal.screen.lines - 1].rstrip()


def paste(terminal, text):
    terminal.draw(lambda: terminal.send(b"\x1b[200~" + text.encode() + b"\x1b[201~"))


def scenario(label, draft, expected, width, height, changed=None, clear_first=False, click=None, select=None, taps=None, shifted=None, wheeled=None, cut=None):
    with tempfile.TemporaryDirectory() as root:
        project, config, state = root + "/project", root + "/config", root + "/state"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        with open(config + "/ask/config.json", "w") as file:
            json.dump({"ui": {"inputRows": 2}}, file)
        server = probe.agent.Server([probe.agent.turn([("text", "CAPTURED")], "end_turn")])
        environment = probe.agent.environment(state, server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
        for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
            environment.pop(key, None)
        terminal = None
        try:
            terminal = probe.Terminal(project, environment, columns=width, rows=height)
            terminal.until(lambda: len(rules(terminal)) >= 2)
            if clear_first:
                paste(terminal, "\n".join(f"line {n}" for n in range(1, 11)))
                check(label + ": configured two-row limit has a visible clipping cue",
                      status(terminal).startswith("input 9–10 of 10") and prompt(terminal) == ["line 9", "line 10"])
                terminal.draw(lambda: terminal.send(b"\x18"))
                check(label + ": Ctrl+X clears every hard line without submitting",
                      not server.requests and prompt(terminal) == [""] and "line 10" not in terminal.text())
            paste(terminal, draft)
            check(label + ": a bracketed paste is not a submission", not server.requests)
            if changed:
                width, height = changed
                terminal.resize(width, height)
                check(label + ": resize preserves a bounded viewport", status(terminal).startswith("input ") and len(prompt(terminal)) == 2)
            if click:
                column, row = click
                terminal.draw(lambda: terminal.send(f"\x1b[<0;{column + 1};{row + 1}M\x1b[<0;{column + 1};{row + 1}m".encode()))
                check(label + ": a click puts the cursor on the clicked cell",
                      (terminal.screen.cursor.x, terminal.screen.cursor.y) == (column, row))
            elif cut:
                (start, end), copied = cut[:2], cut[2]
                terminal.send(f"\x1b[<0;{start[0] + 1};{start[1] + 1}M\x1b[<32;{end[0] + 1};{end[1] + 1}M".encode())
                terminal.send(f"\x1b[<0;{end[0] + 1};{end[1] + 1}m".encode())
                terminal.until(lambda: bool(terminal.copies()))
                copies = len(terminal.copies())
                terminal.send(b"\x18")
                terminal.until(lambda: len(terminal.copies()) > copies)
                check(label + ": control X puts exactly the selection on the clipboard", terminal.copies()[-1] == copied)
                terminal.repaint()
                check(label + ": and takes it out of the draft",
                      prompt(terminal) == ["h world"] and "ctrl+x" not in terminal.text())
            elif wheeled:
                for _ in range(wheeled):
                    terminal.send(f"\x1b[<64;5;{height - 2}M".encode())  # over the prompt's lower row
                    terminal.pump()
                terminal.repaint()
                check(label + ": the wheel scrolls the input's window by rows", prompt(terminal) == ["line 6", "line 7"])
                check(label + ": the cursor is hidden while it is out of the window", terminal.screen.cursor.hidden)
                check(label + ": and nothing was submitted", not server.requests)
                terminal.draw(lambda: terminal.send(b"Y"))
                check(label + ": a key brings the window and the cursor back",
                      not terminal.screen.cursor.hidden and prompt(terminal)[-1:] == ["line 10Y"])
            elif shifted:
                steps, copied = shifted
                terminal.draw(lambda: terminal.send(b"\x01" + b"\x1b[1;2C" * steps))
                row = height - 3
                cells = list(range(0, steps))
                inverse = lambda: [col for col in range(width) if terminal.screen.buffer[row][col].reverse]
                terminal.until(lambda: inverse() == cells)
                check(label + ": shift and right highlight the cells passed", inverse() == cells)
                copies = len(terminal.copies())
                terminal.send(b"\x03")
                terminal.until(lambda: len(terminal.copies()) > copies)
                check(label + ": control C copies exactly them", terminal.copies()[-1] == copied)
                terminal.draw(lambda: terminal.send(b"\x01" + b"\x1b[1;2C" * steps))
            elif taps:
                (column, row), count, copied = taps
                for _ in range(count):
                    terminal.send(f"\x1b[<0;{column + 1};{row + 1}M\x1b[<0;{column + 1};{row + 1}m".encode())
                    terminal.pump()
                terminal.until(lambda: bool(terminal.copies()))
                terminal.repaint()
                check(label + ": copies exactly the word or line taken", terminal.copies()[-1] == copied)
                check(label + ": and highlights it", any(cell.reverse for cell in terminal.screen.buffer[row].values()))
            elif select:
                (start, end), copied = select[:2], select[2]
                terminal.send(f"\x1b[<0;{start[0] + 1};{start[1] + 1}M\x1b[<32;{end[0] + 1};{end[1] + 1}M".encode())
                terminal.send(f"\x1b[<0;{end[0] + 1};{end[1] + 1}m".encode())
                terminal.until(lambda: bool(terminal.copies()))
                terminal.repaint()
                check(label + ": a drag in the input copies exactly the dragged text", terminal.copies()[-1] == copied)
                inverse = [col for col in range(width) if terminal.screen.buffer[start[1]][col].reverse]
                check(label + ": and highlights it", bool(inverse) and inverse[0] == start[0])
            else:
                terminal.draw(lambda: terminal.send(b"\x1b[A"))
                # The prompt has no marker: the wanted cell is the column the caret had, 2 in every draft here (after "YZ", "ef" or "ghi" on a
                # tab stop, which Up lands on at its first cell).
                wanted_column = 2
                check(label + ": Up moves to the previous display row at the wanted cell",
                      terminal.screen.cursor.y == height - 4 and terminal.screen.cursor.x == wanted_column)
            terminal.draw(lambda: terminal.send(b"X"))
            start = len(terminal.raw)
            terminal.send(b"\r")
            terminal.until(lambda: bool(server.requests) and b"CAPTURED" in bytes(terminal.raw)[start:])
            terminal.repaint()
            body = server.requests[0]["body"]
            texts = [block.get("text") for message in body.get("messages", []) for block in message.get("content", [])]
            check(label + ": the provider receives the complete edited source text", expected in texts)
            files = probe.agent.sessions(state)
            users = []
            for path in files:
                with open(path) as archive:
                    for line in archive:
                        record = json.loads(line)
                        if record.get("type") == "entry" and record["payload"].get("kind") == "user":
                            users.append(record["payload"]["text"])
            check(label + ": the session records that same text exactly once", users == [expected])
        except AssertionError:
            if terminal:
                print(terminal.text(), file=sys.stderr)
                print(f"cursor=({terminal.screen.cursor.x},{terminal.screen.cursor.y})", file=sys.stderr)
            raise
        finally:
            if terminal:
                terminal.close()
            server.httpd.shutdown()
            server.httpd.server_close()


def main():
    draft = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    scenario("ASCII", draft, draft[:42] + "X" + draft[42:], 20, 12, clear_first=True)
    scenario("wide", "日本語abcdef", "日X本語abcdef", 10, 9)
    # The tab at display column 7 ends at stop 8; nine letters put the final caret at column 7 on the next row.
    scenario("tabs", "日\tabcdefghi", "日X\tabcdefghi", 10, 9)
    scenario("resized", draft, draft[:52] + "X" + draft[52:], 20, 12, changed=(10, 9))
    # In a 12-row screen a one-row draft is on row 9 (rules on 8 and 10, the status on 11); a two-row one on rows 8 and 9.
    scenario("click", "hello world", "helloX world", 40, 12, click=(5, 9))
    # Forty letters fill two rows of twenty, so the caret after them opens a third and the window shows rows two and three.
    wrapped = "0123456789abcdefghijklmnopqrstuvwxyzABCD"
    scenario("click on a wrapped row", wrapped, wrapped[:24] + "X" + wrapped[24:], 20, 12, click=(4, 8))
    scenario("select", "hello world", "hX world", 40, 12, select=((1, 9), (4, 9), "ello"))
    scenario("double click", "hello world", "X world", 40, 12, taps=((2, 9), 2, "hello"))
    scenario("triple click", "ab cd\nef gh", "ab cd\nX", 40, 12, taps=((2, 9), 3, "ef gh"))
    scenario("shift and arrows", "hello world", "X world", 40, 12, shifted=(5, "hello"))
    ten = "\n".join(f"line {n}" for n in range(1, 11))
    scenario("wheel", ten, ten + "YX", 40, 12, wheeled=3)
    scenario("cut", "hello world", "hX world", 40, 12, cut=((1, 9), (4, 9), "ello"))
    print(f"{len(checks)} checks passed")


if __name__ == "__main__":
    main()
