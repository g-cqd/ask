#!/usr/bin/env python3
"""A terminal resize after /reload is handled (roadmap 0132) through the real binary, a scripted provider and a PTY.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-reload-resize.py .build/release/ask

`/reload` replaces the process with the new build. The thread that does it had SIGWINCH, SIGTERM and SIGINT blocked, and `execve` gave
that mask to the new process, whose threads all inherited it, so a resize was never delivered and the screen was left torn. The probe
reloads into a copy of the binary, resizes the terminal, and requires a full repaint at the new size, in the new process, twice; it
also sends the new process SIGTERM and requires it to leave. pyte, not a physical terminal.
"""
import fcntl
import importlib.util
import os
import shutil
import signal
import struct
import sys
import tempfile
import termios
import time

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("probe_folding", os.path.join(HERE, "probe-folding.py"))
folding = importlib.util.module_from_spec(spec)
spec.loader.exec_module(folding)
agent, check = folding.agent, folding.check
BINARY = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".build/release/ask")


def install_build(directory):
    staged = os.path.join(directory, ".ask.new")
    shutil.copy2(BINARY, staged)
    os.rename(staged, os.path.join(directory, "ask"))
    return os.path.join(directory, "ask")


def main():
    with tempfile.TemporaryDirectory() as root:
        project, config, bins = os.path.realpath(root) + "/p", root + "/c", root + "/bin"
        for path in (project, config + "/ask", bins):
            os.makedirs(path)
        open(config + "/ask/config.json", "w").write('{"ui":{"prompt":"ask> "}}')
        folding.BINARY = install_build(bins)
        server = agent.Server([agent.turn([("text", "Answer 1.")], "end_turn")])
        environment = agent.environment(root + "/state", server.url, config=config)
        environment.update(TERM="xterm-256color", TERM_PROGRAM="ghostty", LANG="en_US.UTF-8")
        terminal = folding.Terminal(project, environment, columns=100, rows=30)
        try:
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.send(b"one\r")
            terminal.until(lambda: "Answer 1." in terminal.text())
            install_build(bins)  # a new build appears beside the running one
            time.sleep(1.5)
            terminal.send(b"/reload\r")
            deadline = time.time() + 40
            while time.time() < deadline and "Answer 1." in terminal.text() and not reloaded(terminal):
                terminal.pump()
            check("the process was replaced by the new build", reloaded(terminal))
            for columns, rows in ((70, 24), (120, 34), (90, 28), (60, 20)):
                start = len(terminal.raw)
                terminal.screen.resize(rows, columns)
                fcntl.ioctl(terminal.fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, columns, 0, 0))
                end = time.time() + 5
                while time.time() < end and b"\x1b[?2026l" not in bytes(terminal.raw)[start:]:
                    terminal.pump()
                for _ in range(10):
                    terminal.pump()
                drawn = b"\x1b[?2026l" in bytes(terminal.raw)[start:]
                if os.environ.get("PROBE_SHOW"):
                    print("resize", columns, rows, "drawn", drawn, "bytes", len(terminal.raw) - start, "rules", [len(l.rstrip()) for l in terminal.screen.display if l and set(l.rstrip()) == {"─"}])
                rules = [line for line in terminal.screen.display if line and set(line.rstrip()) == {"─"}]
                check(f"after reload, a resize to {columns}x{rows} is repainted at the new size",
                      drawn and len(rules) >= 2 and all(len(line.rstrip()) == columns for line in rules)
                      and "ask>" in terminal.text() and "· ↑" in terminal.screen.display[rows - 1])
            os.kill(terminal.pid, signal.SIGTERM)
            end = time.time() + 5
            alive = True
            while time.time() < end and alive:
                try:
                    pid, _ = os.waitpid(terminal.pid, os.WNOHANG)
                    alive = pid == 0
                except ChildProcessError:
                    alive = False
                terminal.pump() if alive else None
            check("and SIGTERM, which the same mask held back, reaches it", not alive)
        except (AssertionError, StopIteration):
            print(terminal.text(), file=sys.stderr)
            raise
        finally:
            try:
                terminal.close()
            except Exception:
                pass
            server.httpd.shutdown()


def reloaded(terminal):
    import subprocess
    command = subprocess.run(["ps", "-o", "command=", "-p", str(terminal.pid)], capture_output=True, text=True).stdout
    return "--reloaded-from" in command


if __name__ == "__main__":
    main()
