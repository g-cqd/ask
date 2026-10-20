#!/usr/bin/env python3
"""Drive the real `ask` binary in a pty with real mouse reports and read back what a terminal would show and receive.

No window is opened and nothing touches the clipboard: the terminal is announced as Ghostty or WezTerm, which take OSC 52, so the
host's pasteboard (`pbcopy`) is never used. The screen is read through `pyte`, a terminal emulator; install it first:

    python3 -m pip install --target /tmp/ask-pty/lib pyte
    ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-pointer.py [path/to/ask]

pyte does not implement scroll-down (`CSI T`), which the screen uses to move the transcript, so a row read right after a scroll can be
wrong. The probe forces a full repaint with a resize before it reads anything that scrolled.

Exit 0 when every check passes, 1 otherwise.
"""
import base64, fcntl, os, pty, re, select, shutil, signal, struct, sys, tempfile, termios, time

sys.path.insert(0, os.environ.get("ASK_PYTE", "/tmp/ask-pty/lib"))
import pyte

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
        for name in ("SSH_TTY", "SSH_CONNECTION", "TMUX", "KITTY_WINDOW_ID"):
            env.pop(name, None)
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.chdir(self.home)
            os.execve(ASK, [ASK], env)
        self.size(ROWS)
        self.screen = pyte.Screen(COLS, ROWS)
        self.stream = pyte.ByteStream(self.screen)
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


# /help prints ten lines; the row of "/quit  Leave ask, stopping a running turn first." is 20 on a 30-row screen.
QUIT, FOLLOW = 20, 21

t = with_help("ghostty")
check("the screen shows /help where the probe expects it", t.lines()[QUIT].startswith("/quit  Leave ask"), t.lines()[QUIT])
raw = bytes(t.raw)
check("the terminal is asked for mouse reports", b"\x1b[?1000h" in raw and b"\x1b[?1006h" in raw)

before = len(t.copies())
t.drag((7, QUIT), (15, QUIT))
check("a drag highlights exactly the dragged cells", t.inverse(QUIT) == list(range(7, 16)), str(t.inverse(QUIT)))
check("and copies exactly that text over OSC 52", t.copies()[before:] == ["Leave ask"], str(t.copies()[before:]))

before = len(t.copies())
t.drag((3, FOLLOW), (7, QUIT))
check(
    "a drag backwards across two rows reads them in order, the grapheme under the press included",
    t.copies()[before:] == ["Leave ask, stopping a running turn first.\n/fol"],
    str(t.copies()[before:]),
)

t.click(50, 25)
check("a click clears the selection", t.inverse(QUIT) == [] and t.inverse(FOLLOW) == [])

before = len(t.copies())
for _ in range(2):
    t.click(9, QUIT)
t.pump(0.4)
check("a double click copies the word", t.copies()[before:] == ["Leave"], str(t.copies()[before:]))
before = len(t.copies())
for _ in range(3):
    t.click(9, QUIT)
t.pump(0.4)
check(
    "a triple click copies the line",
    t.copies()[before:][-1:] == ["/quit  Leave ask, stopping a running turn first."],
    str(t.copies()[before:]),
)

t.type("x")
check("typing clears the selection and reaches the prompt", t.inverse(QUIT) == [] and t.lines()[ROWS - 1] == "ask> x")
t.close()

t = with_help("WezTerm")
t.drag((7, QUIT), (15, QUIT))
first = t.copies()
t.drag((0, QUIT), (5, QUIT))
check(
    "WezTerm gets its first copy twice and the next once",
    first == ["Leave ask", "Leave ask"] and t.copies()[len(first) :] == ["/quit "],
    str(t.copies()),
)
t.close()

t = with_help("ghostty", config="{ ui: { mouse: false } }")
check("ui.mouse false: the terminal is never asked for reports", b"\x1b[?1000h" not in bytes(t.raw))
t.drag((7, QUIT), (15, QUIT))
check("ui.mouse false: a drag selects and copies nothing", t.copies() == [] and t.inverse(QUIT) == [])
t.close()

t = with_help("ghostty", helps=4)
for _ in range(6):
    t.mouse(64, 40, 10)
t.pump(0.5)
t.repaint()
rows = t.lines()
check("the wheel scrolls back to the start of the conversation", rows[1].startswith("› /help"), str(rows[:3]))
known = ("› /help", "/help  ", "/quit  ", "/follow-up  ", "/config  ", "/compact  ", "/new  ", "/model  ", "/resume  ", "/reload  ")
malformed = [row for row in rows[: ROWS - 2] if row and not row.startswith(known)]
check("every row after the scroll is a whole line", malformed == [], str(malformed))
for _ in range(20):
    t.mouse(65, 40, 10, wait=0.03)
t.pump(0.4)
t.repaint()
check("the wheel brings the end back", t.lines()[ROWS - 3].startswith("/reload  "), t.lines()[ROWS - 3])
t.close()

print(f"\n{sum(results)} of {len(results)} checks passed")
sys.exit(0 if all(results) else 1)
