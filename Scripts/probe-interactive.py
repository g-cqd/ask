#!/usr/bin/env python3
"""End-to-end probe of the interactive screen over a PTY, against a local fake Anthropic server.

A: type a prompt; the screen shows it, the tool call, and the answer; the tool's effect is on disk.
B: a command that runs until stopped; Esc leaves it alone, Ctrl-C stops it, its backgrounded child dies, and the screen says so.
C: a double Ctrl-C at an idle prompt quits, exit 0, with the terminal restored (the teardown bytes end the output).

Usage: Scripts/probe-interactive.py .build/release/ask
"""
import json
import re
import subprocess
import shutil
import importlib.util, os, pty, select, signal, struct, sys, tempfile, time, fcntl, termios

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("agent_probe", os.path.join(here, "probe-agent-run.py"))
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)
ASK = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".build/release/ask")
FRAME_END = b"\x1b[?2026l"
ROWS, COLUMNS = 30, 100


_YES = {}


def yes_flag(binary):
    """`--yes` when `binary` has it (roadmap 0134), so a probe about something else is not stopped by approval questions; an older
    control binary has no such flag and asks nothing anyway."""
    if binary not in _YES:
        import subprocess as _subprocess
        shown = _subprocess.run([binary, "--help"], capture_output=True, text=True).stdout
        _YES[binary] = ["--yes"] if "--yes" in shown else []
    return _YES[binary]


class Emulator:
    """Just enough of a terminal to read a diff renderer's screen: cursor moves, text, erase, and the scroll
    region with scroll up and down. Bytes alone cannot show what is on screen, because a diff sends only the
    cells that changed. A scroll region matters: the transcript scrolls by `ESC[n S` inside `ESC[t;b r`, and
    an emulator that ignores it draws every new line over the last one."""

    def __init__(self):
        self.grid = [[" "] * COLUMNS for _ in range(ROWS)]
        self.row = self.column = 0
        self.top, self.bottom = 0, ROWS - 1
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
                if data[end] == ord("]"):
                    # OSC (a hyperlink, a colour query): nothing on screen, up to BEL or ESC \.
                    j = end + 1
                    while j < len(data) and data[j] != 0x07 and not (data[j] == 0x1B and j + 1 < len(data) and data[j + 1] == ord("\\")):
                        j += 1
                    if j >= len(data) or (data[j] == 0x1B and j + 1 >= len(data)):
                        self.pending = data[i:]
                        return
                    i = j + (1 if data[j] == 0x07 else 2)
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
        # A colon sub-parameter (`4:1`, an underline style) counts as its first number.
        numbers = [int(n.split(":")[0] or 0) for n in params.split(";")] if params else []
        if final == "H":
            self.row = max(1, numbers[0] if numbers else 1) - 1
            self.column = max(1, numbers[1] if len(numbers) > 1 else 1) - 1
        elif final == "J":
            self.grid = [[" "] * COLUMNS for _ in range(ROWS)]
        elif final == "K":
            for c in range(self.column, COLUMNS):
                self.grid[self.row][c] = " "
        elif final == "r":
            top = (numbers[0] if numbers and numbers[0] else 1) - 1
            bottom = (numbers[1] if len(numbers) > 1 and numbers[1] else ROWS) - 1
            self.top, self.bottom = (top, bottom) if 0 <= top < bottom < ROWS else (0, ROWS - 1)
            self.row = self.column = 0
        elif final in "ST":
            for _ in range(max(1, numbers[0] if numbers else 1)):
                blank = [" "] * COLUMNS
                if final == "S":
                    del self.grid[self.top]
                    self.grid.insert(self.bottom, blank)
                else:
                    del self.grid[self.bottom]
                    self.grid.insert(self.top, blank)

    def text(self):
        return "\n".join("".join(line).rstrip() for line in self.grid)


class Screen:
    def __init__(self, server_url, project, state=None, arguments=(), config=None, binary=None, approvals=False):
        self.state = state or tempfile.mkdtemp()
        env = agent.environment(self.state, server_url, config)
        binary = binary or ASK
        arguments = tuple(arguments) if approvals else tuple(yes_flag(binary)) + tuple(arguments)
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.chdir(project)
            os.execve(binary, [binary, *arguments], env)
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

    def idle(self):
        """Whether ask waits for a prompt: the status line leads with its idle mark (`✓` sandboxed, `!` not), where a turn shows a spinner (roadmap 0074 dropped the
        "ready" word and the `ask> ` prefix; the probe reads the screen's structure instead)."""
        return self.status().lstrip().startswith(("✓", "!", "Sandboxed", "Not sandboxed"))

    def ready(self, seconds=15):
        """Read until ask is idle at a drawn frame."""
        return self.until_status("ready", seconds)

    def editor_lines(self):
        """The input's rows: those between the last two rules."""
        lines = self.screen.text().split("\n")
        rules = [i for i, line in enumerate(lines) if line and set(line) == {"─"}]
        return lines[rules[-2] + 1:rules[-1]] if len(rules) >= 2 else []

    def until_editor(self, text, seconds=15):
        """Read until the input holds exactly `text` (rows joined by line feeds)."""
        end = time.time() + seconds
        while time.time() < end:
            if self.output.endswith(FRAME_END) and "\n".join(self.editor_lines()) == text:
                return True
            self.until("\x00", 0.05)
        return False

    def until_status(self, word, seconds=15):
        """Read until the status line says `word`. "ready" means idle, "X · ready" idle with X in the line, "working" not idle."""
        end = time.time() + seconds
        while time.time() < end:
            status = self.status()
            if word == "ready":
                matched = self.idle()
            elif word.endswith(" · ready"):
                matched = self.idle() and word[:-len(" · ready")] in status
            elif word == "working":
                matched = bool(status) and not self.idle()
            else:
                matched = word in status
            if matched and self.output.endswith(FRAME_END):
                return True
            self.until("\x00", 0.05)
        return False

    def tool_shown(self, command, mark, kind="shell"):
        """Whether a tool row shows `command` ending in `mark`: `shell · COMMAND …  N lines · ✓`, the mark at the row's right.
        `kind` is the row's first word: `shell`, or `compact` for /compact's row."""
        return any(f"{kind} · {command}" in line and line.rstrip().endswith(mark) for line in self.screen.text().split("\n"))

    def until_tool(self, command, mark="✓", seconds=15, kind="shell"):
        """Read until a tool row shows `command` with `mark` (see ``tool_shown``)."""
        end = time.time() + seconds
        while time.time() < end:
            if self.output.endswith(FRAME_END) and self.tool_shown(command, mark, kind):
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


def dismiss_thinking_offer(screen):
    """Closes the effort list a chosen model offers: /model fills the input with `/thinking ` (ADR-0117), and a prompt typed next would
    otherwise become that command's argument."""
    screen.until("\x00", 0.5)
    if any(line.lstrip().startswith("/thinking") for line in screen.editor_lines()):
        screen.type("\x1b\x15")
        screen.until_editor("")


def output_tokens(screen):
    """The output tokens the status line counts, `↓N`, or None when it shows no usage."""
    found = re.search(r"↓(\d+)", screen.status())
    return int(found.group(1)) if found else None


def check(label, condition, detail=""):
    return agent.check(label, condition, detail)


def probe_turn():
    print("A: a turn on screen")
    project = tempfile.mkdtemp()
    server = agent.Server([agent.turn([("tool", "t1", "echo screen-ok > out.txt")], "tool_use"),
                           agent.turn([("text", "All done here.")], "end_turn")])
    screen = Screen(server.url, project)
    results = [check("prompt drawn", screen.ready())]
    screen.type("Write the file\r")
    results.append(check("prompt in the transcript", screen.until("Write the file")))
    results.append(check("tool call shown, succeeded", screen.until_tool("echo screen-ok > out.txt")))
    results.append(check("answer streamed", screen.until("All done here.")))
    results.append(check("back to ready", screen.until_status("ready")))
    results.append(check("file written", os.path.exists(os.path.join(project, "out.txt"))))
    screen.type("abc")
    screen.until_editor("abc")
    screen.type("\x03")
    screen.until("\x00", 0.5)
    results.append(check("Ctrl-C with text erases it and neither quits nor arms the quit",
                         "abc" not in "\n".join(screen.editor_lines()) and "again to quit" not in screen.screen.text()))
    screen.type("\x03")
    screen.until("press Ctrl+C again to quit")
    screen.type("x")
    screen.until_editor("x")
    screen.until("\x00", 0.3)
    results.append(check("another key disarms the quit", "again to quit" not in screen.screen.text()))
    screen.type("\x03")
    screen.until("\x00", 0.3)
    screen.type("\x03")
    results.append(check("the first Ctrl-C only says it will quit", screen.until("press Ctrl+C again to quit")))
    screen.type("\x03")
    results.append(check("a second Ctrl-C quits", screen.finish() == 0))
    server.httpd.shutdown()
    return all(results)


def probe_abort():
    print("B: Ctrl-C stops a running command, and Esc does not")
    project = tempfile.mkdtemp()
    server = agent.Server([agent.turn([("tool", "t1", "sleep 300 & echo $! > child.pid; wait")], "tool_use")])
    screen = Screen(server.url, project)
    screen.ready()
    screen.type("Run it\r")
    pid_file = os.path.join(project, "child.pid")
    deadline = time.time() + 20
    while not (os.path.exists(pid_file) and open(pid_file).read().strip()) and time.time() < deadline:
        screen.until("\x00", 0.05)
    child = int(open(pid_file).read())
    results = [check("working shown", screen.until_status("working"))]
    screen.type("\x1b")
    screen.until("\x00", 1.0)
    results.append(check("Esc leaves the running command alone", not screen.idle() and "Aborted" not in screen.screen.text()))
    screen.type("\x03")
    # No block says so (roadmap 0142): the tool's row ends in ⊘, drawn orange; the text itself is what the model is sent.
    results.append(check("tool shown as interrupted", screen.until_tool("sleep 300 & echo", "⊘")))
    results.append(check("back to ready", screen.until_status("ready")))
    results.append(check("no Stopping or Aborted block",
                         "Stopping" not in screen.screen.text() and "Aborted" not in screen.screen.text()))
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
    screen.type("\x03\x03")
    results.append(check("quits afterwards", screen.finish() == 0))
    server.httpd.shutdown()
    return all(results)


def probe_quit():
    print("C: a double Ctrl-C when idle restores the terminal")
    screen = Screen("http://127.0.0.1:9", tempfile.mkdtemp())
    screen.ready()
    screen.type("\x03\x03")
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
    first.ready()
    first.type("Remember KIWI\r")
    first.until("First answer.")
    first.until_status("ready")
    first.type("\x03\x03")
    first.finish()
    # Which session it resumed is a detail, said with --verbose (ADR-0119).
    resumed = Screen(server.url, project, state, ["--continue", "--verbose"])
    results = [check("says which session it resumed", resumed.until("Resumed session 20")),
               check("earlier prompt shown", resumed.until("Remember KIWI")),
               check("earlier tool call shown, succeeded", resumed.until_tool("echo kept > kept.txt")),
               check("earlier answer shown", resumed.until("First answer.")),
               check("usage so far on the status line", re.search(r"↑[1-9]\d* ↓[1-9]", resumed.status()) is not None, resumed.status())]
    resumed.type("And now?\r")
    results.append(check("new answer streamed", resumed.until("Second answer.")))
    resumed.until_status("ready")
    resumed.type("\x03\x03")
    results.append(check("quits on a double Ctrl-C", resumed.finish() == 0))
    if check("three requests", len(server.requests) == 3, len(server.requests)):
        texts = [b.get("text", "") for m in server.requests[2]["body"]["messages"] for b in m["content"]]
        results.append(check("the earlier exchange is sent again", "Remember KIWI" in texts
                             and "First answer." in texts, texts))
    results.append(check("still one session", len(agent.sessions(state)) == 1, agent.sessions(state)))
    server.httpd.shutdown()
    return all(results)


def probe_signal_stops_jobs():
    print("E: SIGTERM with a job running restores the terminal and stops the job")
    project, port = tempfile.mkdtemp(), agent.free_port()
    server = agent.Server([
        agent.turn([("call", "t1", "bash", {"command": f"exec python3 -m http.server {port} --bind 127.0.0.1", "yield_seconds": 1})], "tool_use"),
        agent.turn([("call", "t2", "job", {"job": "job-1", "action": "wait", "wait_for_port": port, "timeout_seconds": 20})], "tool_use"),
        agent.turn([("text", "Serving.")], "end_turn")])
    screen = Screen(server.url, project)
    screen.ready()
    screen.type("Serve\r")
    results = [check("the job came up", screen.until("Serving.") and agent.accepts(port))]
    os.kill(screen.pid, signal.SIGTERM)
    code = screen.finish()
    results += [check("exit 143", code == 143, code),
                check("left the alternate screen", b"\x1b[?1049l" in screen.output[-300:]),
                check("the job is gone", not agent.accepts(port))]
    server.httpd.shutdown()
    return all(results)


def probe_reload():
    print("F: configuration edited while ask runs is reloaded before the next prompt")
    project, config = tempfile.mkdtemp(), tempfile.mkdtemp()
    os.makedirs(os.path.join(config, "ask"))
    user_file = os.path.join(config, "ask", "config.json")
    server = agent.Server([agent.turn([("text", f"Answer {i}.")], "end_turn") for i in range(1, 10)])
    # What changed on a reload is a detail, said with --verbose (ADR-0119); a broken file is said regardless.
    screen = Screen(server.url, project, config=config, arguments=["--verbose"])
    results = [check("prompt drawn", screen.ready())]

    def turn(prompt, answer):
        screen.type(prompt + "\r")
        ok = screen.until(answer)
        screen.until_status("ready")
        return ok

    results.append(check("a first prompt with no config file runs", turn("one", "Answer 1.")))
    open(user_file, "w").write("// raised\n{maxTurns: 7, model: 'reloaded-model'}\n")
    results.append(check("a second prompt runs", turn("two", "Answer 2.")))
    results += [check("the change is announced", screen.until("Configuration reloaded.")),
                check("with each setting and where it came from", screen.until("maxTurns: 100 → 7")),
                check("the status line follows the model", "reloaded-model" in screen.status(), screen.status())]
    if len(server.requests) >= 2:
        results.append(check("and the next request used the new model", server.requests[1]["body"]["model"] == "reloaded-model",
                             server.requests[1]["body"]["model"]))
    open(user_file, "w").write("{maxTurns: ]")
    turn("three", "Answer 3.")
    results.append(check("a broken edit is reported, keeping the old settings", screen.until("Configuration not reloaded:") and screen.until("Keeping the previous settings.")))
    turn("four", "Answer 4.")
    shown = screen.screen.text().count("Configuration not reloaded:")
    results.append(check("and reported once, not at every prompt", shown == 1, shown))
    results.append(check("the run still worked on the old settings", server.requests[3]["body"]["model"] == "reloaded-model"
                         if len(server.requests) >= 4 else False))
    open(user_file, "w").write("{maxTurns: 9, model: 'reloaded-model'}")
    turn("five", "Answer 5.")
    results.append(check("a fixed file reloads again, from the settings that were in force", screen.until("maxTurns: 7 → 9")))
    screen.type("\x03\x03")
    results.append(check("quits on a double Ctrl-C", screen.finish() == 0))
    server.httpd.shutdown()
    return all(results)


def probe_slash():
    print("G: slash commands")
    # The /config now report runs to some 45 rows: a taller screen keeps the setting under test in view.
    global ROWS
    saved, ROWS = ROWS, 80
    try:
        return slash_checks()
    finally:
        ROWS = saved


def slash_checks():
    project, config = tempfile.mkdtemp(), tempfile.mkdtemp()
    os.makedirs(os.path.join(config, "ask"))
    server = agent.Server([agent.turn([("text", "Answer 1.")], "end_turn"),
                           agent.turn([("text", "Answer 2.")], "end_turn"),
                           agent.turn([("text", "SUMMARY: the user pasted notes.")], "end_turn"),
                           agent.turn([("text", "Answer 4.")], "end_turn")])
    screen = Screen(server.url, project, config=config, arguments=["--verbose"])
    results = [check("prompt drawn", screen.ready())]

    def line(text):
        screen.type(text + "\r")

    line("/help")
    results += [check("/help lists the screen's commands", screen.until("/quit  Leave ask")),
                check("and the conversation's", screen.until("/compact  Summarise") and screen.until("/config  Edit settings"))]
    line("/confg")
    results.append(check("an unknown command is an error, and no request was made",
                         screen.until("There is no command /confg; /help lists them.") and len(server.requests) == 0,
                         len(server.requests)))
    line("/compact")
    results.append(check("/compact with nothing recorded says so", screen.until("Nothing to compact yet.")))
    # Bare /config opens the settings editor; /config now is the report.
    line("/config now")
    results += [check("/config now shows each setting with its source", screen.until("maxTurns  100 (sandbox on)  [default]")),
                check("and the files", screen.until("user file") and screen.until("(none)"))]
    open(os.path.join(config, "ask", "config.json"), "w").write("{maxTurns: 7}")
    line("/config now")
    results += [check("/config now reads the files again and announces the change", screen.until("maxTurns: 100 → 7")),
                check("and shows the new value from its file", screen.until("maxTurns  7  [") and screen.until("(applied)"))]
    line("/etc/hosts: what is this file?")
    results.append(check("a path is a prompt for the model", screen.until("Answer 1.") and len(server.requests) == 1
                         and "/etc/hosts: what is this file?" in json.dumps(server.requests[0]["body"]["messages"]),
                         len(server.requests)))
    screen.until_status("ready")
    line("/compact")
    results.append(check("/compact with only a short exchange says nothing could be summarised",
                         screen.until_tool("earlier messages", "✗", kind="compact") and len(server.requests) == 1, len(server.requests)))
    screen.until_status("ready")
    # A prompt well past the 80 KB kept tail, pasted: bracketed paste, as a terminal sends it.
    screen.type("\x1b[200~Notes: " + "lorem ipsum " * 7500 + "\x1b[201~\r")
    results.append(check("a large prompt is answered", screen.until("Answer 2.", 30)))
    screen.until_status("ready")
    line("/compact")
    results += [check("/compact summarises the older conversation", screen.until_tool("earlier messages", "✓", 30, kind="compact")),
                check("through one summary request", len(server.requests) == 3, len(server.requests))]
    screen.until_status("ready")
    line("and now?")
    answered = screen.until("Answer 4.", 30)
    dumped = json.dumps(server.requests[3]["body"]["messages"]) if len(server.requests) >= 4 else ""
    results.append(check("and the next prompt carries the summary", answered
                         and "SUMMARY: the user pasted notes." in dumped and "Summary of the conversation so far" in dumped,
                         f"{len(server.requests)} requests: {dumped[:200]}"))
    line("/quit")
    results.append(check("/quit leaves cleanly", screen.finish() == 0))
    server.httpd.shutdown()
    return all(results)


def install_build(directory, name="ask", script=None):
    """Puts a build at `directory/name` the way a linker does: written beside, then renamed into place, so the
    path names a new file. A copy of the real binary, or a shell `script` standing in for a broken build."""
    staged = os.path.join(directory, f".{name}.new")
    if script is None:
        shutil.copy2(ASK, staged)
    else:
        open(staged, "w").write(script)
        os.chmod(staged, 0o755)
    os.rename(staged, os.path.join(directory, name))
    return os.path.join(directory, name)


def terminal_is_cooked(fd):
    """Whether the terminal behind the pty master `fd` is in line mode with echo, as a shell needs it. On macOS
    `tcgetattr` on the master reports the slave's settings, and still does after the child has exited."""
    lflag = termios.tcgetattr(fd)[3]
    return bool(lflag & termios.ICANON) and bool(lflag & termios.ECHO)


def probe_reload_binary():
    print("H: /reload switches to a newly built ask and keeps the session")
    project, state, config, bin_dir = tempfile.mkdtemp(), tempfile.mkdtemp(), tempfile.mkdtemp(), tempfile.mkdtemp()
    os.makedirs(os.path.join(config, "ask"))
    binary = install_build(bin_dir)
    server = agent.Server([agent.turn([("text", "Answer 1.")], "end_turn"), agent.turn([("text", "Answer 2.")], "end_turn")])
    # A new build, the reload and the resumed session are details, said with --verbose (ADR-0119); a reload passes it on.
    screen = Screen(server.url, project, state, config=config, binary=binary, arguments=["--verbose"])
    results = [check("prompt drawn", screen.ready())]
    screen.type("one\r")
    screen.until("Answer 1.")
    screen.until_status("ready")
    screen.type("/reload\r")
    results.append(check("with the build unchanged there is nothing to reload", screen.until("nothing to reload")))
    install_build(bin_dir)
    results.append(check("a new build appearing beside the running one is announced", screen.until("A new ask binary appeared.")))
    screen.until_status("ready")
    results.append(check("the terminal is raw while ask runs", not terminal_is_cooked(screen.fd)))
    screen.type("/reload\r")
    results += [check("it checks the new build", screen.until("Checking the new build")),
                check("and the new process says it reloaded", screen.until("Reloaded ask: built ", 30)),
                check("resuming the same session", screen.until("Resumed session 20")),
                check("with the earlier conversation shown", screen.until("one") and screen.until("Answer 1."))]
    screen.until_status("ready")
    results.append(check("the terminal is raw again in the new process", not terminal_is_cooked(screen.fd)))
    screen.type("two\r")
    results.append(check("the next prompt works in the new process", screen.until("Answer 2.", 30)))
    screen.until_status("ready")
    files = agent.sessions(state)
    kinds = agent.entry_kinds(files[0]) if len(files) == 1 else files  # without the destination record (ADR-0048)
    results.append(check("one session file holds both runs", kinds == ["user", "response", "user", "response"], kinds))
    if len(server.requests) >= 2:
        texts = [b.get("text", "") for m in server.requests[1]["body"]["messages"] for b in m["content"]]
        results.append(check("and the earlier exchange was sent again", "one" in texts and "Answer 1." in texts, texts))
    screen.type("/quit\r")
    results += [check("quits cleanly", screen.finish() == 0),
                check("and the terminal is back in line mode with echo", terminal_is_cooked(screen.fd))]
    server.httpd.shutdown()
    return all(results)


def probe_reload_keeps_grants():
    print("H3: /reload keeps what was allowed for the session (0159)")
    project, state, config, bin_dir = tempfile.mkdtemp(), tempfile.mkdtemp(), tempfile.mkdtemp(), tempfile.mkdtemp()
    os.makedirs(os.path.join(config, "ask"))
    binary = install_build(bin_dir)
    server = agent.Server([agent.turn([("tool", "c1", "touch first.txt")], "tool_use"), agent.turn([("text", "One.")], "end_turn"),
                           agent.turn([("tool", "c2", "touch second.txt")], "tool_use"), agent.turn([("text", "Two.")], "end_turn")])
    screen = Screen(server.url, project, state, config=config, binary=binary, approvals=True)

    def wait(condition, seconds=20):
        end = time.time() + seconds
        while time.time() < end and not condition():
            screen.until("\x00", 0.05)
        return condition()

    results = [check("prompt drawn", screen.ready())]
    screen.type("one\r")
    results.append(check("the first command asks", wait(lambda: "Allow it?" in screen.screen.text())))
    screen.type("a\r")
    results.append(check("allowed for the session, it runs", wait(lambda: os.path.exists(os.path.join(project, "first.txt")))))
    screen.until("One.")
    screen.until_status("ready")
    install_build(bin_dir)
    screen.until("A new ask binary appeared.")
    screen.until_status("ready")
    screen.type("/reload\r")
    results.append(check("the new process starts", screen.until("Resumed session 20", 30) or screen.until("One.", 30)))
    screen.until_status("ready")
    screen.type("two\r")
    results.append(check("after the reload the same program runs without a question",
                         wait(lambda: os.path.exists(os.path.join(project, "second.txt")), 30)
                         and "Allow it?" not in screen.screen.text(), screen.screen.text()))
    leftovers = [name for name in os.listdir(tempfile.gettempdir()) if name.startswith("ask-reload-grants-")]
    results.append(check("the file that carried them is gone", leftovers == [], leftovers))
    screen.until("Two.", 30)
    screen.until_status("ready")
    screen.type("/quit\r")
    results.append(check("quits cleanly", screen.finish() == 0))
    server.httpd.shutdown()
    return all(results)


def probe_reload_env_key():
    print("H2: /reload checks a new build with the key the provider reads from the environment (ADR-0113)")
    project, state, config, bin_dir = tempfile.mkdtemp(), tempfile.mkdtemp(), tempfile.mkdtemp(), tempfile.mkdtemp()
    os.makedirs(os.path.join(config, "ask"))
    server = agent.Server([])
    # The key is in ask's launch environment and nowhere else; ask blanks its own copy once it has read it, so a check that inherits
    # that copy finds no key and refuses a build that works.
    json.dump({"providers": {"gw": {"api": "openai-completions", "baseUrl": server.url + "/v1", "apiKey": "$GW_KEY"}}},
              open(os.path.join(config, "ask", "providers.json"), "w"))
    os.environ["GW_KEY"] = "stand-in-gw-key"
    try:
        binary = install_build(bin_dir)
        screen = Screen(server.url, project, state, arguments=["--provider", "gw", "--model", "m", "--verbose"], config=config, binary=binary)
        results = [check("prompt drawn", screen.ready())]
        install_build(bin_dir)
        results.append(check("a new build is announced", screen.until("A new ask binary appeared.")))
        screen.until_status("ready")
        screen.type("/reload\r")
        results.append(check("the reload goes ahead", screen.until("Reloaded ask: built ", 30), screen.screen.text()[-400:]))
        screen.until_status("ready")
        screen.type("/quit\r")
        results.append(check("quits cleanly", screen.finish() == 0))
    finally:
        del os.environ["GW_KEY"]
        server.httpd.shutdown()
    return all(results)


def probe_reload_refused():
    print("I: a broken build, and running jobs, stop a reload")
    project, state, config, bin_dir = tempfile.mkdtemp(), tempfile.mkdtemp(), tempfile.mkdtemp(), tempfile.mkdtemp()
    os.makedirs(os.path.join(config, "ask"))
    binary = install_build(bin_dir)
    port = agent.free_port()
    server = agent.Server([
        agent.turn([("call", "t1", "bash", {"command": f"exec python3 -m http.server {port} --bind 127.0.0.1", "yield_seconds": 1})], "tool_use"),
        agent.turn([("call", "t2", "job", {"job": "job-1", "action": "wait", "wait_for_port": port, "timeout_seconds": 20})], "tool_use"),
        agent.turn([("text", "Serving.")], "end_turn"),
        agent.turn([("text", "Still here.")], "end_turn")])
    # A new build, the reload and the resumed session are details, said with --verbose (ADR-0119); a reload passes it on.
    screen = Screen(server.url, project, state, config=config, binary=binary, arguments=["--verbose"])
    screen.ready()
    screen.type("serve\r")
    results = [check("a job is running", screen.until("Serving.", 30) and agent.accepts(port))]
    screen.until_status("ready")
    install_build(bin_dir, script="#!/bin/sh\necho 'bad build' >&2\nexit 3\n")
    screen.type("/reload\r")
    results.append(check("a running job stops the reload, naming it and the way out", screen.until("Not reloading: 1 job is running (job-1)") and screen.until("/reload now")))
    results.append(check("and the job still runs", agent.accepts(port)))
    screen.until_status("ready")
    screen.type("/reload now\r")
    results += [check("a build that fails its self-check is refused, with why", screen.until("failed its self-check: it exited 3", 30) and screen.until("bad build") and screen.until("Staying on the running")),
                check("and reload now had not stopped the job before checking", agent.accepts(port))]
    screen.until_status("ready")
    screen.type("still there?\r")
    results.append(check("ask carries on after a refused reload", screen.until("Still here.", 30)))
    screen.until_status("ready")
    install_build(bin_dir)
    screen.type("/reload now\r")
    results += [check("with a good build, /reload now reloads", screen.until("Reloaded ask: built ", 30)),
                check("having stopped the job first", not agent.accepts(port)),
                check("into the same session", screen.until("Resumed session 20") and screen.until("Still here."))]
    screen.until_status("ready")
    screen.type("/quit\r")
    results.append(check("and quits cleanly", screen.finish() == 0))
    server.httpd.shutdown()
    return all(results)


def gate(call, name):
    """A tool call that holds its turn until the file `name` appears in the project: a foreground command, so the model waits on it."""
    return ("call", call, "bash", {"command": f"while [ ! -e {name} ]; do sleep 0.05; done"})


def probe_steering():
    print("J: steering after the whole tool batch; a follow-up only after the agent finishes")
    project = tempfile.mkdtemp()
    server = agent.Server([
        agent.turn([gate("gate1", "release-one"),
                    ("tool", "batch", "echo batch-finished > batch.txt")], "tool_use"),
        agent.turn([gate("gate2", "release-two")], "tool_use"),
        agent.turn([("text", "BASE WORK FINISHED")], "end_turn"),
        agent.turn([("text", "FOLLOWUP ANSWER")], "end_turn")])
    screen = Screen(server.url, project)
    results = [check("initial prompt drawn", screen.ready())]
    screen.type("Start the work\r")
    results.append(check("first gate is running", screen.until("release-one")))
    screen.type("Later please\x1b[13;3u")  # CSI-u Alt+Enter, independent of legacy ESC/Enter ambiguity
    results.append(check("follow-up visibly queued", screen.until(" · Later please")))
    screen.type("Change direction\r")
    results.append(check("steering visibly queued", screen.until(" · Change direction")))
    open(os.path.join(project, "release-one"), "w").close()
    results.append(check("the next turn has reached its gate", screen.until("release-two")))
    if len(server.requests) >= 2:
        blocks = server.requests[1]["body"]["messages"][-1]["content"]
        results.append(check("both tool results precede steering in the actual request",
                             [b["type"] for b in blocks] == ["tool_result", "tool_result", "text"]
                             and blocks[-1]["text"] == "Change direction", blocks))
        results.append(check("the follow-up has not entered yet",
                             "Later please" not in json.dumps(server.requests[1]["body"]["messages"])))
    else:
        results.append(check("second request exists", False, len(server.requests)))
    results.append(check("the rest of the tool batch was not skipped", os.path.exists(os.path.join(project, "batch.txt"))))
    open(os.path.join(project, "release-two"), "w").close()
    results.append(check("the follow-up is answered", screen.until("FOLLOWUP ANSWER")))
    results.append(check("the run is ready", screen.until_status("ready")))
    results.append(check("four requests, with the follow-up only on the last",
                         len(server.requests) == 4
                         and "Later please" not in json.dumps(server.requests[2]["body"]["messages"])
                         and server.requests[3]["body"]["messages"][-1]["content"][-1]["text"] == "Later please",
                         len(server.requests)))
    screen.type("/quit\r")
    results.append(check("clean exit", screen.finish() == 0))
    files = agent.sessions(screen.state)
    prompts = [r["payload"]["text"] for r in map(json.loads, open(files[0]))
               if r.get("type") == "entry" and r["payload"]["kind"] == "user"] if files else []
    results.append(check("each queued prompt was persisted once, in delivery order",
                         prompts == ["Start the work", "Change direction", "Later please"], prompts))
    server.httpd.shutdown()
    return all(results)


def probe_abort_queue():
    print("K: stopping returns unsent input to the editor, without persisting or running it")
    project, config = tempfile.mkdtemp(), tempfile.mkdtemp()
    # The default, "all", sends queued messages when a turn stops; "none" puts them back in the input, which is what this probes.
    os.makedirs(os.path.join(config, "ask"))
    json.dump({"ui": {"queuedOnStop": "none"}}, open(os.path.join(config, "ask", "config.json"), "w"))
    server = agent.Server([
        agent.turn([gate("gate", "never-created")], "tool_use"),
        agent.turn([("text", "RECOVERED AFTER ABORT")], "end_turn")])
    screen = Screen(server.url, project, config=config)
    screen.ready()
    screen.type("Start\r")
    results = [check("waiting in a tool", screen.until("never-created"))]
    screen.type("Unsent steering\r")
    results.append(check("steering queued", screen.until(" · Unsent steering")))
    screen.type("/follow-up Unsent followup\r")
    results.append(check("follow-up queued without a modified Enter key", screen.until(" · Unsent followup")))
    screen.type("draft\x1b")
    screen.until("\x00", 1.0)
    results.append(check("Esc with a draft typed does not end the run", not screen.idle() and "draft" in screen.screen.text()))
    screen.type("\x03")
    screen.until("\x00", 0.5)
    results.append(check("the first Ctrl-C erases the draft", "draft" not in screen.screen.text() and not screen.idle()))
    screen.type("\x03")
    results.append(check("the second stops the run", screen.until_status("ready")))
    editor = screen.editor_lines()
    results.append(check("the editor holds both unsent messages on separate lines",
                         editor == ["Unsent steering", "", "Unsent followup"], editor))
    results.append(check("nothing was automatically requested after abort", len(server.requests) == 1))
    screen.type("\x18Recovered\r")  # Ctrl-X clears the restored lines at once
    results.append(check("the editor can submit another prompt", screen.until("RECOVERED AFTER ABORT")))
    screen.until_status("ready")
    screen.type("/quit\r")
    results.append(check("clean exit", screen.finish() == 0))
    files = agent.sessions(screen.state)
    prompts = [r["payload"]["text"] for r in map(json.loads, open(files[0]))
               if r.get("type") == "entry" and r["payload"]["kind"] == "user"] if files else []
    results.append(check("unsent messages never entered the session", prompts == ["Start", "Recovered"], prompts))
    server.httpd.shutdown()
    return all(results)


def probe_failed_queue():
    print("L: a failed stream returns queued input rather than automatically starting it")
    project = tempfile.mkdtemp()
    server = agent.Server([
        agent.turn([gate("gate", "release")], "tool_use"),
        b'event: message_stop\ndata: {"type":"message_stop"}\n\n'])
    screen = Screen(server.url, project)
    screen.ready()
    screen.type("Start\r")
    results = [check("waiting in a tool", screen.until("release"))]
    screen.type("Unsent followup\x1b[13;3u")
    results.append(check("follow-up queued", screen.until(" · Unsent followup")))
    open(os.path.join(project, "release"), "w").close()
    results.append(check("failed stream ends the run", screen.until_status("ready")))
    results.append(check("unsent input is back in the editor", screen.editor_lines() == ["Unsent followup"], screen.editor_lines()))
    results.append(check("no automatic third request", len(server.requests) == 2, len(server.requests)))
    screen.type("\x15/quit\r")  # clear the restored prompt first
    results.append(check("clean exit", screen.finish() == 0))
    server.httpd.shutdown()
    return all(results)


def probe_multiline():
    print("M: a multi-line prompt: pasted, typed, edited by line, submitted whole")
    project = tempfile.mkdtemp()
    server = agent.Server([agent.turn([("text", "Got all four lines.")], "end_turn")])
    screen = Screen(server.url, project)
    results = [check("prompt drawn", screen.ready())]
    screen.type("\x1b[200~alpha\nbeta\x1b[201~")  # a bracketed paste: its newline is not Enter
    screen.type("\x0agamma")  # Ctrl-J
    screen.type("\x1b[13;2udelta")  # Shift-Enter as a terminal reports it (CSI u)
    results.append(check("every line is on its own row",
                         screen.until("delta") and screen.editor_lines() == ["alpha", "beta", "gamma", "delta"],
                         screen.editor_lines()))
    screen.type("\x1b[A\x1b[A")  # Up, Up: from "delta" to "beta", column 5 clamped to 4
    screen.type("\x15BETA")  # Ctrl-U deletes the line's start, then replace it
    results.append(check("the middle line is edited in place", screen.until("BETA")))
    results.append(check("nothing was sent yet", len(server.requests) == 0))
    screen.type("\r")
    results.append(check("the answer arrives", screen.until("Got all four lines.")))
    results.append(check("the transcript shows the prompt on four rows",
                         "alpha\nBETA\ngamma\ndelta" in "\n".join(line.strip() for line in screen.screen.text().split("\n"))))
    wanted = "alpha\nBETA\ngamma\ndelta"
    blocks = [b.get("text") for m in (server.requests[0]["body"]["messages"] if server.requests else [])
              for b in m["content"]]
    results.append(check("the provider received the exact text, newlines intact", wanted in blocks, blocks))
    files = agent.sessions(screen.state)
    users = [r["payload"]["text"] for r in map(json.loads, open(files[0]))
             if r.get("type") == "entry" and r["payload"]["kind"] == "user"] if files else []
    results.append(check("the session recorded the same text", users == [wanted], users))
    screen.until_status("ready")
    screen.type("\x15/quit\r")
    results.append(check("clean exit", screen.finish() == 0))
    server.httpd.shutdown()
    return all(results)


def probe_new_session():
    print("N: /new releases the old session and starts the next one lazily, with no old context or usage")
    project = tempfile.mkdtemp()
    server = agent.Server([agent.turn([("text", "ORIGINAL SESSION ANSWER")], "end_turn"),
                           agent.turn([("text", "FRESH SESSION ANSWER")], "end_turn")])
    screen = Screen(server.url, project)
    results = [check("screen ready", screen.ready())]
    screen.type("/new\r")
    results.append(check("an unused session is not claimed to be saved", screen.until("New session. It will be saved when you send a prompt.")))
    results.append(check("new before the first prompt creates no session", not agent.sessions(screen.state)))
    screen.until_status("ready")
    screen.type("First session canary\r")
    results.append(check("original turn finished", screen.until("ORIGINAL SESSION ANSWER")))
    screen.until_status("ready")
    paths = agent.sessions(screen.state)
    original = paths[0] if paths else None
    before = open(original, "rb").read() if original else b""
    screen.type("/new\r")
    results.append(check("new session announced", screen.until("New session. The previous one is saved.")))
    results.append(check("old transcript and usage are gone",
                         "ORIGINAL SESSION ANSWER" not in screen.screen.text() and output_tokens(screen) != 5))
    results.append(check("no empty session was created", agent.sessions(screen.state) == paths))
    released = False
    if original:
        with open(original, "rb") as file:
            try:
                fcntl.flock(file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                released = True
            except BlockingIOError:
                pass
    results.append(check("the old writer lock is released", released))
    screen.until_status("ready")
    screen.type("Fresh canary\r")
    results.append(check("the next prompt runs normally", screen.until("FRESH SESSION ANSWER")))
    screen.until_status("ready")
    requests = [r["body"]["messages"] for r in server.requests]
    results.append(check("the new request contains no old exchange",
                         len(requests) == 2 and "First session canary" not in json.dumps(requests[1])
                         and "ORIGINAL SESSION ANSWER" not in json.dumps(requests[1]), requests))
    files = agent.sessions(screen.state)
    results.append(check("the second prompt created its own session", len(files) == 2, files))
    results.append(check("the old file is unchanged", original and open(original, "rb").read() == before))
    results.append(check("only new usage is shown", output_tokens(screen) == 5 and output_tokens(screen) != 10, screen.status()))
    screen.type("/quit\r")
    results.append(check("same process exits cleanly", screen.finish() == 0))
    server.httpd.shutdown()
    return all(results)


def probe_session_job_guard():
    print("O: a session switch refuses running jobs and bad arguments without changing the session")
    project = tempfile.mkdtemp()
    port = agent.free_port()
    server = agent.Server([
        agent.turn([("call", "start", "bash", {"command": f"exec python3 -m http.server {port} --bind 127.0.0.1",
                                             "yield_seconds": 1})], "tool_use"),
        agent.turn([("call", "wait", "wait", {"job": "job-1", "port_open": port, "timeout_seconds": 20})], "tool_use"),
        agent.turn([("text", "BACKGROUND READY")], "end_turn"),
        agent.turn([("text", "ORIGINAL CONTEXT KEPT")], "end_turn")])
    screen = Screen(server.url, project)
    screen.ready()
    screen.type("Start a background job\r")
    results = [check("the background job is serving", screen.until("BACKGROUND READY") and agent.accepts(port))]
    screen.until_status("ready")
    files = agent.sessions(screen.state)
    before = open(files[0], "rb").read() if files else b""
    screen.type("/new extra\r")
    results.append(check("bad arguments are rejected", screen.until("Usage: /new (no arguments).")))
    screen.until_status("ready")
    screen.type("/new\r")
    results.append(check("the running job blocks the switch", screen.until("Cannot switch sessions while jobs are running (job-1).")))
    results.append(check("the job was not stopped", agent.accepts(port)))
    screen.until_status("ready")
    target = os.path.join(project, "other-session.jsonl")
    shutil.copyfile(files[0], target)
    screen.type("/resume " + target + "\r")
    results.append(check("resume also refuses to carry the job into another session", screen.until("/resume: Cannot switch sessions while jobs are running")))
    screen.until_status("ready")
    results.append(check("the refused resume retained the current writer lock", not can_lock_session(files[0])))
    results.append(check("the archive is unchanged", files and open(files[0], "rb").read() == before))
    results.append(check("no extra session appeared", agent.sessions(screen.state) == files))
    screen.until_status("ready")
    screen.type("Continue the same session\r")
    results.append(check("the old conversation still works", screen.until("ORIGINAL CONTEXT KEPT")))
    last = server.requests[-1]["body"]["messages"]
    results.append(check("the original context was retained", "Start a background job" in json.dumps(last)))
    screen.until_status("ready")
    screen.type("/quit\r")
    results.append(check("exit stops the process's jobs", screen.finish() == 0 and not agent.accepts(port)))
    server.httpd.shutdown()
    return all(results)


def can_lock_session(path):
    with open(path, "rb") as file:
        try:
            fcntl.flock(file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            return True
        except BlockingIOError:
            return False


def probe_resume_sessions():
    print("P: /resume lists and switches sessions transactionally; refusal preserves the current one")
    project = tempfile.mkdtemp()
    server = agent.Server([agent.turn([("text", text)], "end_turn") for text in [
        "FIRST ARCHIVE ANSWER", "SECOND ARCHIVE ANSWER", "B AFTER REFUSAL", "A AFTER RESUME", "AFTER REPAIR"]])
    screen = Screen(server.url, project)
    screen.ready()
    screen.type("/resume\r")
    # An empty list says so in the picker's title; Enter then runs the bare command, which says why.
    offered = screen.until("resume · nothing to choose")
    screen.type("\r")
    available = offered and screen.until("No sessions in this project yet.")
    results = [check("an empty list is reported without creating a session", available and not agent.sessions(screen.state), screen.screen.text())]
    if not available:
        screen.type("/quit\r")
        screen.finish()
        server.httpd.shutdown()
        return False
    screen.until_status("ready")
    screen.type("A first canary\r")
    results.append(check("session A answered", screen.until("FIRST ARCHIVE ANSWER")))
    screen.until_status("ready")
    a = agent.sessions(screen.state)[0]
    screen.type("/new\r")
    screen.until("New session. The previous one is saved.")
    screen.until_status("ready")
    screen.type("B second canary\r")
    results.append(check("session B answered", screen.until("SECOND ARCHIVE ANSWER")))
    screen.until_status("ready")
    b = next(path for path in agent.sessions(screen.state) if path != a)
    a_bytes = open(a, "rb").read()
    screen.type("/resume\r")
    results.append(check("the list includes both session names", screen.until(os.path.basename(a)) and screen.until(os.path.basename(b))))
    results.append(check("listing made no provider request", len(server.requests) == 2))
    screen.type("\x1b\x15")  # close the list, clear the draft
    screen.until_editor("")
    # In the screen a prefix narrows the list, and Enter takes the highlighted row; the command refusing an ambiguous prefix is
    # SessionLookupTests' to show.
    ambiguous = os.path.commonprefix([os.path.basename(a), os.path.basename(b)])
    screen.type("/resume " + ambiguous)
    screen.until("\x00", 0.5)
    listed = "\n".join(screen.editor_lines())
    results.append(check("an ambiguous prefix leaves both sessions to choose from",
                         os.path.basename(a) in listed and os.path.basename(b) in listed, listed))
    screen.type("\x1b\x15")
    screen.until_editor("")
    screen.type("/resume definitely-absent\r")
    results.append(check("unknown selection is refused", screen.until("Cannot resume definitely-absent:")))
    screen.until_status("ready")
    missing = os.path.join(project, "missing.jsonl")
    screen.type("/resume " + missing + "\r")
    results.append(check("opening a missing file is refused, in words", screen.until("Cannot resume " + missing + ":")
                         and screen.until("No such file or directory"), screen.screen.text()[-600:]))
    screen.until_status("ready")
    with open(a, "rb") as locked:
        fcntl.flock(locked.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        screen.type("/resume " + os.path.basename(a) + "\r")
        results.append(check("another writer is refused", screen.until("this session is open")))  # the long path wraps the rest
        screen.until_status("ready")
    screen.type("Continue B after refusals\r")
    results.append(check("B remains usable", screen.until("B AFTER REFUSAL")))
    screen.until_status("ready")
    kept = server.requests[-1]["body"]["messages"]
    results.append(check("refusals retained B, not A", "B second canary" in json.dumps(kept) and "A first canary" not in json.dumps(kept)))
    b_bytes = open(b, "rb").read()
    screen.type("/resume " + os.path.basename(a) + "\r")
    results.append(check("A is resumed in place", screen.until("Resumed session " + os.path.basename(a))))
    screen.until_status("ready")
    results.append(check("only A's history is drawn", "FIRST ARCHIVE ANSWER" in screen.screen.text()
                         and "SECOND ARCHIVE ANSWER" not in screen.screen.text() and "B AFTER REFUSAL" not in screen.screen.text()))
    results.append(check("A's usage replaces B's usage", output_tokens(screen) == 5 and output_tokens(screen) != 10, screen.status()))
    results.append(check("B is unlocked and A is locked", can_lock_session(b) and not can_lock_session(a)))
    results.append(check("switching only reads the target archive", open(a, "rb").read() == a_bytes))
    screen.type("/resume " + a + "\r")
    results.append(check("selecting the current session is a no-op", screen.until("Already using session " + os.path.basename(a))))
    screen.until_status("ready")
    results.append(check("reselecting does not double-count usage", output_tokens(screen) == 5 and output_tokens(screen) != 10, screen.status()))
    screen.type("Continue A now\r")
    results.append(check("A continues", screen.until("A AFTER RESUME")))
    screen.until_status("ready")
    last = server.requests[-1]["body"]["messages"]
    results.append(check("the actual request carries A, not B", "A first canary" in json.dumps(last) and "B second canary" not in json.dumps(last)))
    results.append(check("A usage accumulates from its own history", output_tokens(screen) == 10, screen.status()))
    results.append(check("B's file was not changed by A's turn", open(b, "rb").read() == b_bytes))
    damaged = os.path.join(os.path.dirname(a), "damaged-probe.jsonl")
    original = open(a, "rb").read() + b'{"id":"torn'
    open(damaged, "wb").write(original)
    screen.type("/resume damaged-probe\r")
    results.append(check("damage on interactive resume is reported", screen.until("mid-write and was dropped.") and "session file had a problem" in screen.screen.text(), screen.screen.text()))
    results.append(check("a repaired read does not rewrite the file", open(damaged, "rb").read() == original))
    screen.until_status("ready")
    screen.type("Continue after repair\r")
    results.append(check("the repaired session continues", screen.until("AFTER REPAIR")))
    screen.until_status("ready")
    results.append(check("the first change preserves the damaged bytes", os.path.exists(damaged + ".damaged")
                         and open(damaged + ".damaged", "rb").read() == original))
    screen.type("/quit\r")
    results.append(check("clean exit", screen.finish() == 0))
    server.httpd.shutdown()
    return all(results)


def until_after(screen, marker, needle, seconds=15):
    """Reads until `marker` is on screen and `needle` appears below its last occurrence, so output from an earlier
    command cannot satisfy the wait, nor can a marker that has not been drawn yet."""
    end = time.time() + seconds
    while time.time() < end:
        text = screen.screen.text()
        if screen.output.endswith(FRAME_END) and marker in text and needle in text.rsplit(marker, 1)[-1]:
            return True
        screen.until("\x00", 0.05)
    return False


def probe_model_selection():
    print("Q: /model is run-local, atomic, pinned to its provider, and survives reload without losing reset")
    # The /config now report runs to some 45 rows: a taller screen keeps the settings under test in view.
    global ROWS
    saved, ROWS = ROWS, 80
    try:
        return model_selection_checks()
    finally:
        ROWS = saved


def model_selection_checks():
    project, config, binary_dir = tempfile.mkdtemp(), tempfile.mkdtemp(), tempfile.mkdtemp()
    os.makedirs(os.path.join(config, "ask"))
    config_path = os.path.join(config, "ask", "config.json")
    settings = {"model": "file-model", "provider": "anthropic", "maxTurns": 3}
    open(config_path, "w").write(json.dumps(settings))
    # \"keyless\" names a variable that does not exist (ASK_ variables are removed from the probe's environment);
    # \"local\" needs no key and a loopback address, so it resolves.
    open(os.path.join(config, "ask", "providers.json"), "w").write(json.dumps({"providers": {
        "keyless": {"api": "openai-completions", "baseUrl": "http://127.0.0.1:9/v1", "apiKey": "$ASK_PROBE_MISSING",
                    "models": [{"id": "m"}]},
        "local": {"api": "openai-completions", "baseUrl": "http://127.0.0.1:9/v1", "models": [{"id": "local-default"}]}}}))
    binary = install_build(binary_dir)
    server = agent.Server([agent.turn([("text", text)], "end_turn") for text in [
        "BASE MODEL ANSWER", "PICKED MODEL ANSWER", "MODEL AFTER REFUSAL", "RESET MODEL ANSWER"]])
    # A changed provider, a new build and the reload are details, said with --verbose (ADR-0119).
    screen = Screen(server.url, project, config=config, binary=binary, arguments=("--model", "flag-model", "--verbose"))
    screen.ready()
    screen.type("/model\r")
    # Bare /model opens the list of models; the status line names the current one.
    found = screen.until("model · ") and "flag-model" in screen.status()
    screen.type("\x1b\x15")  # close the list, clear the draft
    results = [check("the list opens and the current model is shown, without a request", found and not server.requests, screen.screen.text())]
    if not found:
        screen.type("/quit\r")
        screen.finish()
        server.httpd.shutdown()
        return False
    screen.until_status("ready")
    screen.type("Original request\r")
    results.append(check("the original model runs", screen.until("BASE MODEL ANSWER")))
    screen.until_status("ready")
    chosen = "vendor/model:tag"
    before = open(config_path, "rb").read()
    screen.type("/model " + chosen + "\r")
    results.append(check("a model id with slashes is not misread as a provider", screen.until("Model selected for this run: " + chosen)))
    dismiss_thinking_offer(screen)
    results.append(check("selecting did not rewrite configuration", open(config_path, "rb").read() == before))
    screen.until_status("ready")
    screen.type("/config now\r")
    results.append(check("configuration reports command provenance", screen.until("[/model (this run)]")))
    screen.until_status("ready")
    settings.update(provider="unconfigured-file-provider", model="changed-file-model", maxTurns=7)
    open(config_path, "w").write(json.dumps(settings))
    screen.type("Request after config changed\r")
    results.append(check("the choice survives prompt-time configuration reload", screen.until("PICKED MODEL ANSWER")))
    screen.until_status("ready")
    results.append(check("the request uses the selected id", len(server.requests) == 2 and server.requests[1]["body"]["model"] == chosen))
    screen.type("/config now\r")
    results.append(check("unrelated configuration still reloads", screen.until("maxTurns  7")))
    screen.until_status("ready")
    for arguments in ["missing-provider any-model", "keyless any-model"]:
        screen.type("/model " + arguments + "\r")
        results.append(check("failed selection is nonfatal: " + arguments, screen.until("Model not changed (" + arguments + "):")))
        dismiss_thinking_offer(screen)
        screen.until_status("ready")
    marker = "/config after-refusals"  # unique: an older /config's report cannot satisfy the waits below
    screen.type("/config after-refusals\r")
    results.append(check("after refusals the live configuration still loads and keeps the choice",
                         until_after(screen, marker, "project file")
                         and "[/model (this run)]" in screen.screen.text().rsplit(marker, 1)[-1]
                         and "Configuration not reloaded" not in screen.screen.text().rsplit(marker, 1)[-1],
                         screen.screen.text()))
    screen.until_status("ready")
    screen.type("/model local local-model\r")
    results.append(check("a provider and model switch together", screen.until("Model selected for this run: local-model"), screen.screen.text()))
    dismiss_thinking_offer(screen)
    results.append(check("the status label names the provider", screen.until_status("local/local-model")))
    screen.until_status("ready")
    screen.type("/model " + chosen + "\r")
    results.append(check("a bare id keeps the provider now in force", screen.until("local/" + chosen)))
    dismiss_thinking_offer(screen)
    screen.until_status("ready")
    screen.type("/model anthropic " + chosen + "\r")
    results.append(check("and the provider can be named again", screen.until('provider: "local" → "anthropic" (/model (this run))')))
    dismiss_thinking_offer(screen)
    screen.until_status("ready")
    screen.type("/model one two three\r")
    results.append(check("bad command syntax is refused", screen.until("Usage: /model [CONNECTION] MODEL"), screen.screen.text()))
    dismiss_thinking_offer(screen)
    screen.until_status("ready")
    results.append(check("commands made no model requests", len(server.requests) == 2))
    screen.type("Request after refusals\r")
    results.append(check("the previous model remains usable", screen.until("MODEL AFTER REFUSAL")))
    screen.until_status("ready")
    results.append(check("failed selections retained the chosen model", server.requests[-1]["body"]["model"] == chosen))
    files = agent.sessions(screen.state)
    original_path = files[0] if files else None
    original_pid = screen.pid
    install_build(binary_dir)
    results.append(check("the replacement binary is noticed", screen.until("A new ask binary appeared.")))
    screen.type("/reload\r")
    results.append(check("reload checks the effective model, not the invalid file provider",
                         screen.until("Reloaded ask: built ", 30)))
    results.append(check("reload keeps the selected model and process", chosen in screen.status() and screen.pid == original_pid))
    screen.until_status("ready")
    screen.type("/config now\r")
    results.append(check("reload kept command rather than CLI provenance", screen.until("[/model (this run)]")))
    screen.until_status("ready")
    settings["provider"] = "anthropic"
    open(config_path, "w").write(json.dumps(settings))
    saved = open(config_path, "rb").read()
    screen.type("/model --reset\r")
    results.append(check("reset after reload restores the original CLI flag", screen.until("Model selection reset to configuration: flag-model")))
    dismiss_thinking_offer(screen)
    screen.until_status("ready")
    screen.type("Request after reset\r")
    results.append(check("the reset model runs", screen.until("RESET MODEL ANSWER")))
    screen.until_status("ready")
    results.append(check("the actual request uses the original flag", server.requests[-1]["body"]["model"] == "flag-model"))
    results.append(check("reset did not save a setting", open(config_path, "rb").read() == saved))
    results.append(check("model changes kept the same archive", agent.sessions(screen.state) == [original_path]))
    payloads = [r["payload"] for r in map(json.loads, open(original_path)) if r.get("type") == "entry"] if original_path else []
    results.append(check("only the four real prompts were persisted", len([p for p in payloads if p["kind"] == "user"]) == 4))
    screen.type("/quit\r")
    results.append(check("clean exit", screen.finish() == 0))
    server.httpd.shutdown()
    return all(results)


def probe_strict_label():
    print("R: a strict sandbox is said at the start with --verbose; no sandbox is a warning on the status line")
    # Roadmap 0074: the status line leads with ✓ when sandboxed and ! when not, and says nothing more about a sandbox that is on.
    project = tempfile.mkdtemp()
    server = agent.Server([])
    results = []
    for arguments, wanted, mark in [(("--write", "workspace", "--network", "none"), "network none", "✓"),
                                    (("--network", "localhost"), "network localhost", "✓"),
                                    (("--read", "workspace"), "reads only the workspace", "✓"),
                                    (("--no-sandbox",), "The sandbox is off", "!"),
                                    ((), None, "✓")]:
        screen = Screen(server.url, project, arguments=(*arguments, "--verbose"))
        screen.ready()
        status = screen.status()
        # A long sentence wraps: read it as one.
        text = " ".join(line.strip() for line in screen.screen.text().split("\n"))
        label = " ".join(arguments) or "the default"
        results.append(check(f"{label}: the status line leads with {mark}", status.lstrip().startswith(mark), status))
        if wanted:
            results.append(check(f"{label}: the start says '{wanted}'", wanted in text, text[:400]))
        else:
            results.append(check("the default sandbox is not described", "Sandbox:" not in text, text[:400]))
        screen.type("/quit\r")
        results.append(check("clean exit", screen.finish() == 0))
    server.httpd.shutdown()
    return all(results)


def sandbox_row(screen):
    """The sandbox rows of the last `/config now` report: `sandbox   on` and the line under it naming writes, reads and the network."""
    lines = screen.screen.text().split("\n")
    start = max((i for i, line in enumerate(lines) if line.strip().startswith("sandbox ")), default=None)
    # The row wraps on a narrow screen: up to the network, which ends it.
    end = next((i for i in range(start, len(lines)) if "network" in lines[i]), start + 1) if start is not None else 0
    return " ".join(line.strip() for line in lines[start:end + 1]) if start is not None else ""


def probe_resume_strict():
    print("S: /resume adopts a session's recorded sandbox and /new drops it")
    project, state = tempfile.mkdtemp(), tempfile.mkdtemp()
    server = agent.Server([agent.turn([("text", "Strict session answer.")], "end_turn")])
    made = subprocess.run([ASK, "-p", "Start strict.", "--network", "none", "--write", "workspace"], cwd=project,
                          env=agent.environment(state, server.url), capture_output=True, text=True, timeout=60)
    files = agent.sessions(state)
    results = [check("a strict session exists", made.returncode == 0 and len(files) == 1, made.stderr[-300:])]
    # Keeping a session's sandbox is a detail, said with --verbose (ADR-0119); /config now shows the sandbox in force.
    global ROWS
    saved, ROWS = ROWS, 80
    try:
        screen = Screen(server.url, project, state, arguments=["--verbose"])
        screen.ready()
        screen.type("/config now\r")
        screen.until("project file")
        results.append(check("a fresh screen is not strict", "network: any" in sandbox_row(screen), sandbox_row(screen)))
        screen.until_status("ready")
        screen.type("/resume " + os.path.basename(files[0]) + "\r")
        results.append(check("resuming says it keeps the recorded sandbox", screen.until("Keeping this session's sandbox")))
        screen.until_status("ready")
        screen.type("/config now\r")
        screen.until("\x00", 1.0)
        row = sandbox_row(screen)
        results.append(check("and adopts it", ("network none" in row or "network: none" in row) and "this session's record" in row, row))
        screen.until_status("ready")
        screen.type("/new\r")
        screen.until("New session.")
        screen.until_status("ready")
        screen.type("/config now\r")
        screen.until("\x00", 1.0)
        results.append(check("/new drops it", "network: any" in sandbox_row(screen), sandbox_row(screen)))
        screen.type("/quit\r")
        results.append(check("clean exit", screen.finish() == 0))
    finally:
        ROWS = saved
        server.httpd.shutdown()
    return all(results)


def probe_model_and_destination():
    print("T: in a resumed session /model overrides the recorded destination; /resume goes back to a session's own")
    project, state, config = tempfile.mkdtemp(), tempfile.mkdtemp(), tempfile.mkdtemp()
    os.makedirs(os.path.join(config, "ask"))
    # Another provider, at a port nothing listens on: a request sent there never reaches the fake Anthropic server.
    open(os.path.join(config, "ask", "providers.json"), "w").write(json.dumps({"providers": {
        "local": {"api": "openai-completions", "baseUrl": "http://127.0.0.1:9/v1", "models": [{"id": "local-x"}]}}}))
    server = agent.Server([agent.turn([("text", f"ANSWER {n}")], "end_turn") for n in range(1, 7)])
    env = agent.environment(state, server.url, config)
    for model in ("alpha-model", "beta-model"):
        subprocess.run([ASK, "-p", "Start " + model, "--model", model], cwd=project, env=env, capture_output=True,
                       text=True, timeout=60)
    by_model = {}
    for path in agent.sessions(state):
        first = next(json.loads(l) for l in open(path) if '"kind":"destination"' in l)
        by_model[first["payload"]["destination"]["model"]] = path
    results = [check("two sessions recorded on two models", sorted(by_model) == ["alpha-model", "beta-model"], by_model)]
    screen = Screen(server.url, project, state, config=config, arguments=("--resume", by_model.get("alpha-model", "")))
    screen.ready()
    sent = lambda: server.requests[-1]["body"]["model"]
    screen.type("Continue alpha\r")
    results.append(check("a resumed session goes where it was sent", screen.until("ANSWER 3") and sent() == "alpha-model", sent()))
    screen.until_status("ready")
    screen.type("/model gamma-model\r")
    screen.until("Model selected for this run: gamma-model")
    dismiss_thinking_offer(screen)
    screen.until_status("ready")
    screen.type("Now on gamma\r")
    results.append(check("/model overrides the recorded destination, as the user's consent",
                         screen.until("ANSWER 4") and sent() == "gamma-model", (sent(), screen.screen.text()[-600:])))
    screen.until_status("ready")
    screen.type("/model local local-x\r")
    screen.until("Model selected for this run: local-x")
    dismiss_thinking_offer(screen)
    screen.until_status("local/local-x · ready")
    before = len(server.requests)
    screen.type("Now elsewhere\r")
    # Refused connections are retried for about 15 s; the run's last line says it gave up.
    screen.until("ask: the request did not complete", 40)
    screen.until_status("ready")
    results.append(check("/model to another provider leaves the recorded provider too",
                         len(server.requests) == before and "local/local-x" in screen.status(),
                         (len(server.requests) - before, screen.status())))
    # The choice is the user's consent to move a session with history (ADR-0048): the move is recorded, not refused.
    moved = [json.loads(l)["payload"]["destination"] for l in open(by_model["alpha-model"]) if '"kind":"destination"' in l]
    results.append(check("and the session records the move as consented", moved[-1:] and moved[-1]["name"] == "local"
                         and "destination" not in screen.screen.text().lower().split("now elsewhere")[-1], moved))
    screen.type("/resume " + os.path.basename(by_model.get("beta-model", "")) + "\r")
    screen.until("Resumed session")
    screen.until_status("beta-model · ready")  # the command has ended: a prompt typed earlier stays in the editor
    screen.type("Continue beta\r")
    results.append(check("/resume goes back to that session's own model, dropping this run's choice",
                         screen.until("ANSWER 5") and sent() == "beta-model", (sent(), screen.screen.text()[-900:])))
    screen.until_status("ready")
    screen.type("/quit\r")
    results.append(check("clean exit", screen.finish() == 0))
    server.httpd.shutdown()
    return all(results)


def probe_protected_paths():
    print("S2: what runs later and other tools' credentials are closed; a request for one asks, and allowed opens it (0153)")
    project = tempfile.mkdtemp()
    state = tempfile.mkdtemp()
    home = os.path.realpath(os.path.join(state, "home"))
    os.makedirs(home + "/.config/gh", exist_ok=True)
    open(home + "/.config/gh/hosts.yml", "w").write("oauth_token: gho_probe_secret\n")
    rc = home + "/.zshrc"
    calls = [
        ("call", "p1", "bash", {"command": f"echo planted >> '{rc}'; echo rc=$?"}),
        ("call", "p2", "bash", {"command": f"echo allowed >> '{rc}'; echo rc=$?", "sandbox": {"write": [rc]}}),
        ("call", "p3", "bash", {"command": f"cat '{home}/.config/gh/hosts.yml'; echo rc=$?", "sandbox": {"read": [home + "/.config/gh"]}}),
    ]
    server = agent.Server([agent.turn([c], "tool_use") for c in calls] + [agent.turn([("text", "All done.")], "end_turn")])
    screen = Screen(server.url, project, state)

    def wait(condition, seconds=15):
        end = time.time() + seconds
        while time.time() < end and not condition():
            screen.until("\x00", 0.05)
        return condition()

    result = lambda n: json.dumps(server.requests[n]["body"]["messages"][-1]) if len(server.requests) > n else ""
    screen.ready()
    screen.type("Go\r")
    results = [check("a plain write to a shell startup file fails, and nothing is written",
                     wait(lambda: "rc=1" in result(1)) and not os.path.exists(rc), result(1)[-200:])]
    results.append(check("a request for it asks, naming it protected",
                         wait(lambda: "protected" in screen.screen.text() and ".zshrc" in screen.screen.text()),
                         screen.screen.text()[-400:]))
    screen.type("y\r")
    results.append(check("allowed, the write goes through", wait(lambda: "rc=0" in result(2))
                         and open(rc).read() == "allowed\n", result(2)[-200:]))
    results.append(check("a request to read gh's credentials asks",
                         wait(lambda: "Allow it?" in screen.screen.text() and "reading" in screen.screen.text()
                              and ".config/gh" in screen.screen.text())))
    screen.type("n\r")
    results.append(check("denied, nothing of the token reaches the model",
                         wait(lambda: len(server.requests) > 3) and "gho_probe_secret" not in json.dumps(server.requests[3]["body"]),
                         result(3)[-200:]))
    screen.until("All done.", 15)
    screen.until_status("ready")
    screen.type("/quit\r")
    results.append(check("clean exit", screen.finish() == 0))
    return all(results)


def probe_question_tool():
    print("Q1: the model's questions are answered in a section above the input; ask -p does not offer them (0117)")
    project = tempfile.mkdtemp()
    questions = {"questions": [
        {"question": "What should change?", "header": "Scope",
         "choices": [{"label": "Only the parser"}, {"label": "Everything", "description": "parser and printer"}]},
        {"question": "Which tests?", "header": "Tests", "choices": [{"label": "Unit"}, {"label": "Probes"}], "multiple": True}]}
    server = agent.Server([agent.turn([("call", "q1", "question", questions)], "tool_use"),
                           agent.turn([("text", "Thanks, noted.")], "end_turn")])
    screen = Screen(server.url, project)

    def wait(condition, seconds=15):
        end = time.time() + seconds
        while time.time() < end and not condition():
            screen.until("\x00", 0.05)
        return condition()

    screen.ready()
    offered = lambda: [tool["name"] for tool in server.requests[0]["body"].get("tools", [])] if server.requests else []
    screen.type("Plan it\r")
    results = [check("the tool is offered on the screen", wait(lambda: "question" in offered()), offered())]
    results.append(check("the first question is shown with its choices",
                         wait(lambda: "What should change?" in screen.screen.text() and "Everything" in screen.screen.text())))
    # Down and Space pick "Everything", Tab reaches the note row, Enter goes to the next question, Space checks "Unit", Enter reviews.
    for key in ["\x1b[B", " ", "\t", "k", "e", "e", "p", " ", "i", "t", "\r", " ", "\r"]:
        screen.type(key)
        time.sleep(0.05)
    results.append(check("after the last, the review lists every answer",
                         wait(lambda: "Review" in screen.screen.text() and "note: keep it" in screen.screen.text()), screen.screen.text()))
    screen.type("\r")
    got = lambda: json.dumps(server.requests[1]["body"]["messages"][-1]) if len(server.requests) > 1 else ""
    results.append(check("the model gets one line per answer",
                         wait(lambda: 'Scope: chose \\"Everything\\"; note: \\"keep it\\"' in got() and 'Tests: chose \\"Unit\\"' in got()), got()))
    screen.until("Thanks, noted.", 15)
    screen.until_status("ready")
    screen.type("/quit\r")
    results.append(check("clean exit", screen.finish() == 0))
    printed = agent.Server([agent.turn([("text", "ok")], "end_turn")])
    state = tempfile.mkdtemp()
    subprocess.run([ASK, "-p", "hi"], cwd=project, env=agent.environment(state, printed.url), capture_output=True, timeout=60)
    names = [tool["name"] for tool in printed.requests[0]["body"].get("tools", [])] if printed.requests else ["no request"]
    results.append(check("ask -p does not offer it", "question" not in names and "bash" in names, names))
    return all(results)


def probe_allow_commands():
    print("X2: --allow commands runs every command unasked, and a write still asks (0156)")
    project = tempfile.mkdtemp()
    calls = [("tool", "c1", "rm -f nothing-here; echo ran-one"), ("tool", "c2", "git status; echo ran-two"),
             ("call", "w1", "write", {"path": "note.txt", "content": "x"})]
    server = agent.Server([agent.turn([c], "tool_use") for c in calls] + [agent.turn([("text", "All done.")], "end_turn")])
    screen = Screen(server.url, project, arguments=("--allow", "commands"), approvals=True)

    def wait(condition, seconds=15):
        end = time.time() + seconds
        while time.time() < end and not condition():
            screen.until("\x00", 0.05)
        return condition()

    screen.ready()
    screen.type("Go\r")
    results = [check("two commands ran without a question", wait(lambda: len(server.requests) > 2)
                     and "ran-two" in json.dumps(server.requests[2]["body"]["messages"][-1]))]
    results.append(check("the write asks", wait(lambda: "Allow it?" in screen.screen.text() and "note.txt" in screen.screen.text())))
    screen.type("y\r")
    results.append(check("allowed, it is written", wait(lambda: os.path.exists(os.path.join(project, "note.txt")))))
    screen.until("All done.", 15)
    screen.until_status("ready")
    screen.type("/quit\r")
    results.append(check("clean exit", screen.finish() == 0))
    return all(results)


def probe_call_approvals():
    print("X: a call that changes things asks first: this time, the subcommand or the program for the session, or deny (0134)")
    project = tempfile.mkdtemp()
    commands = ["git status", "git status --short", "git log -1", "git diff", "ls"]
    calls = [("tool", f"c{n}", command) for n, command in enumerate(commands)]
    server = agent.Server([agent.turn([c], "tool_use") for c in calls] + [agent.turn([("text", "All done.")], "end_turn")])
    screen = Screen(server.url, project, approvals=True)

    def wait(condition, seconds=15):
        end = time.time() + seconds
        while time.time() < end and not condition():
            screen.until("\x00", 0.05)
        return condition()

    result = lambda n: json.dumps(server.requests[n]["body"]["messages"][-1]) if len(server.requests) > n else ""
    pending = lambda: screen.screen.text() if "Allow it?" in screen.screen.text() else ""
    screen.ready()
    screen.type("Go\r")
    results = [check("git status asks, offering the subcommand and the program for the session",
                     wait(lambda: "Allow `git status` for the session" in pending() and "Allow `git` for the session" in pending()),
                     screen.screen.text()[-500:])]
    screen.type("a\r")
    results.append(check("allowed for the session, it runs", wait(lambda: len(server.requests) > 1)))
    # A covered call runs without a question; one that asked would wait for an answer that never comes.
    results.append(check("git status --short is covered: no question", wait(lambda: len(server.requests) > 2)))
    results.append(check("git log is another subcommand: it asks, the whole command shown",
                         wait(lambda: "Allow `git log` for the session" in pending() and "git log -1" in pending())))
    screen.type("p\r")
    results.append(check("git diff is covered by the program grant", wait(lambda: len(server.requests) > 4)))
    results.append(check("ls asks", wait(lambda: "Allow `ls` for the session" in pending())))
    screen.type("n\r")
    results.append(check("denied, the model is told", wait(lambda: "did not allow" in result(5)), result(5)[-200:]))
    screen.until("All done.", 15)
    screen.until_status("ready")
    screen.type("/quit\r")
    results.append(check("clean exit", screen.finish() == 0))
    return all(results)


def probe_sandbox_approval():
    print("V: a call asking for more than the sandbox allows is put to the user: once, for the session, or no")
    project = tempfile.mkdtemp()
    target = agent.Server([])
    reach = f"curl -s -o /dev/null -w 'HTTP %{{http_code}}' -d '{{}}' {target.url}/probe; echo ' curl='$?"
    never = "/Users/Shared/ask-approval-never"
    calls = [("call", f"w{n}", "bash", {"command": reach, "sandbox": {"network": "any"}}) for n in range(3)]
    calls.append(("call", "o", "bash", {"command": f"echo x > {never}", "sandbox": {"write": ["/Users/Shared"]}}))
    server = agent.Server([agent.turn([c], "tool_use") for c in calls] + [agent.turn([("text", "All done.")], "end_turn")])
    screen = Screen(server.url, project, arguments=("--network", "localhost", "--write", "workspace"))

    def wait(condition, seconds=15):
        end = time.time() + seconds
        while time.time() < end and not condition():
            screen.until("\x00", 0.05)
        return condition()

    questions = lambda: screen.screen.text().count("Allow it?")
    result = lambda n: json.dumps(server.requests[n]["body"]["messages"][-1]) if len(server.requests) > n else ""
    screen.ready()
    screen.type("Go\r")
    results = [check("the question names the call and what it asks for",
                     wait(lambda: questions() == 1) and "asks for network any (this run allows localhost)" in screen.screen.text()
                     and "Allow this time" in screen.screen.text() and "[✓]" in screen.screen.text(), screen.screen.text()[-600:])]
    screen.type("y\r")
    results.append(check("y runs it, under what it asked for", wait(lambda: "HTTP 200 curl=0" in result(1)), result(1)[-200:]))
    # An answered question leaves nothing behind (0157): "Allow it?" on the screen is the question waiting now.
    results.append(check("once is not remembered: the same request asks again",
                         wait(lambda: len(server.requests) > 1 and questions() == 1)))
    screen.type("a\r")
    results.append(check("a runs it and allows it for the session",
                         wait(lambda: "HTTP 200 curl=0" in result(2))))
    # Earlier questions scroll away: what follows the grant is what counts.
    after_grant = lambda: screen.screen.text() if questions() else ""
    results.append(check("a request the session grant covers runs without asking",
                         wait(lambda: "HTTP 200 curl=0" in result(3)) and "network any" not in after_grant(),
                         (after_grant()[-300:], result(3)[-200:])))
    results.append(check("a larger request asks", wait(lambda: "asks for writing under /Users/Shared" in after_grant())))
    screen.type("n\r")
    # The model is told the least about the sandbox (ADR-0115): a refusal, not who could widen it.
    results.append(check("n refuses it",
                         wait(lambda: "that request is refused" in result(4)) and not os.path.exists(never), result(4)[-300:]))
    screen.until("All done.", 15)
    screen.until_status("ready")
    screen.type("/quit\r")
    results.append(check("clean exit", screen.finish() == 0))
    server.httpd.shutdown()
    target.httpd.shutdown()
    return all(results)

def probe_approval_abort():
    print("W: aborting the turn while a question waits answers no, and nothing hangs")
    project = tempfile.mkdtemp()
    marker = os.path.join(project, "ran.txt")
    server = agent.Server([agent.turn([("call", "w", "bash", {"command": f"echo ran > {marker}", "sandbox": {"network": "any"}})], "tool_use"),
                           agent.turn([("text", "After abort.")], "end_turn")])
    screen = Screen(server.url, project, arguments=("--network", "localhost"))
    screen.ready()
    screen.type("Go\r")
    results = [check("the question waits", screen.until("Allow it?"))]
    screen.type("\x03")
    results.append(check("Ctrl-C aborts the turn instead, with no block (roadmap 0142)",
                         screen.until_status("ready") and "Aborted" not in screen.screen.text()))
    results.append(check("and the call did not run", not os.path.exists(marker)))
    results.append(check("the question no longer waits: keys type again",
                         (screen.type("hello"), screen.until_editor("hello", 5))[1]))
    screen.type("\x15/quit\r")
    results.append(check("clean exit", screen.finish() == 0))
    server.httpd.shutdown()
    return all(results)


def probe_session_narrowing_screen():
    print("Y: undoing the session's narrowing asks; /model keeps it and /new drops it")
    project = tempfile.mkdtemp()
    target = agent.Server([])
    reach = f"curl -s -o /dev/null -w 'HTTP %{{http_code}}' -d '{{}}' {target.url}/probe; echo ' curl='$?"
    steps = [("call", "n1", "narrow_sandbox", {"sandbox": {"network": "none"}}), ("call", "b1", "bash", {"command": reach}),
             ("call", "r", "narrow_sandbox", {"reset": True}), ("call", "b2", "bash", {"command": reach})]
    server = agent.Server([agent.turn([c], "tool_use") for c in steps] + [agent.turn([("text", "First done.")], "end_turn"),
                           agent.turn([("call", "n2", "narrow_sandbox", {"sandbox": {"network": "none"}})], "tool_use"),
                           agent.turn([("text", "Narrowed again.")], "end_turn"),
                           agent.turn([("call", "b3", "bash", {"command": reach})], "tool_use"),
                           agent.turn([("text", "Still narrowed.")], "end_turn"),
                           agent.turn([("call", "b4", "bash", {"command": reach})], "tool_use"),
                           agent.turn([("text", "New done.")], "end_turn")])
    screen = Screen(server.url, project)

    def wait(condition, seconds=15):
        end = time.time() + seconds
        while time.time() < end and not condition():
            screen.until("\x00", 0.05)
        return condition()

    result = lambda n: json.dumps(server.requests[n]["body"]["messages"][-1]) if len(server.requests) > n else ""
    screen.ready()
    screen.type("Go\r")
    results = [check("narrowed, a call cannot connect", wait(lambda: "curl=7" in result(2)), result(2)[-200:]),
               check("reset asks the user", wait(lambda: "Allow it?" in screen.screen.text()) and "narrowing" in screen.screen.text())]
    screen.type("y\r")
    results.append(check("y restores the run's sandbox", wait(lambda: "HTTP 200 curl=0" in result(4)), result(4)[-200:]))
    screen.until("First done.")
    screen.until_status("ready")
    screen.type("Narrow\r")
    screen.until("Narrowed again.")
    screen.until_status("ready")
    screen.type("/model narrowed-model\r")
    screen.until("Model selected for this run: narrowed-model")
    dismiss_thinking_offer(screen)
    screen.until_status("ready")
    screen.type("Try after rebuilding the loop\r")
    results.append(check("/model rebuilds the loop without losing the narrowing",
                         wait(lambda: "curl=7" in result(8)), result(8)[-200:]))
    screen.until("Still narrowed.")
    screen.until_status("ready")
    screen.type("/new\r")
    screen.until("New session.")
    screen.until_status("ready")
    screen.type("Reach\r")
    results.append(check("/new drops the narrowing", wait(lambda: "HTTP 200 curl=0" in result(10)), result(10)[-200:]))
    screen.until("New done.")
    screen.until_status("ready")
    screen.type("/quit\r")
    results.append(check("clean exit", screen.finish() == 0))
    server.httpd.shutdown()
    target.httpd.shutdown()
    return all(results)


def probe_reset_ignores_unrelated_grants():
    print("Z: a remembered write grant is not permission to undo a network narrowing")
    project = tempfile.mkdtemp()
    target = agent.Server([])
    reach = f"curl -s -o /dev/null -w 'HTTP %{{http_code}}' -d '{{}}' {target.url}/probe; echo ' curl='$?"
    steps = [("call", "grant", "bash", {"command": "echo granted", "sandbox": {"write": ["/Users/Shared"]}}),
             ("call", "narrow", "narrow_sandbox", {"sandbox": {"network": "none"}}),
             ("call", "reset", "narrow_sandbox", {"reset": True}),
             ("call", "reach", "bash", {"command": reach})]
    server = agent.Server([agent.turn([c], "tool_use") for c in steps]
                          + [agent.turn([("text", "Reset refused.")], "end_turn")])
    screen = Screen(server.url, project, arguments=("--write", "workspace"))

    def wait(condition, seconds=15):
        end = time.time() + seconds
        while time.time() < end and not condition():
            screen.until("\x00", 0.05)
        return condition()

    result = lambda n: json.dumps(server.requests[n]["body"]["messages"][-1]) if len(server.requests) > n else ""
    screen.ready()
    screen.type("Go\r")
    results = [check("a widening asks first", screen.until("Allow it?"))]
    screen.type("a\r")
    results.append(check("the write grant is remembered", wait(lambda: "granted" in result(1))))
    results.append(check("reset still asks separately",
                         wait(lambda: "granted" in result(1) and "Allow it?" in screen.screen.text())
                         and "narrowing" in screen.screen.text(), screen.screen.text()[-600:]))
    screen.type("n\r")
    results.append(check("no keeps the narrowing", wait(lambda: "that request is refused" in result(3)), result(3)[-200:]))
    results.append(check("and a later call cannot connect", wait(lambda: "curl=7" in result(4)), result(4)[-200:]))
    screen.until("Reset refused.")
    screen.until_status("ready")
    screen.type("\x15/quit\r")
    results.append(check("clean exit", screen.finish() == 0))
    server.httpd.shutdown()
    target.httpd.shutdown()
    return all(results)


if __name__ == "__main__":
    probes = [probe_turn, probe_abort, probe_quit, probe_resume, probe_signal_stops_jobs, probe_reload, probe_slash, probe_reload_binary, probe_reload_keeps_grants, probe_reload_env_key, probe_reload_refused, probe_steering, probe_abort_queue, probe_failed_queue, probe_multiline, probe_new_session, probe_session_job_guard, probe_resume_sessions, probe_model_selection, probe_strict_label, probe_resume_strict, probe_model_and_destination, probe_sandbox_approval, probe_approval_abort, probe_session_narrowing_screen, probe_reset_ignores_unrelated_grants, probe_call_approvals, probe_allow_commands, probe_question_tool, probe_protected_paths]
    # --only A,F runs the probes whose heading starts with those letters (each prints "A: …" first).
    wanted = sys.argv[sys.argv.index("--only") + 1].split(",") if "--only" in sys.argv else None
    ok = True
    for probe in probes:
        label = next((c.split(":")[0] for c in probe.__code__.co_consts if isinstance(c, str) and re.match(r"[A-Z]\w*: ", c)), "?")
        if wanted is None or label in wanted:
            ok = probe() and ok
    print("PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)
