#!/usr/bin/env python3
"""End-to-end probe of the interactive screen over a PTY, against a local fake Anthropic server.

A: type a prompt; the screen shows it, the tool call, and the answer; the tool's effect is on disk.
B: a command that runs until stopped; Esc aborts it, its backgrounded child dies, and the screen says so.
C: Ctrl-C at an idle prompt quits, exit 0, with the terminal restored (the teardown bytes end the output).

Usage: Scripts/probe-interactive.py .build/release/ask
"""
import json
import shutil
import importlib.util, os, pty, select, signal, struct, sys, tempfile, time, fcntl, termios

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("agent_probe", os.path.join(here, "probe-agent-run.py"))
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)
ASK = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".build/release/ask")
FRAME_END = b"\x1b[?2026l"
ROWS, COLUMNS = 30, 100


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
    def __init__(self, server_url, project, state=None, arguments=(), config=None, binary=None):
        self.state = state or tempfile.mkdtemp()
        env = agent.environment(self.state, server_url, config)
        binary = binary or ASK
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


def probe_signal_stops_jobs():
    print("E: SIGTERM with a job running restores the terminal and stops the job")
    project, port = tempfile.mkdtemp(), agent.free_port()
    server = agent.Server([
        agent.turn([("call", "t1", "bash", {"command": f"exec python3 -m http.server {port} --bind 127.0.0.1", "yield_seconds": 1})], "tool_use"),
        agent.turn([("call", "t2", "wait", {"job": "job-1", "port_open": port, "timeout_seconds": 20})], "tool_use"),
        agent.turn([("text", "Serving.")], "end_turn")])
    screen = Screen(server.url, project)
    screen.until("ask>")
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
    screen = Screen(server.url, project, config=config)
    results = [check("prompt drawn", screen.until("ask>"))]

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
    screen.type("\x03")
    results.append(check("quits on Ctrl-C", screen.finish() == 0))
    server.httpd.shutdown()
    return all(results)


def probe_slash():
    print("G: slash commands")
    project, config = tempfile.mkdtemp(), tempfile.mkdtemp()
    os.makedirs(os.path.join(config, "ask"))
    server = agent.Server([agent.turn([("text", "Answer 1.")], "end_turn"),
                           agent.turn([("text", "Answer 2.")], "end_turn"),
                           agent.turn([("text", "SUMMARY: the user pasted notes.")], "end_turn"),
                           agent.turn([("text", "Answer 4.")], "end_turn")])
    screen = Screen(server.url, project, config=config)
    results = [check("prompt drawn", screen.until("ask>"))]

    def line(text):
        screen.type(text + "\r")

    line("/help")
    results += [check("/help lists the screen's commands", screen.until("/quit  Leave ask")),
                check("and the conversation's", screen.until("/compact  Summarise") and screen.until("/config  Read"))]
    line("/confg")
    results.append(check("an unknown command is an error, and no request was made",
                         screen.until("There is no command /confg; /help lists them.") and len(server.requests) == 0,
                         len(server.requests)))
    line("/compact")
    results.append(check("/compact with nothing recorded says so", screen.until("Nothing to compact yet.")))
    line("/config")
    results += [check("/config shows each setting with its source", screen.until("maxTurns  100  [default]")),
                check("and the files", screen.until("user file") and screen.until("(none)"))]
    open(os.path.join(config, "ask", "config.json"), "w").write("{maxTurns: 7}")
    line("/config")
    results += [check("/config reads the files again and announces the change", screen.until("maxTurns: 100 → 7")),
                check("and shows the new value from its file", screen.until("maxTurns  7  [") and screen.until("(applied)"))]
    line("/etc/hosts: what is this file?")
    results.append(check("a path is a prompt for the model", screen.until("Answer 1.") and len(server.requests) == 1
                         and "/etc/hosts: what is this file?" in json.dumps(server.requests[0]["body"]["messages"]),
                         len(server.requests)))
    screen.until_status("ready")
    line("/compact")
    results.append(check("/compact with only a short exchange says nothing could be summarised",
                         screen.until("Could not compact") and len(server.requests) == 1, len(server.requests)))
    screen.until_status("ready")
    # A prompt well past the 80 KB kept tail, pasted: bracketed paste, as a terminal sends it.
    screen.type("\x1b[200~Notes: " + "lorem ipsum " * 7500 + "\x1b[201~\r")
    results.append(check("a large prompt is answered", screen.until("Answer 2.", 30)))
    screen.until_status("ready")
    line("/compact")
    results += [check("/compact summarises the older conversation", screen.until("Compacted the conversation", 30)),
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
    screen = Screen(server.url, project, state, config=config, binary=binary)
    results = [check("prompt drawn", screen.until("ask>"))]
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
                check("with the earlier conversation shown", screen.until("› one") and screen.until("Answer 1."))]
    screen.until_status("ready")
    results.append(check("the terminal is raw again in the new process", not terminal_is_cooked(screen.fd)))
    screen.type("two\r")
    results.append(check("the next prompt works in the new process", screen.until("Answer 2.", 30)))
    screen.until_status("ready")
    files = agent.sessions(state)
    kinds = [json.loads(l)["payload"]["kind"] for l in open(files[0]) if '"type":"entry"' in l] if len(files) == 1 else files
    results.append(check("one session file holds both runs", kinds == ["user", "response", "user", "response"], kinds))
    if len(server.requests) >= 2:
        texts = [b.get("text", "") for m in server.requests[1]["body"]["messages"] for b in m["content"]]
        results.append(check("and the earlier exchange was sent again", "one" in texts and "Answer 1." in texts, texts))
    screen.type("/quit\r")
    results += [check("quits cleanly", screen.finish() == 0),
                check("and the terminal is back in line mode with echo", terminal_is_cooked(screen.fd))]
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
        agent.turn([("call", "t2", "wait", {"job": "job-1", "port_open": port, "timeout_seconds": 20})], "tool_use"),
        agent.turn([("text", "Serving.")], "end_turn"),
        agent.turn([("text", "Still here.")], "end_turn")])
    screen = Screen(server.url, project, state, config=config, binary=binary)
    screen.until("ask>")
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


def probe_steering():
    print("J: steering after the whole tool batch; a follow-up only after the agent finishes")
    project = tempfile.mkdtemp()
    server = agent.Server([
        agent.turn([("call", "gate1", "wait", {"file_exists": "release-one"}),
                    ("tool", "batch", "echo batch-finished > batch.txt")], "tool_use"),
        agent.turn([("call", "gate2", "wait", {"file_exists": "release-two"})], "tool_use"),
        agent.turn([("text", "BASE WORK FINISHED")], "end_turn"),
        agent.turn([("text", "FOLLOWUP ANSWER")], "end_turn")])
    screen = Screen(server.url, project)
    results = [check("initial prompt drawn", screen.until("ask>"))]
    screen.type("Start the work\r")
    results.append(check("first gate is running", screen.until("release-one")))
    screen.type("Later please\x1b[13;3u")  # CSI-u Alt+Enter, independent of legacy ESC/Enter ambiguity
    results.append(check("follow-up visibly queued", screen.until("Queued follow-up: Later please")))
    screen.type("Change direction\r")
    results.append(check("steering visibly queued", screen.until("Queued steering: Change direction")))
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
    print("K: abort returns unsent input alongside the draft, without persisting or running it")
    project = tempfile.mkdtemp()
    server = agent.Server([
        agent.turn([("call", "gate", "wait", {"file_exists": "never-created"})], "tool_use"),
        agent.turn([("text", "RECOVERED AFTER ABORT")], "end_turn")])
    screen = Screen(server.url, project)
    screen.until("ask>")
    screen.type("Start\r")
    results = [check("waiting in a tool", screen.until("never-created"))]
    screen.type("Unsent steering\r")
    results.append(check("steering queued", screen.until("Queued steering: Unsent steering")))
    screen.type("/follow-up Unsent followup\r")
    results.append(check("follow-up queued without a modified Enter key", screen.until("Queued follow-up: Unsent followup")))
    screen.type("draft\x1b")
    results.append(check("abort ends the run", screen.until_status("ready")))
    lines = screen.screen.text().splitlines()
    editor = lines[lines.index(next(line for line in lines if " · ready" in line)) + 1:]
    results.append(check("the editor holds both unsent messages and the draft on separate lines",
                         editor == ["ask> Unsent steering", "", "Unsent followup", "", "draft"], editor))
    results.append(check("nothing was automatically requested after abort", len(server.requests) == 1))
    screen.type("\x15\x7f" * 4 + "\x15Recovered\r")  # Ctrl-U and Backspace clear the five restored lines, one by one
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
        agent.turn([("call", "gate", "wait", {"file_exists": "release"})], "tool_use"),
        b'event: message_stop\ndata: {"type":"message_stop"}\n\n'])
    screen = Screen(server.url, project)
    screen.until("ask>")
    screen.type("Start\r")
    results = [check("waiting in a tool", screen.until("release"))]
    screen.type("Unsent followup\x1b[13;3u")
    results.append(check("follow-up queued", screen.until("Queued follow-up: Unsent followup")))
    open(os.path.join(project, "release"), "w").close()
    results.append(check("failed stream ends the run", screen.until_status("ready")))
    lines = screen.screen.text().splitlines()
    results.append(check("unsent input is back in the editor", lines[-1] == "ask> Unsent followup", lines[-1]))
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
    results = [check("prompt drawn", screen.until("ask>"))]
    screen.type("\x1b[200~alpha\nbeta\x1b[201~")  # a bracketed paste: its newline is not Enter
    screen.type("\x0agamma")  # Ctrl-J
    screen.type("\x1b[13;2udelta")  # Shift-Enter as a terminal reports it (CSI u)
    results.append(check("every line is on its own row",
                         screen.until("delta") and [l for l in screen.screen.text().split("\n") if l][-4:]
                         == ["ask> alpha", "beta", "gamma", "delta"], screen.screen.text()[-200:]))
    screen.type("\x1b[A\x1b[A")  # Up, Up: from "delta" to "beta", column 5 clamped to 4
    screen.type("\x15BETA")  # Ctrl-U deletes the line's start, then replace it
    results.append(check("the middle line is edited in place", screen.until("BETA")))
    results.append(check("nothing was sent yet", len(server.requests) == 0))
    screen.type("\r")
    results.append(check("the answer arrives", screen.until("Got all four lines.")))
    results.append(check("the transcript shows the prompt on four rows",
                         all(t in screen.screen.text() for t in ["› alpha", "  BETA", "  gamma", "  delta"])))
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


if __name__ == "__main__":
    ok = probe_turn() & probe_abort() & probe_quit() & probe_resume() & probe_signal_stops_jobs() & probe_reload() & probe_slash() & probe_reload_binary() & probe_reload_refused() & probe_steering() & probe_abort_queue() & probe_failed_queue() & probe_multiline()
    print("PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)
