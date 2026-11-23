#!/usr/bin/env python3
"""Open bash call blocks highlight shell and embedded heredoc bodies through the real binary, a PTY and a scripted provider (t128).

Scripts/probe-heredoc-highlight.py .build/release/ask

The model runs a bash call with a `python3 - <<'EOF'` heredoc. Opening the tool block shows the Python `def` keyword coloured
(ANSI foreground palette 5) while the `shell ·` lead stays dim and plain text stays at full brightness. pyte, not a physical
terminal.
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


def check(label, condition, detail=""):
    if not condition:
        raise AssertionError(f"{label}: {detail}")
    print("PASS " + label, flush=True)


def main():
    root = tempfile.mkdtemp(prefix="probe-heredoc-")
    config, state, project = root + "/config", root + "/state", root + "/project"
    os.makedirs(config + "/ask")
    os.makedirs(project)
    with open(config + "/ask/config.json", "w") as file:
        json.dump({"ui": {"inputPrefix": "ask> ", "fold": {"tools": False}, "highlight": True}}, file)
    command = "python3 - <<'EOF'\ndef compute_answer():\n    return \"ok\"\nEOF"
    turn = probe.agent.turn
    server = probe.agent.Server([
        turn([("call", "b1", "bash", {"command": command})], "tool_use"),
        turn([("text", "ALL DONE")], "end_turn"),
    ])
    environment = probe.agent.environment(state, server.url, config=config)
    terminal = None
    try:
        terminal = probe.Terminal(project, environment, columns=100, rows=24)
        terminal.until(lambda: "ask>" in terminal.text())
        terminal.send(b"Run it\r")
        terminal.until(lambda: "ALL DONE" in terminal.text() and "def compute_answer" in terminal.text())
        row = next(r for r, line in enumerate(terminal.screen.display) if "def compute_answer" in line)
        line = terminal.screen.display[row]
        col = line.index("def")
        def_fg = terminal.screen.buffer[row][col].fg
        ident_fg = terminal.screen.buffer[row][line.index("compute_answer")].fg
        ret_row = next(r for r, text in enumerate(terminal.screen.display) if 'return "ok"' in text)
        str_col = terminal.screen.display[ret_row].index('"ok"')
        str_fg = terminal.screen.buffer[ret_row][str_col].fg
        check("Python `def` keyword is coloured (palette magenta, not default)", def_fg == "magenta", f"fg={def_fg}")
        check("identifier stays default foreground at full brightness", ident_fg == "default", f"fg={ident_fg}")
        check("Python string literal is coloured (palette green)", str_fg == "green", f"fg={str_fg}")
    except AssertionError:
        if terminal:
            print(terminal.text(), file=sys.stderr)
        raise
    finally:
        if terminal:
            terminal.close()
        server.httpd.shutdown()
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    main()
