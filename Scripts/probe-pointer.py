#!/usr/bin/env python3
"""Drive the real `ask` binary in a pty with real mouse reports and read back what a terminal would show and receive.

No window is opened and nothing touches the clipboard: the terminal is announced as Ghostty or WezTerm, which take OSC 52, so the
host's pasteboard (`pbcopy`) is never used. The screen is read through `pyte`, a terminal emulator; install it first:

    python3 -m pip install --target /tmp/ask-pty/lib pyte
    ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-pointer.py [path/to/ask]

pyte does not implement SU and SD (`CSI S`, `CSI T`), which the screen uses to move the transcript; `probe_screen` adds them, so rows
read after a scroll are what a terminal shows. The scroll checks still force a full repaint before reading, as a second opinion.

Exit 0 when every check passes, 1 otherwise.
"""
import base64, fcntl, os, pty, re, select, shutil, signal, struct, sys, tempfile, termios, time

sys.path.insert(0, os.environ.get("ASK_PYTE", "/tmp/ask-pty/lib"))
import pyte

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probe_screen
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probe_keychain

ASK = os.path.abspath(
    sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", ".build", "debug", "ask")
)
COLS, ROWS = 100, 30
results = []


def check(name, ok, detail=""):
    results.append(ok)
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f"   {detail}"))


class Terminal:
    def __init__(self, program, config=None):
        self.home = tempfile.mkdtemp()
        os.makedirs(self.home + "/ask")
        if config:
            open(self.home + "/ask/config.json", "w").write(config)
        env = dict(os.environ, TERM="xterm-256color", TERM_PROGRAM=program, XDG_CONFIG_HOME=self.home, HOME=self.home)
        env["ASK_KEYCHAIN_PATH"] = probe_keychain.throwaway_keychain()  # never the person's keychain
        for name in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
            env.pop(name, None)
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.chdir(self.home)
            os.execve(ASK, [ASK], env)
        self.size(ROWS)
        self.screen, self.stream = probe_screen.make(COLS, ROWS)
        self.raw = bytearray()
        self.pump(3)

    def size(self, rows):
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, COLS, 0, 0))

    def pump(self, seconds):
        end = time.time() + seconds
        while time.time() < end:
            ready, _, _ = select.select([self.fd], [], [], 0.05)
            if ready:
                try:
                    data = os.read(self.fd, 65536)
                except OSError:
                    return
                if not data:
                    return
                self.raw.extend(data)
                self.stream.feed(data)

    def type(self, text):
        os.write(self.fd, text.encode())
        self.pump(1.2)

    def lines(self):
        return [self.screen.display[row].rstrip() for row in range(self.screen.lines)]

    def rules(self):
        return [row for row, line in enumerate(self.lines()) if line.startswith("\u2500" * 10)]

    def prompt(self):
        """The prompt's text: the rows between the last two rules (the prompt has no marker of its own)."""
        rules = self.rules()
        return "\n".join(self.lines()[rules[-2] + 1 : rules[-1]]) if len(rules) >= 2 else None

    def status(self):
        """The status is the last row with text, below the prompt's lower rule."""
        return next((line for line in reversed(self.lines()) if line), "")

    def transcript(self):
        """The rows above the prompt, without the left margin, blank rows dropped."""
        rules = self.rules()
        rows = self.lines()[: rules[-2] if len(rules) >= 2 else ROWS]
        return [row.strip() for row in rows if row.strip()]

    def inverse(self, row):
        return [col for col in range(COLS) if self.screen.buffer[row][col].reverse]

    def mouse(self, button, col, row, release=False, wait=0.05):
        os.write(self.fd, f"\x1b[<{button};{col + 1};{row + 1}{'m' if release else 'M'}".encode())
        self.pump(wait)

    def click(self, col, row):
        self.mouse(0, col, row, wait=0.02)
        self.mouse(0, col, row, release=True)

    def drag(self, start, end):
        self.mouse(0, *start, wait=0.1)
        self.mouse(32, *end, wait=0.1)
        self.mouse(0, *end, release=True, wait=0.5)

    def copies(self):
        found = re.findall(rb"\x1b\]52;c;([A-Za-z0-9+/=]+)(?:\x07|\x1b\\)", bytes(self.raw))
        return [base64.b64decode(item).decode("utf8", "replace") for item in found]

    def repaint(self):
        """A resize makes ask repaint every row by position, which pyte reads correctly after a scroll."""
        self.size(ROWS + 1)
        os.kill(self.pid, signal.SIGWINCH)
        self.screen.resize(ROWS + 1, COLS)
        self.pump(0.8)
        self.size(ROWS)
        os.kill(self.pid, signal.SIGWINCH)
        self.screen.resize(ROWS, COLS)
        self.pump(0.8)

    def close(self):
        try:
            os.kill(self.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        shutil.rmtree(self.home, ignore_errors=True)


def with_help(program, helps=1, config=None):
    terminal = Terminal(program, config)
    for _ in range(helps):
        terminal.type("/help\r")
    return terminal


def found(terminal, start):
    """The row whose text, after the left margin, starts with `start`, and the column of that text; (-1, -1) when absent."""
    for row, line in enumerate(terminal.lines()):
        if line.lstrip().startswith(start):
            return row, len(line) - len(line.lstrip())
    return -1, -1


NOTICE = "Nothing is signed in"  # the first row of a conversation with no account: where the start is


def at_start(terminal):
    rows = terminal.transcript()
    # Every /help listing starts with a "/help" row, so only the notice above the first one says this is the start.
    return bool(rows) and rows[0].startswith(NOTICE) and rows[1:2] == ["/help"]


def wheel(terminal, button, limit=80):
    """Turns the wheel until the transcript stops moving: enough to reach either end however long /help has grown."""
    last = None
    for _ in range(limit):
        terminal.mouse(button, 40, 10, wait=0.03)
        terminal.pump(0.05)
        now = terminal.lines()
        if now == last:
            break
        last = now
    terminal.pump(0.3)
    terminal.repaint()


# /help prints one line a command, so its rows move each time a command is added: they are found, not counted, and so is the left margin.
t = with_help("ghostty")
QUIT, MARGIN = found(t, "/quit  Leave ask")
FOLLOW = QUIT + 1
LEAVE = MARGIN + len("/quit  ")
check("the screen shows /help where the probe expects it", QUIT > 0, str(t.lines()))
found_listing = t.transcript()
check("the user prompt has no leading marker", "/help" in t.transcript()[:1], str(t.transcript()[:2]))
check("the status has no painted inverse surface", t.inverse(ROWS - 1) == [], t.status())
raw = bytes(t.raw)
check("the terminal is asked for mouse reports", b"\x1b[?1000h" in raw and b"\x1b[?1006h" in raw)

before = len(t.copies())
t.drag((LEAVE, QUIT), (LEAVE + 8, QUIT))
check("a drag highlights exactly the dragged cells", t.inverse(QUIT) == list(range(LEAVE, LEAVE + 9)), str(t.inverse(QUIT)))
check("and copies exactly that text over OSC 52", t.copies()[before:] == ["Leave ask"], str(t.copies()[before:]))

before = len(t.copies())
t.drag((MARGIN + 3, FOLLOW), (LEAVE, QUIT))
following = t.lines()[FOLLOW][MARGIN : MARGIN + 4]
check(
    "a drag backwards across two rows reads them in order, the grapheme under the press included",
    t.copies()[before:] == ["Leave ask, stopping a running turn first.\n" + following],
    str(t.copies()[before:]),
)

t.click(50, 2)
check("a click clears the selection", t.inverse(QUIT) == [] and t.inverse(FOLLOW) == [])

before = len(t.copies())
for _ in range(2):
    t.click(LEAVE + 2, QUIT)
t.pump(0.4)
check("a double click copies the word", t.copies()[before:] == ["Leave"], str(t.copies()[before:]))
before = len(t.copies())
for _ in range(3):
    t.click(LEAVE + 2, QUIT)
t.pump(0.4)
check(
    "a triple click copies the line",
    t.copies()[before:][-1:] == ["/quit  Leave ask, stopping a running turn first."],
    str(t.copies()[before:]),
)

t.type("x")
check("typing clears the selection and reaches the prompt", t.inverse(QUIT) == [] and t.prompt() == "x", repr(t.prompt()))
t.close()

t = with_help("WezTerm")
t.drag((LEAVE, QUIT), (LEAVE + 8, QUIT))
first = t.copies()
t.drag((MARGIN, QUIT), (MARGIN + 5, QUIT))
check(
    "WezTerm gets its first copy twice and the next once",
    first == ["Leave ask", "Leave ask"] and t.copies()[len(first) :] == ["/quit "],
    str(t.copies()),
)
t.close()

t = with_help("ghostty", config="{ ui: { copyOnSelect: false } }")
t.drag((LEAVE, QUIT), (LEAVE + 8, QUIT))
check(
    "copy-on-select off keeps the highlight without copying",
    t.copies() == [] and t.inverse(QUIT) == list(range(LEAVE, LEAVE + 9)),
    f"{t.copies()} {t.inverse(QUIT)}",
)
check("the status explains keyboard copy", "ctrl+c copy" in t.status(), t.status())
t.type("\x03")
check("Ctrl+C explicitly copies and consumes the selection", t.copies() == ["Leave ask"] and t.inverse(QUIT) == [], str(t.copies()))
# Only a copy that went wrong is announced (roadmap 0074): one that was sent says nothing.
check("the status says nothing about a copy that worked", "opy" not in t.status(), t.status())
t.type("x")
check("copy did not quit the screen", t.prompt() == "x", repr(t.prompt()))
t.close()

t = with_help("ghostty", config="{ ui: { mouse: false } }")
check("ui.mouse false: the terminal is never asked for reports", b"\x1b[?1000h" not in bytes(t.raw))
t.drag((LEAVE, QUIT), (LEAVE + 8, QUIT))
check("ui.mouse false: a drag selects and copies nothing", t.copies() == [] and t.inverse(QUIT) == [])
t.close()

t = with_help("ghostty", helps=4)
end = t.transcript()
listing = set(found_listing)  # every row /help draws, the wrapped continuations included, read from the first screen
wheel(t, 64)
rows = t.transcript()
check(
    "the wheel scrolls back to the start of the conversation",
    at_start(t) and rows[rows.index("/help") + 1].startswith("/help  "), str(rows[:3])
)
malformed = [row for row in rows if row not in listing and not row.startswith(NOTICE)]
check("every row after the scroll is a whole line", malformed == [], str(malformed))
wheel(t, 65)
check("the wheel brings the end back", t.transcript() == end, str(t.transcript()[-2:]))
t.close()

t = with_help("ghostty", helps=4)
before = len(t.copies())
t.mouse(0, 5, 12, wait=0.1)
t.mouse(32, 5, 0, wait=0.1)
t.mouse(0, 5, 0, release=True, wait=0.4)
brief = t.copies()[before:]
check("a drag at the edge that is released at once copies only a little", len(brief) == 1 and brief[0].count("\n") < 25, str(brief))
t.close()

t = with_help("ghostty", helps=4)
before = len(t.copies())
t.mouse(0, 5, 12, wait=0.1)
t.mouse(32, 5, 0, wait=0.1)
# The button is held still: a terminal reports no motion, so only the timer can scroll. Held until the start is in view (or 15 s).
held_for = time.time()
t.pump(1.0)
check("a held drag shows no copy before release", t.copies()[before:] == [])
while time.time() - held_for < 15 and not at_start(t):
    t.pump(0.5)
t.pump(0.5)
t.mouse(0, 5, 0, release=True, wait=0.5)
held = t.copies()[before:]
check(
    "a drag held still at the top edge scrolls to the start and selects everything it passed",
    len(held) == 1 and held[0].startswith(NOTICE) and held[0].count("/quit") >= 3
    and held[0].count("\n") >= brief[0].count("\n") + 8,
    f"held lines={held[0].count(chr(10)) + 1 if held else 0} quits={held[0].count('/quit') if held else 0}; "
    f"brief lines={brief[0].count(chr(10)) + 1}; {time.time() - held_for:.1f} s",
)
t.repaint()
check("the screen is left scrolled to the start", at_start(t), str(t.transcript()[:3]))
t.close()

print(f"\n{sum(results)} of {len(results)} checks passed")
sys.exit(0 if all(results) else 1)
