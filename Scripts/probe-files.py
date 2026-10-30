#!/usr/bin/env python3
"""Probe the `@` file picker (roadmap 0048, ADR-0069) through the real binary, a PTY and a local fake provider.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-files.py .build/release/ask [--control OLDER_BINARY]

The project is a real git repository: tracked files, an untracked one, an ignored directory, a name with a space, and a directory the
user's configuration hides from the sandbox. With --control, an older binary (before the picker) must show no list.
"""
import importlib.util
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("picker_probe", os.path.join(HERE, "probe-picker.py"))
saved = sys.argv
sys.argv = [saved[0], saved[1]]
pp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pp)
sys.argv = saved
check = pp.check
type_text, press, rows, prompt_row = pp.type_text, pp.press, pp.rows, pp.prompt_row

FILES = {
    "README.md": "readme\n", "src/main.swift": "print(1)\n", "docs/readme-notes.md": "notes\n", "My Docs/a b.txt": "spaced\n",
    ".gitignore": "out/\n", "out/gen.txt": "generated\n", "secret/key.pem": "KEY\n", "secret/token.txt": "TOKEN\n",
}


def prepare(project):
    for path, text in FILES.items():
        full = os.path.join(project, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w") as file:
            file.write(text)
    run = lambda *args: subprocess.run(["git", "-c", "user.email=t@t", "-c", "user.name=t", *args], cwd=project,
                                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    run("init", "-q")
    run("add", "README.md", "src/main.swift", "docs/readme-notes.md", "My Docs/a b.txt", ".gitignore", "secret/key.pem",
        "secret/token.txt")
    with open(os.path.join(project, "untracked.md"), "w") as file:  # in the project, in no commit
        file.write("untracked\n")


def settings(project):
    return {"sandbox": {"hide": [project + "/secret"]}}


def files_title(terminal):
    return next((i for i, line in enumerate(rows(terminal)) if line.startswith("files")), None)


def listed(terminal):
    shown, top = rows(terminal), files_title(terminal)
    if top is None:
        return [], None
    out = []
    for line in shown[top + 1:]:
        if line.startswith("ask>"):
            break
        out.append(line)
    return out, top


def wait_for_list(terminal):
    """Typing `@` shows a placeholder until the listing arrives; wait for real rows, repainting as the screen settles."""
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        names, top = listed(terminal)
        if top is not None and names:
            return names, top
        terminal.pump()
        terminal.repaint()
    raise AssertionError("the file list never arrived:\n" + terminal.text())


def main():
    binary = os.path.abspath(sys.argv[1])
    if "--control" in sys.argv:
        with pp.Session(sys.argv[sys.argv.index("--control") + 1], [], prepare=prepare) as session:
            type_text(session.terminal, "@")
            check("control (a binary without the picker): an at sign opens no list", files_title(session.terminal) is None)

    turns = [pp.short_answer("GOT PROMPT"), pp.short_answer("GOT SECOND")]
    with pp.Session(binary, turns, prepare=prepare, settings=settings) as session:
        terminal = session.terminal
        type_text(terminal, "@")
        names, top = wait_for_list(terminal)
        check("an at sign lists the project's files above the prompt", top is not None and prompt_row(terminal) == "ask> @")
        check("tracked and untracked files are listed", {"README.md", "src/main.swift", "untracked.md"} <= set(names))
        check("an ignored directory, git's own files and the sandbox-hidden directory are not listed",
              not any(n.startswith(("out/", ".git/", "secret/")) for n in names))
        check("the title says how many files the sandbox hid", "2 hidden by the sandbox" in rows(terminal)[top])

        type_text(terminal, "read")
        names, top = wait_for_list(terminal)
        check("typing narrows it, a path that starts with the query first", names[0] == "README.md" and "docs/readme-notes.md" in names)
        check("the filter is the draft itself", prompt_row(terminal) == "ask> @read")

        baseline = session.requests()
        press(terminal, b"\r")
        check("Enter inserts the chosen path and does not send it",
              prompt_row(terminal) == "ask> @README.md" and files_title(terminal) is None and session.requests() == baseline)
        press(terminal, b"\x18")

        type_text(terminal, "@read:3-9")
        wait_for_list(terminal)
        press(terminal, b"\t")
        check("Tab completes, and a line range typed after the path is kept",
              prompt_row(terminal) == "ask> @README.md:3-9" and session.requests() == baseline)
        press(terminal, b"\x18")

        type_text(terminal, "@secret")
        check("a file the sandbox hides is neither listed nor findable by name", files_title(terminal) is None)
        press(terminal, b"\x18")

        type_text(terminal, "@my")
        wait_for_list(terminal)
        press(terminal, b"\r")
        check("a name with a space is inserted quoted, so the space does not end the word",
              prompt_row(terminal) == 'ask> @"My Docs/a b.txt"')
        press(terminal, b"\x18")

        type_text(terminal, "me@read")
        check("an at sign inside a word is text, not a trigger", files_title(terminal) is None)
        press(terminal, b"\x18")

        type_text(terminal, "@rea")
        wait_for_list(terminal)
        press(terminal, b"\x1b")
        type_text(terminal, "d")
        check("Escape closes it, keeps the text, and typing on does not reopen it",
              files_title(terminal) is None and prompt_row(terminal) == "ask> @read")
        press(terminal, b"\x18")

        type_text(terminal, "look at @README.md")
        check("a path typed in full closes the list", files_title(terminal) is None)
        press(terminal, b"\r")
        terminal.until(lambda: "GOT PROMPT" in terminal.text())
        check("so Enter sends the prompt, with the reference as typed", "look at @README.md" in session.sent_texts())

        # A file that appears later is found once the listing is old (ten seconds), without leaving the screen.
        with open(os.path.join(session.project, "later.txt"), "w") as file:
            file.write("later\n")
        time.sleep(11)
        type_text(terminal, "@later")
        deadline = time.monotonic() + 15
        found = False
        while time.monotonic() < deadline and not found:
            terminal.pump()
            terminal.repaint()
            found = "later.txt" in listed(terminal)[0]
        check("a file created after the first listing is found once that listing has aged", found)
        press(terminal, b"\x18")

    with pp.Session(binary, [pp.short_answer("GOT SMALL")], columns=80, height=11, prepare=prepare) as session:
        terminal = session.terminal
        type_text(terminal, "@read")
        check("a screen too short for the list does not show one", files_title(terminal) is None)
        press(terminal, b"\r")
        terminal.until(lambda: "GOT SMALL" in terminal.text())
        check("and Enter keeps its ordinary meaning there", "@read" in session.sent_texts())

    print(f"{len(pp.checks)} checks passed")


if __name__ == "__main__":
    main()
