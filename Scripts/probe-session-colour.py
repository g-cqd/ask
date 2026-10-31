#!/usr/bin/env python3
"""ui.sessionColor (roadmap 0164) through the real binary in a PTY, read with pyte: the status line's background is the session's colour
with "always", plain with "off", and with "others" coloured only while another process called ask runs (a copy of sleep named ask).

    ASK_PYTE=/tmp/ask-pty/lib python3 Scripts/probe-session-colour.py [.build/release/ask]
"""
import os, pty, select, shutil, signal, subprocess, sys, tempfile, time

sys.path.insert(0, os.environ.get("ASK_PYTE", "/tmp/ask-pty/lib"))
import pyte
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probe_keychain

BINARY = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".build/release/ask")
ROWS, COLUMNS = 24, 100
failures = []


def check(label, condition, detail=""):
    print(("PASS " if condition else "FAIL ") + label + ("" if condition else f": {detail}"))
    if not condition:
        failures.append(label)


def status_background(setting, seconds=6.0):
    """Starts ask with `setting`, waits up to `seconds` for the status row to settle, and returns its backgrounds and its text."""
    root = tempfile.mkdtemp(prefix="ask-colour-")
    project, config, state, home = (os.path.join(root, n) for n in ("project", "config", "state", "home"))
    for path in (project, os.path.join(config, "ask"), state, home):
        os.makedirs(path)
    with open(os.path.join(config, "ask", "config.json"), "w") as file:
        file.write('{"ui": {"inputPrefix": "ask> "%s}}' % (f', "sessionColor": "{setting}"' if setting else ""))
    pid, fd = pty.fork()
    if pid == 0:
        import fcntl, struct, termios
        fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLUMNS, 0, 0))
        os.chdir(project)
        env = {k: v for k, v in os.environ.items() if not k.startswith(("ASK_", "ANTHROPIC_", "OPENAI_"))}
        env.update(TERM="xterm-256color", XDG_CONFIG_HOME=config, XDG_STATE_HOME=state, HOME=home)
        env["ASK_KEYCHAIN_PATH"] = probe_keychain.throwaway_keychain()  # never the person's keychain
        os.execve(BINARY, [BINARY], env)
    screen, stream = pyte.Screen(COLUMNS, ROWS), pyte.ByteStream()
    stream.attach(screen)
    end = time.time() + seconds
    try:
        while time.time() < end:
            if select.select([fd], [], [], 0.05)[0]:
                try:
                    stream.feed(os.read(fd, 1 << 16))
                except OSError:
                    break
        row = max(r for r in range(ROWS) if screen.display[r].strip())
        return {screen.buffer[row][c].bg for c in range(COLUMNS)}, screen.display[row].strip()
    finally:
        os.kill(pid, signal.SIGKILL)
        os.waitpid(pid, 0)
        shutil.rmtree(root, ignore_errors=True)


always, text = status_background("always")
check("always: the status line has a colour", always != {"default"}, (always, text))
off, _ = status_background(None)
check("off by default: the status line is plain", off == {"default"}, off)
running = subprocess.run(["ps", "-axo", "comm="], capture_output=True, text=True).stdout.split("\n")
if any(os.path.basename(name.strip()) == "ask" for name in running):
    print("SKIP others, alone: other ask processes are running on this Mac, so the alone case cannot be made here")
else:
    others, _ = status_background("others")
    check("others, alone: plain", others == {"default"}, others)
stand_in = os.path.join(tempfile.mkdtemp(), "ask")
shutil.copy("/bin/sleep", stand_in)
other = subprocess.Popen([stand_in, "60"])
try:
    together, _ = status_background("others")
    check("others, with another ask running: coloured", together != {"default"}, together)
finally:
    other.kill()
sys.exit(1 if failures else 0)
