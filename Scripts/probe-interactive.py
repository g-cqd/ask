#!/usr/bin/env python3
"""End-to-end probe of the interactive screen over a PTY, against a local fake Anthropic server.

A: type a prompt; the screen shows it, the tool call, and the answer; the tool's effect is on disk.
B: a command that runs until stopped; Esc aborts it, its backgrounded child dies, and the screen says so.
C: Ctrl-C at an idle prompt quits, exit 0, with the terminal restored (the teardown bytes end the output).

Usage: Scripts/probe-interactive.py .build/release/ask
"""
import importlib.util, os, pty, select, signal, struct, sys, tempfile, time, fcntl, termios

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("agent_probe", os.path.join(here, "probe-agent-run.py"))
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)
ASK = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".build/release/ask")
FRAME_END = b"\x1b[?2026l"
ROWS, COLUMNS = 30, 100


class Emulator:
    """Just enough of a terminal to read a diff renderer's screen: cursor moves, text, erase. Bytes alone cannot
    show what is on screen, because a diff sends only the cells that changed."""

    def __init__(self):
        self.grid = [[" "] * COLUMNS for _ in range(ROWS)]
        self.row = self.column = 0
        self.pending = b""

    def feed(self, data):
        data = self.pending + data
        self.pending = b""
        i = 0
        while i < len(data):
            byte = data[i]
            if byte == 0x1B:
                end = i + 1
                if end >= len(data):
                    self.pending = data[i:]
                    return
                if data[end] == ord("["):
                    j = end + 1
                    while j < len(data) and not (0x40 <= data[j] <= 0x7E):
                        j += 1
                    if j >= len(data):
                        self.pending = data[i:]
                        return
                    self.control(data[end + 1:j].decode(errors="replace"), chr(data[j]))
                    i = j + 1
                    continue
                i = end + 1
                continue
            if byte == 0x0D:
                self.column = 0
            elif byte == 0x0A:
                self.row = min(ROWS - 1, self.row + 1)
            elif byte >= 0x20:
                length = 1 if byte < 0x80 else 2 if byte >> 5 == 0b110 else 3 if byte >> 4 == 0b1110 else 4
                if i + length > len(data):
                    self.pending = data[i:]
                    return
                if self.row < ROWS and self.column < COLUMNS:
                    self.grid[self.row][self.column] = data[i:i + length].decode(errors="replace")
                self.column += 1
                i += length
                continue
            i += 1

    def control(self, params, final):
        if params.startswith("?"):
            return
        numbers = [int(n) if n else 0 for n in params.split(";")] if params else []
        if final == "H":
            self.row = max(1, numbers[0] if numbers else 1) - 1
            self.column = max(1, numbers[1] if len(numbers) > 1 else 1) - 1
        elif final == "J":
            self.grid = [[" "] * COLUMNS for _ in range(ROWS)]
        elif final == "K":
            for c in range(self.column, COLUMNS):
                self.grid[self.row][c] = " "

    def text(self):
        return "\n".join("".join(line).rstrip() for line in self.grid)


class Screen:
    def __init__(self, server_url, project, state=None, arguments=()):
        self.state = state or tempfile.mkdtemp()
        env = agent.environment(self.state, server_url)
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.chdir(project)
            os.execve(ASK, [ASK, *arguments], env)
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLUMNS, 0, 0))
        self.output = b""
        self.screen = Emulator()

    def until(self, text, seconds=15):
        """Read until the screen, as of the last complete frame, shows `text`."""
        end = time.time() + seconds
        while time.time() < end:
            if self.output.endswith(FRAME_END) and text in self.screen.text():
                return True
            if select.select([self.fd], [], [], 0.05)[0]:
                try:
                    chunk = os.read(self.fd, 65536)
                except OSError:
                    return False
                if not chunk:
                    return False
                self.output += chunk
                self.screen.feed(chunk)
        return False

    def status(self):
        """The status line: the inverse bar just above the prompt."""
        lines = self.screen.text().split("\n")
        return next((line for line in reversed(lines) if " · " in line), "")

    def until_status(self, word, seconds=15):
        end = time.time() + seconds
        while time.time() < end:
            if word in self.status() and self.output.endswith(FRAME_END):
                return True
            self.until("\x00", 0.05)
        return False

    def type(self, text):
        os.write(self.fd, text.encode())

    def finish(self, seconds=10):
        end = time.time() + seconds
        while time.time() < end:
            done, status = os.waitpid(self.pid, os.WNOHANG)
            if done:
                try:
                    while select.select([self.fd], [], [], 0.05)[0]:
                        chunk = os.read(self.fd, 65536)
                        if not chunk:
                            break
                        self.output += chunk
                except OSError:
                    pass
                return os.waitstatus_to_exitcode(status)
            if select.select([self.fd], [], [], 0.05)[0]:
                try:
                    self.output += os.read(self.fd, 65536)
                except OSError:
                    pass
        os.kill(self.pid, signal.SIGKILL)
        return None


def check(label, condition, detail=""):
    return agent.check(label, condition, detail)


def probe_turn():
    print("A: a turn on screen")
    project = tempfile.mkdtemp()
    server = agent.Server([agent.turn([("tool", "t1", "echo screen-ok > out.txt")], "tool_use"),
                           agent.turn([("text", "All done here.")], "end_turn")])
    screen = Screen(server.url, project)
    results = [check("prompt drawn", screen.until("ask>"))]
    screen.type("Write the file\r")
    results.append(check("prompt in the transcript", screen.until("› Write the file")))
    results.append(check("tool call shown, succeeded", screen.until("▸ bash echo screen-ok > out.txt ✓")))
    results.append(check("answer streamed", screen.until("All done here.")))
    results.append(check("back to ready", screen.until_status("ready")))
    results.append(check("file written", os.path.exists(os.path.join(project, "out.txt"))))
    screen.type("\x03")
    results.append(check("quits on Ctrl-C", screen.finish() == 0))
    server.httpd.shutdown()
    return all(results)


def probe_abort():
    print("B: Esc aborts a running command")
    project = tempfile.mkdtemp()
    server = agent.Server([agent.turn([("tool", "t1", "sleep 300 & echo $! > child.pid; wait")], "tool_use")])
    screen = Screen(server.url, project)
    screen.until("ask>")
    screen.type("Run it\r")
    pid_file = os.path.join(project, "child.pid")
    deadline = time.time() + 20
    while not (os.path.exists(pid_file) and open(pid_file).read().strip()) and time.time() < deadline:
        screen.until("\x00", 0.05)
    child = int(open(pid_file).read())
    results = [check("working shown", screen.until_status("working"))]
    screen.type("\x1b")
    results.append(check("abort reported", screen.until("Aborted. Results already known were kept.")))
    results.append(check("tool shown as stopped", screen.until("[aborted; the command and its children were stopped]")))
    results.append(check("back to ready", screen.until_status("ready")))
    alive = True
    end = time.time() + 5
    while alive and time.time() < end:
        try:
            os.kill(child, 0)
            time.sleep(0.02)
        except ProcessLookupError:
            alive = False
    results.append(check("backgrounded child stopped", not alive, f"pid {child}"))
    if alive:
        os.kill(child, signal.SIGKILL)
    screen.type("\x03")
    results.append(check("quits afterwards", screen.finish() == 0))
    server.httpd.shutdown()
    return all(results)


def probe_quit():
    print("C: idle Ctrl-C restores the terminal")
    screen = Screen("http://127.0.0.1:9", tempfile.mkdtemp())
    screen.until("ask>")
    screen.type("\x03")
    code = screen.finish()
    # Teardown: end of frame, cursor shown, then the reset ladder's first tier (leaves the alternate screen).
    results = [check("exit 0", code == 0, code),
               check("left the alternate screen", b"\x1b[?1049l" in screen.output[-200:]),
               check("cursor shown", b"\x1b[?25h" in screen.output[-200:])]
    return all(results)


def probe_resume():
    print("D: --continue shows the earlier conversation and carries it on")
    project, state = tempfile.mkdtemp(), tempfile.mkdtemp()
    server = agent.Server([agent.turn([("tool", "t1", "echo kept > kept.txt")], "tool_use"),
                           agent.turn([("text", "First answer.")], "end_turn"),
                           agent.turn([("text", "Second answer.")], "end_turn")])
    first = Screen(server.url, project, state)
    first.until("ask>")
    first.type("Remember KIWI\r")
    first.until("First answer.")
    first.until_status("ready")
    first.type("\x03")
    first.finish()
    resumed = Screen(server.url, project, state, ["--continue"])
    results = [check("says which session it resumed", resumed.until("Resumed session 20")),
               check("earlier prompt shown", resumed.until("› Remember KIWI")),
               check("earlier tool call shown, succeeded", resumed.until("▸ bash echo kept > kept.txt ✓")),
               check("earlier answer shown", resumed.until("First answer.")),
               check("usage so far on the status line", "% cached" in resumed.status(), resumed.status())]
    resumed.type("And now?\r")
    results.append(check("new answer streamed", resumed.until("Second answer.")))
    resumed.until_status("ready")
    resumed.type("\x03")
    results.append(check("quits on Ctrl-C", resumed.finish() == 0))
    if check("three requests", len(server.requests) == 3, len(server.requests)):
        texts = [b.get("text", "") for m in server.requests[2]["body"]["messages"] for b in m["content"]]
        results.append(check("the earlier exchange is sent again", "Remember KIWI" in texts
                             and "First answer." in texts, texts))
    results.append(check("still one session", len(agent.sessions(state)) == 1, agent.sessions(state)))
    server.httpd.shutdown()
    return all(results)


if __name__ == "__main__":
    ok = probe_turn() & probe_abort() & probe_quit() & probe_resume()
    print("PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)
