"""A pyte screen that also scrolls a region, for the PTY probes.

ask moves the transcript with SU and SD (`CSI n S`, `CSI n T`) inside a scroll region (DECSTBM). pyte implements the region and the
one-line index and reverse index, but not SU or SD, so a probe reading after a scroll saw stale rows and had to force a full repaint with
a resize. With this screen the rows are what a terminal would show without that. It also reads kitty's colon underline (`ESC[4:1m`), which
pyte took for text. It finds pyte itself (`probe_pyte`):

    import probe_screen
    screen, stream = probe_screen.make(columns, rows)
"""
import re

import probe_pyte

probe_pyte.ensure()
import pyte  # noqa: E402

# An SGR sequence, and an unfinished one at the end of a read.
_SGR = re.compile(rb"\x1b\[([0-9;:]*)m")
_TAIL = re.compile(rb"\x1b(\[[0-9;:]*)?$")


def _plain_sgr(match):
    """The SGR with kitty's colon forms as pyte reads them: `4:0` is 24, `4:N` is 4, and other sub-parameters (an underline's colour)
    are left out. pyte takes the colon for text, so `ESC[4:1m` drew "1m" on the screen."""
    params = []
    for param in match.group(1).split(b";"):
        if b":" not in param:
            params.append(param)
        elif param.startswith(b"4:"):
            params.append(b"24" if param == b"4:0" else b"4")
    return b"\x1b[" + b";".join(params) + b"m"


class ScrollingScreen(pyte.Screen):
    def _region(self):
        return self.margins or pyte.screens.Margins(0, self.lines - 1)

    def scroll_up(self, count=None, *args, **kwargs):
        """SU: the rows of the region move up `count` lines; blank lines enter at its bottom. The cursor stays."""
        top, bottom = self._region()
        for _ in range(min(max(count or 1, 1), bottom - top + 1)):
            for y in range(top, bottom):
                self.buffer[y] = self.buffer[y + 1]
            self.buffer.pop(bottom, None)
        self.dirty.update(range(self.lines))

    def scroll_down(self, count=None, *args, **kwargs):
        """SD: the rows of the region move down `count` lines; blank lines enter at its top. The cursor stays."""
        top, bottom = self._region()
        for _ in range(min(max(count or 1, 1), bottom - top + 1)):
            for y in range(bottom, top, -1):
                self.buffer[y] = self.buffer[y - 1]
            self.buffer.pop(top, None)
        self.dirty.update(range(self.lines))


class ScrollingStream(pyte.ByteStream):
    csi = dict(pyte.ByteStream.csi, S="scroll_up", T="scroll_down")

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._carry = b""

    def feed(self, data):
        data = self._carry + bytes(data)
        tail = _TAIL.search(data)
        self._carry = data[tail.start():] if tail else b""
        data = data[:tail.start()] if tail else data
        super().feed(_SGR.sub(_plain_sgr, data))


def make(columns, rows):
    screen = ScrollingScreen(columns, rows)
    return screen, ScrollingStream(screen)


def unboxed(line):
    """A screen row as text, an input row without the box's borders (note n36): `│ ask> hi   │` reads `ask> hi`."""
    text = line.rstrip()
    if text.startswith("│ ") and text.endswith("│"):
        text = text[2:-1].rstrip()
    return text


def is_box_edge(line):
    """Whether a row is the input box's top or bottom edge: `╭───╮` or `╰───╯`, perhaps with the sidebar beside it."""
    return line.startswith("╭─") or line.startswith("╰─")
