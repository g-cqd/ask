"""A pyte screen that also scrolls a region, for the PTY probes.

ask moves the transcript with SU and SD (`CSI n S`, `CSI n T`) inside a scroll region (DECSTBM). pyte implements the region and the
one-line index and reverse index, but not SU or SD, so a probe reading after a scroll saw stale rows and had to force a full repaint with
a resize. With this screen the rows are what a terminal would show without that. Import it after pyte is on the path:

    sys.path.insert(0, os.environ.get("ASK_PYTE", "/tmp/ask-pty/lib"))
    import probe_screen
    screen, stream = probe_screen.make(columns, rows)
"""
import pyte


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


def make(columns, rows):
    screen = ScrollingScreen(columns, rows)
    return screen, ScrollingStream(screen)
