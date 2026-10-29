#!/usr/bin/env python3
"""Live probe of the interactive screen with Antigravity, through the real binary, a PTY and a terminal emulator.

ASK_LIVE_AGY=1 ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-agy-live.py .build/release/ask

Opt-in, because it sends real requests with the signed-in Antigravity account (about a dozen small ones) and reads the real
credentials. Sessions go to a throwaway state directory, and the project is a throwaway one. Nothing printed is a token. The
emulator shows what ask's bytes draw, not a physical terminal's rendering (ADR-0109 left the interactive screen unexercised).
"""
import importlib.util
import os
import random
import signal
import sys
import tempfile
import time

if os.environ.get("ASK_LIVE_AGY") != "1":
    print("SKIP: set ASK_LIVE_AGY=1 to run this against the real Antigravity account")
    sys.exit(0)

HERE = os.path.dirname(os.path.abspath(__file__))
BINARY = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".build/release/ask")
MODEL = os.environ.get("ASK_LIVE_AGY_MODEL", "gemini-3-flash")
sys.argv = [sys.argv[0], BINARY]
spec = importlib.util.spec_from_file_location("fold_probe", os.path.join(HERE, "probe-folding.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


def lines(terminal):
    return [line.rstrip() for line in terminal.screen.display]


def transcript(terminal):
    """Every row but the status line and the prompt, which hold labels and the draft rather than the conversation."""
    return "\n".join(line for line in lines(terminal)[:-2])


def status(terminal):
    return next((line for line in lines(terminal) if "Shift: native selection" in line), "")


def settle(terminal, timeout=90):
    """Waits for the turn to finish: the status line says ready again after it said working."""
    deadline = time.monotonic() + timeout
    seen_working = False
    while time.monotonic() < deadline:
        terminal.pump()
        line = status(terminal)
        seen_working = seen_working or "working" in line
        if seen_working and "· ready" in line:
            # pyte has no scroll regions, so a diff renderer's screen is only right after a full repaint (as the other probes do).
            terminal.repaint()
            return
    raise AssertionError("the turn did not finish in time:\n" + terminal.text())


def say(terminal, text):
    terminal.send(text.encode() + b"\r")
    settle(terminal)


def command(terminal, text, model):
    """A slash command: it starts no turn, and the label in the status line follows the next request, so the notice is what says it took."""
    terminal.send(text.encode() + b"\r")
    terminal.until(lambda: "Model selected for this run: %s." % model in terminal.text())
    terminal.repaint()


def main():
    token = "%04d" % random.randint(0, 9999)
    first, second = "alpha-" + token, "omega-" + token
    content = "first line: %s\nsecond line: %s\n" % (first, second)
    with tempfile.TemporaryDirectory() as root:
        project = root + "/project"
        os.makedirs(project)
        with open(project + "/notes.txt", "w") as file:
            file.write(content)
        environment = dict(os.environ, XDG_STATE_HOME=root + "/state", TERM="xterm-256color", TERM_PROGRAM="ghostty",
                           ASK_PROVIDER="agy", ASK_MODEL=MODEL)
        for key in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID", "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"):
            environment.pop(key, None)
        terminal = probe.Terminal(project, environment, columns=100, rows=30)
        try:
            terminal.until(lambda: "ask>" in terminal.text())
            probe.check("the screen names the provider and model, and is ready", "agy/%s · ready" % MODEL in status(terminal))

            say(terminal, "Use the read tool to read notes.txt, then tell me the word after 'second line:'.")
            probe.check("a tool call is shown, finished", "read notes.txt ✓" in transcript(terminal))
            probe.check("the answer is what the file says", transcript(terminal).count(second) >= 1)
            probe.check("usage is shown for the turn", "in " in status(terminal) and "out " in status(terminal))

            command(terminal, "/model agy claude-sonnet-5-5-low", "claude-sonnet-5-5-low")
            say(terminal, "Without using any tool: what is the word after 'first line:' in notes.txt?")
            # The first line's word appears nowhere else on the screen: the earlier question asked only for the second.
            probe.check("a history that holds a Gemini signature is answered by Claude, from the earlier tool result",
                        transcript(terminal).count(first) >= 1)

            command(terminal, "/model agy " + MODEL, MODEL)
            size = len(content.encode())
            say(terminal, "Use the bash tool to run: wc -c < notes.txt, and tell me the number it printed.")
            probe.check("back on Gemini, with the Claude turn in the history, a new tool call works",
                        "bash" in transcript(terminal) and str(size) in transcript(terminal).split("wc -c")[-1])

            terminal.send(b"Write an essay of about 800 words on the sea, in many paragraphs.\r")
            terminal.until(lambda: "working" in status(terminal))
            time.sleep(5)
            terminal.pump()
            terminal.send(b"\x1b")
            terminal.until(lambda: "· ready" in status(terminal))
            terminal.repaint()
            probe.check("Esc aborts a streaming answer without a block, and returns to the prompt",
                        "Aborted" not in transcript(terminal) and lines(terminal)[-1].startswith("ask>"))
            marker = "pong-" + token
            say(terminal, "Reply with exactly this one word and nothing else: " + marker)
            probe.check("the next turn after an abort works", transcript(terminal).count(marker) >= 2)

            terminal.send(b"\x03")
            deadline = time.monotonic() + 10
            code = None
            while time.monotonic() < deadline:
                terminal.pump()
                done, state = os.waitpid(terminal.pid, os.WNOHANG)
                if done:
                    code = os.waitstatus_to_exitcode(state)
                    break
            probe.check("Ctrl-C at an idle prompt quits with exit 0", code == 0)
            os.close(terminal.fd)
            terminal = None
        finally:
            if terminal is not None:
                terminal.close()
    print("ALL PASS")


if __name__ == "__main__":
    main()
