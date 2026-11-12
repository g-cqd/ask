#!/usr/bin/env python3
"""Probe encrypted sessions (ADR-0138, roadmap 0182) through the real binary, a PTY and a local fake provider.

Scripts/probe-session-encryption.py .build/release/ask

A fresh state: the first-start questions asked inside the screen once it is drawn (idea i1) and answered there: yes, the key not
remembered, a password typed twice as hidden input, the recovery code read off the question that shows it and gone once answered; one
prompt answered. Then the files: framed and encrypted, no prompt or answer in clear, keys.json private, the answer
kept. Then `--continue` opened with the password, `--continue` after three wrong passwords with the recovery code, and `ask sessions`,
which has no keys, listing the session as locked. Throwaway keychain, state and config; nothing of the person's.
"""
import glob
import importlib.util
import json
import os
import re
import stat
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("fold_probe", os.path.join(HERE, "probe-folding.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
PASSWORD = "a long enough password"


def wait_raw(terminal, text):
    terminal.until(lambda: text.encode() in bytes(terminal.raw))


def answer(terminal, question, reply):
    wait_raw(terminal, question)
    start = len(terminal.raw)
    terminal.send(reply.encode() + b"\r")
    return start


def screen_has(terminal, text):
    terminal.until(lambda: text in terminal.text())


def choose(terminal, question, number):
    """A question of the screen's picker answered: its choice by number, then Enter (one question has no review)."""
    screen_has(terminal, question)
    for key in (str(number).encode(), b"\r"):
        terminal.send(key)
        probe.time.sleep(0.15)
    terminal.until(lambda: question not in terminal.text())


def type_hidden(terminal, prompt, text):
    """A hidden answer: typed, sent, and acknowledged on the screen without its text."""
    screen_has(terminal, prompt)
    received = terminal.text().count("Received (hidden).")
    terminal.send(text.encode() + b"\r")
    terminal.until(lambda: terminal.text().count("Received (hidden).") > received)


def declined():
    """The first-start question closed with Esc: this run's session is plain, and nothing is kept, so the next start asks again."""
    root = tempfile.TemporaryDirectory()
    project, config, state = root.name + "/project", root.name + "/config", root.name + "/state"
    os.makedirs(project)
    os.makedirs(config + "/ask")
    with open(config + "/ask/config.json", "w") as file:
        json.dump({"ui": {"inputPrefix": "ask> "}}, file)
    server = probe.agent.Server([probe.agent.turn([("text", "PLAIN ANSWER")], "end_turn")])
    environment = probe.agent.environment(state, server.url, config=config)
    environment.pop("ASK_SESSION_ENCRYPTION")
    environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")
    terminal = probe.Terminal(project, environment)
    screen_has(terminal, "Encrypt your ask sessions?")
    terminal.send(b"\x1b")
    terminal.until(lambda: "Encrypt your ask sessions?" not in terminal.text())
    for character in "hello":
        terminal.send(character.encode())
    terminal.send(b"\r")
    screen_has(terminal, "PLAIN ANSWER")
    terminal.close()
    sessions = glob.glob(state + "/ask/sessions/*/*.jsonl")
    probe.check("closing the question leaves this run's session plain",
                len(sessions) == 1 and b"PLAIN ANSWER" in open(sessions[0], "rb").read())
    probe.check("and keeps no answer, so the next start asks again", not os.path.exists(state + "/ask/session-encryption.json"))


def main():
    root = tempfile.TemporaryDirectory()
    project, config, state = root.name + "/project", root.name + "/config", root.name + "/state"
    os.makedirs(project)
    os.makedirs(config + "/ask")
    with open(config + "/ask/config.json", "w") as file:
        json.dump({"ui": {"inputPrefix": "ask> "}}, file)
    server = probe.agent.Server([probe.agent.turn([("text", "THE ANSWER IS FORTY-TWO")], "end_turn")])
    environment = probe.agent.environment(state, server.url, config=config)
    environment.pop("ASK_SESSION_ENCRYPTION")  # the first-start question is what this probe is about
    environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty")

    first = probe.Terminal(project, environment)
    screen_has(first, "Encrypt your ask sessions?")
    probe.check("the first-start question is asked inside the screen, once it is drawn", "ask>" in first.text())
    choose(first, "Encrypt your ask sessions?", 1)
    choose(first, "Keep the key in your keychain", 2)
    type_hidden(first, "Password:", PASSWORD)
    probe.check("a typed password is never on the screen", PASSWORD not in first.text())
    type_hidden(first, "Again:", PASSWORD)
    screen_has(first, "Press Return")
    code = re.search(r"[A-Z2-7]{4}(?:-[A-Z2-7]{4}){12}", first.text())
    probe.check("the recovery code is shown once, in 13 groups", code is not None)
    first.send(b"\r")
    first.until(lambda: "Press Return" not in first.text())
    probe.check("the recovery code is gone from the screen once kept", code.group(0) not in first.text())
    screen_has(first, "ask>")
    for character in "what is the answer":
        first.send(character.encode())
    first.send(b"\r")
    screen_has(first, "FORTY-TWO")
    first.close()

    sessions = glob.glob(state + "/ask/sessions/*/*.jsonl")
    probe.check("one session was written", len(sessions) == 1)
    data = open(sessions[0], "rb").read()
    probe.check("the session file is framed", data.startswith(b"ASKF"))
    probe.check("neither the prompt nor the answer is in the file in clear", b"what is the answer" not in data and b"FORTY-TWO" not in data)
    keys = state + "/ask/keys.json"
    probe.check("keys.json is private to the person", stat.S_IMODE(os.stat(keys).st_mode) == 0o600)
    probe.check("keys.json holds no password", PASSWORD.encode() not in open(keys, "rb").read())
    choice = json.load(open(state + "/ask/session-encryption.json"))
    probe.check("the first-start answer is kept", choice == {"encrypt": True, "remember": False})

    second = probe.Terminal(project, environment, resume=True)
    answer(second, "Password for your encrypted ask sessions:", PASSWORD)
    screen_has(second, "FORTY-TWO")
    probe.check("--continue opens the encrypted session with the password", "FORTY-TWO" in second.text())
    second.close()

    third = probe.Terminal(project, environment, resume=True)
    for _ in range(3):
        start = answer(third, "Password for your encrypted ask sessions:", "wrong password")
        third.until(lambda: b"not the password" in bytes(third.raw)[start:])
    answer(third, "Your recovery code", code.group(0).lower().replace("-", " "))
    screen_has(third, "FORTY-TWO")
    probe.check("after three wrong passwords, the recovery code opens it, however typed", "FORTY-TWO" in third.text())
    third.close()

    listed = subprocess.run([probe.BINARY, "sessions"], cwd=project, env=environment, capture_output=True, text=True,
                            stdin=subprocess.DEVNULL, timeout=30)
    probe.check("ask sessions, with no keys, lists the session as locked", "locked" in listed.stdout)
    declined()
    print("ok: encrypted sessions, set up, written, reopened with the password and with the recovery code, listed as locked")


if __name__ == "__main__":
    main()
