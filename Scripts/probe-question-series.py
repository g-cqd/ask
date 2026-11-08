#!/usr/bin/env python3
"""Note n14 through the real binary, a scripted provider and a PTY: the model asks sixteen questions; on a 60-column screen the tab row
shows the current one in full and the others by their initial, a › where the rest are left out, Right moves along it, and after the review the model gets sixteen
answers back.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-question-series.py .build/release/ask

Requires pyte.
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

WORDS = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel",
         "India", "Juliett", "Kilo", "Lima", "Mike", "November", "Oscar", "Papa"]
checks = []


def check(label, condition, detail=""):
    if not condition:
        raise AssertionError(f"{label}: {detail}")
    checks.append(label)
    print("PASS " + label, flush=True)


def tab_row(terminal):
    return next((line for line in terminal.screen.display if any(f"[{word}]" in line for word in WORDS)), "")


def main():
    root = tempfile.mkdtemp()
    config, state = root + "/config", root + "/state"
    project = tempfile.mkdtemp(prefix="probe-questions-")
    os.makedirs(config + "/ask")
    with open(config + "/ask/config.json", "w") as file:
        json.dump({"ui": {"inputPrefix": "ask> "}}, file)
    questions = {"questions": [{"question": f"Pick for {word}?", "header": word, "choices": [{"label": "yes"}, {"label": "no"}]}
                               for word in WORDS]}
    turn = probe.agent.turn
    server = probe.agent.Server([turn([("call", "q1", "question", questions)], "tool_use"),
                                 turn([("text", "NOTED ALL")], "end_turn")])
    environment = probe.agent.environment(state, server.url, config=config)
    terminal = None
    try:
        terminal = probe.Terminal(project, environment, columns=60, rows=30)
        terminal.until(lambda: "ask>" in terminal.text())
        terminal.send(b"Plan it\r")
        terminal.until(lambda: "Enter next" in terminal.text())
        row = tab_row(terminal)
        check("the shown question keeps its header, the others their initial",
              "[Alpha]" in row and " B " in row and "Bravo" not in row, row)
        check("and, too many for the row, a › marks those left out", row.rstrip().endswith("›"), row)
        check("the row fits the screen", len(row.rstrip()) <= 60, row)
        terminal.draw(lambda: terminal.send(b"\x1b[Z"))  # Shift+Tab, as back-tab: from the choices back to the tabs
        terminal.draw(lambda: terminal.send(b"\x1b[C"))
        row = tab_row(terminal)
        check("Right shows the next, now in full", "[Bravo]" in row and "Alpha" not in row and " A " in row, row)
        terminal.send(b"\t")
        for _ in WORDS[1:]:
            terminal.draw(lambda: terminal.send(b" \r"))
        terminal.until(lambda: "Enter sends" in terminal.text())
        check("after the sixteenth, the review", "Papa: yes" in terminal.text(), terminal.text())
        terminal.send(b"\r")
        terminal.until(lambda: "NOTED ALL" in terminal.text())
        sent = json.dumps(server.requests[1]["body"]["messages"][-1])
        check("the model gets sixteen answers", all(f"{word}:" in sent for word in WORDS), sent[:400])
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
