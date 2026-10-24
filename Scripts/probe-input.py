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


def paste(terminal, text):
    terminal.draw(lambda: terminal.send(b"\x1b[200~" + text.encode() + b"\x1b[201~"))


def scenario(label, draft, expected, width, height, changed=None, clear_first=False, click=None, select=None, taps=None):
    with tempfile.TemporaryDirectory() as root:
        project, config, state = root + "/project", root + "/config", root + "/state"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        with open(config + "/ask/config.json", "w") as file:
            json.dump({"ui": {"promptRows": 2}}, file)
        server = probe.agent.Server([probe.agent.turn([("text", "CAPTURED")], "end_turn")])
        environment = probe.agent.environment(state, server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
        for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
            environment.pop(key, None)
        terminal = None
        try:
            terminal = probe.Terminal(project, environment, columns=width, rows=height)
            terminal.until(lambda: "ask>" in terminal.text())
            if clear_first:
                paste(terminal, "\n".join(f"line {n}" for n in range(1, 11)))
                check(label + ": configured two-row limit has a visible clipping cue",
                      terminal.screen.display[height - 3].startswith("input 9–10 of 10"))
                terminal.draw(lambda: terminal.send(b"\x18"))
                check(label + ": Ctrl+X clears every hard line without submitting",
                      not server.requests and terminal.screen.display[height - 1].rstrip() == "ask>"
                      and "line 10" not in terminal.text())
            paste(terminal, draft)
            check(label + ": a bracketed paste is not a submission", not server.requests)
            if changed:
                width, height = changed
                terminal.resize(width, height)
                check(label + ": resize preserves a bounded viewport", terminal.screen.display[height - 3].startswith("input "))
            if click:
                column, row = click
                terminal.draw(lambda: terminal.send(f"\x1b[<0;{column + 1};{row + 1}M\x1b[<0;{column + 1};{row + 1}m".encode()))
                check(label + ": a click puts the cursor on the clicked cell",
                      (terminal.screen.cursor.x, terminal.screen.cursor.y) == (column, row))
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
                wanted_column = 7
                check(label + ": Up moves to the previous display row at the wanted cell",
                      terminal.screen.cursor.y == height - 2 and terminal.screen.cursor.x == wanted_column)
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
    scenario("click", "hello world", "helloX world", 40, 12, click=(10, 11))
    wrapped = "0123456789abcdefghijklmnopqrstuvwxyzABCD"
    scenario("click on a wrapped row", wrapped, wrapped[:19] + "X" + wrapped[19:], 20, 12, click=(4, 10))
    scenario("select", "hello world", "hX world", 40, 12, select=((6, 11), (9, 11), "ello"))
    scenario("double click", "hello world", "X world", 40, 12, taps=((7, 11), 2, "hello"))
    scenario("triple click", "ab cd\nef gh", "ab cd\nX", 40, 12, taps=((7, 11), 3, "ef gh"))
    print(f"{len(checks)} checks passed")


if __name__ == "__main__":
    main()
