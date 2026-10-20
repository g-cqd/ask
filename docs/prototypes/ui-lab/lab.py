#!/usr/bin/env python3
"""Disposable UI prototype for ask. Everything shown is fixture data.

No network, no subprocesses, no tool execution, nothing outside this file is touched.
Pixel lines use the kitty graphics protocol when available and fall back to glyphs.
"""
import argparse, base64, fcntl, json, math, os, re, select, shutil, struct, sys, termios, time, tty, unicodedata, zlib

# Only used to fill an ANSI colour the terminal did not report; the lab never paints a background.
PRESETS = {
    'light': dict(base='#ffffff', fg='#111111',
                  ansi={1: '#b3261e', 2: '#1b6636', 3: '#8a5a00', 4: '#154b85', 5: '#8a2f8f', 6: '#0b6b73', 8: '#6c7787'}),
    'dark': dict(base='#0e1217', fg='#f0f3f8',
                 ansi={1: '#ff9d9d', 2: '#8ee0ae', 3: '#f2c777', 4: '#8fc0ff', 5: '#e0a8ff', 6: '#7fe0e8', 8: '#66748a'}),
}
ACCENTS = {'blue': 4, 'cyan': 6, 'magenta': 5, 'green': 2, 'yellow': 3}
# How visible hairlines, rules and the scrollbar track are: (share of the foreground in the stroke, least contrast it keeps
# against the terminal's own background).
STROKES = {'subtle': (0.22, 1.4), 'normal': (0.35, 2.0), 'strong': (0.45, 2.6)}
BOTTOMS = ['roomy', 'tight', 'flush']
PADS = [0, 1]                    # rows of padding above and below the content of every block: none, or one block row
LAYOUTS = ['standard', 'workbench']             # standard: spacing and a separator between blocks. workbench: adds a sidebar
# The ANSI colour numbers used when the terminal does not report its own colours (so light and dark terminals both work).
ANSI_FALLBACK = dict(fg='ansi:39', muted='ansi:2;39', faint='ansi:2;39', line='ansi:2;39', good='ansi:32', warn='ansi:33', bad='ansi:31')
ANSI_ACCENT = {'blue': 'ansi:34', 'cyan': 'ansi:36', 'magenta': 'ansi:35', 'green': 'ansi:32', 'yellow': 'ansi:33'}
HEX_FOR_IMAGES = dict(line='#7f7f7f', accent='#4a90e2')       # pixel strokes cannot use an ANSI colour


def hex_rgb(h):
    h = h.lstrip('#')
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def rgb_hex(c):
    return '#%02x%02x%02x' % tuple(max(0, min(255, round(v))) for v in c)


def blend(a, b, t):
    ca, cb = hex_rgb(a), hex_rgb(b)
    return rgb_hex([ca[i] * (1 - t) + cb[i] * t for i in range(3)])


def luminance(h):
    def lin(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (lin(v) for v in hex_rgb(h))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def ensure(color, base, minimum, fg):
    """Nudge `color` away from `base` until it reaches a contrast ratio, toward fg (or the opposite extreme)."""
    if contrast(color, base) >= minimum:
        return color
    target = fg if contrast(fg, base) >= minimum else ('#ffffff' if luminance(base) < 0.4 else '#000000')
    for step in range(1, 21):
        trial = blend(color, target, step / 20)
        if contrast(trial, base) >= minimum:
            return trial
    return target


def derive(base, fg, ansi, accent='blue', stroke='subtle'):
    """The text colours, derived from the terminal's own background, foreground and ANSI palette. Nothing here is a
    background: the lab never paints one, so hierarchy rests on these colours, on type and on spacing."""
    fallback = PRESETS['dark' if luminance(base) < 0.4 else 'light']['ansi']
    pick = lambda i: ansi.get(i) or fallback[i]
    share, least = STROKES[stroke]
    return dict(
        base=base, fg=ensure(fg, base, 7.0, fg),
        muted=ensure(blend(fg, base, 0.22), base, 5.0, fg), faint=ensure(blend(fg, base, 0.40), base, 4.5, fg),
        line=ensure(blend(base, fg, share), base, least, fg),
        accent=ensure(pick(ACCENTS[accent]), base, 4.5, fg),
        good=ensure(pick(2), base, 4.5, fg), warn=ensure(pick(3), base, 4.5, fg), bad=ensure(pick(1), base, 4.5, fg))


SEPS = ['pixel line', 'block line']       # block line (an eighth-block glyph) is what terminals without pixels get
DATA = {
    'commands': [('/model', 'Switch provider and model', 'SETTING', 'Local UI action. No model request.'),
                 ('/review', 'Review the working diff', 'PROMPT', 'Expands a saved prompt into your draft.'),
                 ('/compact', 'Summarize conversation context', 'ACTION', 'Uses the model. Confirms before starting.'),
                 ('/code-review', 'Find defects in a code change', 'SKILL', '~/.agents/skills/code-review/SKILL.md\nLoads instructions for this request only.\nSelecting grants no tool permission.'),
                 ('/swift', 'Swift APIs, isolation and concurrency', 'SKILL', '~/.agents/skills/swift/SKILL.md\nLoads instructions for this request only.'),
                 ('/project-checks', 'Run the project verification recipe', 'SKILL', '.agents/skills/project-checks/SKILL.md\nProject skill: review before trusting.'),
                 ('/agents', 'Open agent activity', 'VIEW', 'Inspect child agents without changing them.'),
                 ('/sessions', 'Open active sessions', 'VIEW', 'Sessions you can address with @ and talk to directly.'),
                 ('/tasks', 'Open task list', 'VIEW', 'Inspect work without changing it.'),
                 ('/theme', 'Tune the accent, lines, padding and layout', 'SETTING', 'Opens the settings panel. Changes apply live.'),
                 ('/clear', 'Start a new conversation', 'ACTION', 'The current conversation stays in history.')],
    'refs': [('docs/rendering.md:42-58', 'Rendering ownership and cancellation', 'FILE', '42  A frame has exactly one owner.\n43  Input never waits for composition.\n44  Stop the renderer before restoration.'),
             ('src/ScreenSession.swift', 'Event application and frame submission', 'FILE', 'The event loop applies an update,\nthen submits state. The render thread\ntakes the newest revision.'),
             ('docs/decisions/0014.md', 'Why rendering has its own thread', 'FILE', 'Decision: single-owner rendering.\nTradeoff: one thread, bounded queue.'),
             ('reviewer', 'Read-only review of the render loop', 'AGENT', 'Tools: read, search. No edits.\nMention to delegate; opens a child task.'),
             ('explorer', 'Map input ownership', 'AGENT', 'Tools: read, search. No edits.\nMention to delegate; opens a child task.'),
             ('session:render-review', 'Active session · reviewer · running', 'SESSION', 'Your message goes to that session, not to this one.\nIt keeps its own context and permissions.\nEsc removes the address; nothing is sent until Enter.'),
             ('session:docs-pass', 'Active session · idle 4m', 'SESSION', 'Your message goes to that session, not to this one.\nIt keeps its own context and permissions.')],
    'agents': [('reviewer', 'Read-only review of the render loop', 'RUNNING', 'Child of main / task 2\nTools: read, search. No edits.\nEnter opens its transcript.'),
               ('test-runner', 'Regression suite', 'BLOCKED', 'Child of main / task 3\nWaiting for permission: swift test\nPermission request: [p]'),
               ('explorer', 'Map input ownership', 'DONE', 'Child of main / task 1\nResult: input and rendering are independent.')],
    'tasks': [('1  Trace the event path', 'explorer', 'DONE', 'Input, events, state, newest frame.\nEvidence: input-stall regression test.'),
              ('2  Review render cancellation', 'reviewer', 'RUNNING', 'Checking halt and finish races.\nNo changes requested yet.'),
              ('3  Verify terminal restoration', 'test-runner', 'BLOCKED', 'Waiting for command approval.\nNothing is approved silently.'),
              ('4  Summarize findings', 'main', 'QUEUED', 'Starts after tasks 2 and 3.')],
    'permission': [('Deny', 'Do not run the command', 'SAFE', 'swift test --filter RestorationTests\ncwd /project/ask  by test-runner / task 3\nAllow once does not authorize later commands.'),
                   ('Allow once', 'Authorize only this invocation', 'ONCE', 'swift test --filter RestorationTests\ncwd /project/ask  by test-runner / task 3\nMock only. Nothing will run.')],
}
TRIGGERS = {'/': 'commands', '@': 'refs'}
BROWSE_MODALS = {'a': 'agents', 't': 'tasks', 'p': 'permission'}
BAR = ' ▏▎▍▌▋▊▉█'


def width(s):
    if s.isascii():
        return len(s)
    return sum(0 if unicodedata.combining(c) else 2 if unicodedata.east_asian_width(c) in 'WF' else 1 for c in s)


def fit(s, n):
    if n <= 0:
        return ''
    if s.isascii():
        return s[:n]
    used, out = 0, []
    for c in s:
        w = 0 if unicodedata.combining(c) else 2 if unicodedata.east_asian_width(c) in 'WF' else 1
        if used + w > n:
            break
        used += w
        out.append(c)
    return ''.join(out)


def wrap(text, n):
    n = max(8, n)
    lines, cur = [], ''
    for word in text.split(' '):
        trial = (cur + ' ' + word) if cur else word
        if width(trial) <= n:
            cur = trial
            continue
        if cur:
            lines.append(cur)
        cur = word
        while width(cur) > n:
            head = fit(cur, n)
            lines.append(head)
            cur = cur[len(head):]
    lines.append(cur)
    return lines


def png(w, h, raw):
    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw, 6)) + chunk(b'IEND', b''))


SETTING_ROWS = [
    ('Accent', 'accent', list(ACCENTS), 'Which of your terminal\'s ANSI colours is the accent: the focus, the mode, selections. It colours text only.'),
    ('Separators', 'sep', SEPS, 'pixel line: a real 1 or 2 pixel line between blocks, costing no row (kitty graphics). block line: an eighth-block glyph row, for terminals without pixels.'),
    ('Line thickness', 'thick', ['1px', '2px'], 'Pixel lines and the scrollbar only.'),
    ('Strokes', 'stroke', list(STROKES), 'How visible lines and the scrollbar track are. subtle keeps just enough contrast with your terminal\'s background to find the edge.'),
    ('Block padding', 'pad', ['none', '1 block'], 'One blank row above and below the content of every block: yours, the assistant\'s, thinking, tool calls, and the input.'),
    ('Bottom section', 'bottom', BOTTOMS, 'roomy: work strip, two-row input, status. tight: no work strip. flush: one-row input with its chips inline, then status.'),
    ('Layout', 'layout', LAYOUTS, 'standard: one column, blocks spaced and separated. workbench: standard plus a sidebar of tasks, agents and context.'),
]
SAVED = ['accent', 'pad', 'sep', 'thick', 'stroke', 'bottom', 'layout']


INNER = 2          # columns of padding inside a block, left and right of its text


class Line:
    """One row of the transcript. role: 'content', 'pad' (a blank row of padding inside a block) or 'sep' (a block-line row).
    There is no background, no leading bar and no leading icon: hierarchy is spacing, type and colour."""
    def __init__(self, spans, edge=False, role='content', block=-1, right=None, italic=False):
        self.spans, self.edge, self.role, self.block = spans, edge, role, block
        self.right = right          # text aligned to the right edge, such as "ctrl+t to expand"
        self.italic = italic


KINDS = ('user', 'out', 'think', 'tool')       # the kinds of block. Nothing is painted behind any of them.


class Lab:
    def __init__(self, layout='standard'):
        self.layout, self.sep, self.thick = layout, 0, 1
        self.gfx = False
        self.accent, self.bottom, self.pad = 'blue', 0, 1
        self.stroke = 'subtle'
        self.strokes = []           # vertical strokes drawn this frame: the lab asserts there is one at a boundary
        self.img_clip, self.placed, self.phase = None, [], 'page'   # rows an open popup hides from images; every placement, for tests
        self.term = None            # colours read from the terminal (OSC 10/11/4), or None
        self.rescan = False         # set when the terminal says its colour scheme changed
        self.retheme()
        self.thinking = self.tools = False
        self.browse = False
        self.modal = self.trigger = None
        self.after = None
        self.query, self.selected = '', 0
        self.draft = 'Review cancellation in the rendering loop.'
        self.cursor = len(self.draft)
        self.chips = [('file', 'rendering.md:42-58'), ('skill', 'code-review')]
        self.sent = []
        self.scroll = 0
        self.toast = ''
        self.cw = self.ch = 0
        self.force_gfx = False
        self.cache, self.next_id = {}, 100
        self.page = 10

    # ---------- colour and drawing primitives ----------
    def retheme(self):
        if self.term:
            self.pal = derive(self.term['base'], self.term['fg'], self.term['ansi'], self.accent, self.stroke)
            self.theme_note = 'your terminal\'s colours (OSC 10/11/4)'
        else:
            # The terminal did not say. Plain ANSI colours adapt to a light or a dark terminal without guessing a palette.
            self.pal = dict(ANSI_FALLBACK, accent=ANSI_ACCENT[self.accent], base='#000000')
            self.theme_note = 'the terminal did not report its colours: using ANSI colours'

    def col(self, name):
        return self.pal.get(name, name)

    def bg_code(self, name):
        return '\033[49m'              # never painted: the terminal's own background, its opacity, blur and wallpaper

    def fg_code(self, name):
        value = self.col(name)
        if value.startswith('ansi:'):
            return '\033[' + value[5:] + 'm'
        if name == 'fg' and self.term and value == self.term['fg']:
            return '\033[39m'
        return self.rgb(value)

    @staticmethod
    def rgb(hexcolor, bg=False):
        h = hexcolor.lstrip('#')
        return '\033[%d;2;%d;%d;%dm' % (48 if bg else 38, int(h[:2], 16), int(h[2:4], 16), int(h[4:], 16))

    def put(self, x, y, text, fg='fg', bg=None, bold=False, rev=False, italic=False, raw=False):
        """Draw text. `bg` is accepted and ignored: nothing in this UI is ever painted behind the text."""
        if fg == 'accentfg':
            fg, bold = 'accent', True
        if y < 0 or y >= min(self.h, self.clip_y) or x >= self.xlim or not text:
            return
        text = fit(text, self.xlim - x)
        if not text:
            return
        for i, c in enumerate(text):
            if x + i < self.w:
                self.grid[y][x + i] = c
        sgr = '\033[0' + (';1' if bold else '') + (';3' if italic else '') + (';7' if rev else '') + 'm'
        self.out.append(f'\033[{y+1};{x+1}H' + sgr + self.fg_code(fg) + self.bg_code(bg) + text)

    def fill(self, x, y, w, bg):
        self.put(x, y, ' ' * max(0, w), 'fg', bg)

    # ---------- kitty graphics (true pixel lines) ----------
    def gfx_ok(self):
        return self.force_gfx or bool(self.cw and self.ch and 'kitty' in os.environ.get('TERM', ''))

    def image(self, key, w, h, raw):
        if key in self.cache:
            return self.cache[key]
        ident = self.next_id
        self.next_id += 1
        data = base64.standard_b64encode(png(w, h, raw)).decode()
        parts = [data[i:i + 4096] for i in range(0, len(data), 4096)] or ['']
        for n, part in enumerate(parts):
            more = 1 if n < len(parts) - 1 else 0
            self.out.append(f'\033_Ga=t,f=100,i={ident},q=2,m={more};{part}\033\\' if n == 0 else f'\033_Gm={more};{part}\033\\')
        self.cache[key] = ident
        return ident

    def place(self, ident, x, y, xoff=0, yoff=0, rows=1):
        """Place an image at a cell. Images sit above the text layer, so one under an open popup would show through it:
        rows inside the popup are skipped, and a tall image that runs into it is cropped (kitty's source-rect height)."""
        crop, visible = '', rows
        if self.img_clip is not None:
            top, bottom = self.img_clip
            if top <= y < bottom:
                return
            if y < top < y + rows:
                crop, visible = f',h={(top - y) * self.ch}', top - y
        self.placed.append((y, visible, self.phase))
        self.out.append(f'\033[{y+1};{x+1}H\033_Ga=p,i={ident},C=1,z=1,q=2,X={xoff},Y={yoff}{crop}\033\\')

    def rgba(self, name):
        value = self.col(name)
        h = (HEX_FOR_IMAGES.get(name, '#7f7f7f') if value.startswith('ansi:') else value).lstrip('#')
        return bytes([int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255])

    def px_hline(self, x, y, w, color='line', yoff=0):
        wpx, t = w * self.cw, self.thick
        raw = (b'\0' + self.rgba(color) * wpx) * t
        self.place(self.image(('h', wpx, t, self.col(color)), wpx, t, raw), x, y, 0, yoff, 1)

    def px_vline(self, x, y, h, color='line'):
        t, hpx = self.thick, h * self.ch
        raw = (b'\0' + self.rgba(color) * t) * hpx
        self.place(self.image(('v', hpx, t, self.col(color)), t, hpx, raw), x, y, self.cw // 2, 0, h)

    def px_scrollbar(self, x, y, rows, start_px, size_px, edge=False):
        """Track and thumb as pixels. `edge`: the track is the last pixel column of the cell, flush with what follows."""
        hpx = rows * self.ch
        track, thumb = self.rgba('line'), self.rgba('accent')
        clear = bytes(4)
        if edge:
            row_track, row_thumb, wpx, xoff = clear + track + clear, thumb * 3, 3, self.cw - 2
        else:
            row_track, row_thumb, wpx, xoff = clear * 2 + track + clear * 2, clear + thumb * 3 + clear, 5, max(0, self.cw - 6)
        lines = [b'\0' + (row_thumb if start_px <= r < start_px + size_px else row_track) for r in range(hpx)]
        key = ('s', hpx, start_px, size_px, wpx, self.col('line'), self.col('accent'))
        self.place(self.image(key, wpx, hpx, b''.join(lines)), x, y, xoff, 0, rows)

    # ---------- separators ----------
    def pixel(self):
        """True when separators are real pixel lines: chosen, and the terminal can draw them."""
        return self.sep == 0 and self.gfx

    def sep_rows(self):
        """Rows a separator costs: none as a pixel line, one as a block-line row."""
        return 0 if self.pixel() else 1

    def rule(self, y, x, w, color='line'):
        if self.pixel():
            self.px_hline(x, y, w, color)
        else:
            self.put(x, y, '▁' * w, color)

    def vrule(self, x, y, h, bg=None, color='line'):
        if self.pixel():
            self.px_vline(x, y, h, color)
        else:
            for r in range(y, y + h):
                self.put(x, r, '│', color)

    # ---------- transcript ----------
    def blocks(self, tw):
        """The conversation as blocks: [kind, [Line]]. Adjacent lines of one kind share a block; a message is its own."""
        n = max(8, tw - 2 * INNER)
        out = []

        def add(kind, line):
            if out and out[-1][0] == kind and kind != 'user':
                out[-1][1].append(line)
            else:
                out.append([kind, [line]])

        def span(text, fg='fg', bold=False):
            return (text, fg, None, bold)

        def user(text):
            out.append(['user', []])
            for t in wrap(text, n):
                out[-1][1].append(Line([span(t, 'fg', True)]))

        def assistant(text):
            for t in wrap(text, n):
                add('out', Line([span(t)]))

        def disclosure(kind, open_, label, detail, body, key):
            add(kind, Line([span(label, 'faint' if kind == 'think' else 'muted'), span(('  ' + detail) if detail else '', 'faint')],
                           right=(f'{key} to ' + ('collapse' if open_ else 'expand'), 'faint'), italic=kind == 'think'))
            if open_:
                for t in body:
                    add(kind, Line([span('  ' + fit(t, n - 2), 'faint' if kind == 'think' else 'muted')], italic=kind == 'think'))

        def agents():
            add('tool', Line([span('reviewer', 'fg', True), span('  cancellation races', 'muted'), span('   running 0:42', 'good')]))
            add('tool', Line([span('test-runner', 'fg', True), span('  restoration regression', 'muted'), span('   needs approval', 'warn', True)]))

        def diff():
            add('tool', Line([span('src/RenderLoop.swift', 'muted', True), span('   +2 −1', 'faint')]))
            add('tool', Line([span('− try pipeline.flush()', 'bad')]))
            add('tool', Line([span('+ try halt()  // finish before restore', 'good')]))
            add('tool', Line([span('+ terminal.leave()', 'good')]))

        topics = ['Where does a frame get its state?', 'Which state is shared between input and rendering?',
                  'What happens to a frame in flight on resize?', 'Does the status line ever block input?',
                  'How is the terminal restored after a signal?']
        for k in range(12):
            last = k == 11
            user(topics[k % 5] if not last else 'Review cancellation in the rendering loop.')
            assistant('I will trace ownership first, then check shutdown and restoration.' if last else 'Tracing the path from the event loop to the terminal writer. Reading the session and the loop.')
            disclosure('think', self.thinking, 'Thinking…', '', ['The renderer and event loop share a terminal, not layout state.', 'A halt must finish before the session is restored.', 'Checking whether a pending frame can cross that boundary.'], 'ctrl+t')
            disclosure('tool', self.tools, 'Read 2 files', 'ScreenSession.swift, RenderLoop.swift', ['ScreenSession.swift: terminal.leave() follows renderer.finish().', 'RenderLoop.swift: halt waits for the write in flight.'], 'ctrl+o')
            if last:
                agents()
                diff()
            assistant('Cancellation is safe on the normal path. A signal must stop the renderer before leaving the session; the test for that is the remaining gap.' if last else 'The two sides only share the connection. No change is needed here.')
        for text in self.sent:
            user(text)
            assistant('Simulated reply. Nothing was sent and nothing ran.')
        add('out', Line([span('Working…', 'faint')], italic=True))
        return out

    def build(self, tw):
        """The transcript as rows. One rule for every kind of block, in every layout: the same padding above and below.
        Every block is also separated from the one above it, with a pixel line
        (no row) or a block-line row. Never a margin, never a background."""
        pixel = self.sep == 0 and self.gfx
        rows = []
        for i, (kind, lines) in enumerate(self.blocks(tw)):
            edge = False
            if i > 0:
                if self.sep_rows():
                    rows.append(Line([], role='sep'))
                elif pixel:
                    edge = True
            for k in range(self.pad):
                rows.append(Line([], edge=(edge and k == 0), role='pad', block=i))
            for j, ln in enumerate(lines):
                ln.block = i
                ln.edge = edge and self.pad == 0 and j == 0
                rows.append(ln)
            for _ in range(self.pad):
                rows.append(Line([], role='pad', block=i))
        return rows

    def draw_line(self, ln, y, w, x0=0):
        if ln.role == 'sep':
            self.put(x0, y, '▁' * w, 'line')
            return
        if ln.edge and self.sep == 0 and self.gfx:
            self.px_hline(x0, y, w)
        x = x0 + INNER
        for text, fg, _, bold in ln.spans:
            self.put(x, y, text, fg, None, bold, italic=ln.italic)
            x += width(text)
        if ln.right:
            text, fg = ln.right
            self.put(x0 + w - INNER - width(text), y, text, fg, None, italic=ln.italic)

    # ---------- chrome ----------
    def chip(self, x, y, text, fg, bg, bold=False, raw=False):
        self.put(x, y, text, fg, bg, bold, raw=raw)
        return x + width(text)

    def draw_status(self, y):
        """Status as text: the mode, who a draft goes to, model, branch, work, and the context meter. Colour and weight carry
        it; nothing is painted and nothing leads with an icon."""
        self.xlim = self.w
        mode = ('BROWSE', 'warn') if self.browse else ('INPUT', 'accent')
        meter_cells, ratio = 12, 0.42
        fill8 = int(ratio * meter_cells * 8)
        bar = '█' * (fill8 // 8) + (BAR[fill8 % 8] if fill8 % 8 else '')
        bar = bar + ' ' * (meter_cells - width(bar))
        right = '  42%  114k/272k  $0.18'
        ctx_w = 4 + meter_cells + width(right)
        x = INNER
        self.put(x, y, mode[0], mode[1], None, True)
        x += width(mode[0])
        parts = ([(f'to {self.route()}', 'warn', True)] if self.route() else []) + [
            ('gpt-5.5 · high', 'fg', False), ('git:main +3', 'muted', False), ('2 working', 'good', False), ('1 approval', 'warn', True)]
        for text, fg, bold in parts:
            if x + 3 + width(text) + ctx_w > self.w:
                break
            x += 3
            self.put(x, y, text, fg, None, bold)
            x += width(text)
        if x + ctx_w <= self.w:
            cx = self.w - ctx_w
            self.put(cx, y, 'ctx ', 'faint')
            self.put(cx + 4, y, bar, 'accent')
            self.put(cx + 4 + meter_cells, y, right, 'fg')

    def draw_input(self, in_y):
        """The input is a block like the others: padding, text inset by INNER, and no leading bar or prompt glyph."""
        self.xlim = self.w
        focus = not self.browse
        flush = self.bottom == 2
        for r in range(in_y, in_y + self.in_rows):
            self.fill(0, r, self.w, 'input')
        chip_y = in_y + math.ceil(self.pad)           # padding rows above and below, inside the input's own block
        text_y = chip_y if flush else chip_y + 1
        x = INNER
        if not self.chips and not flush:
            self.put(x, chip_y, '@ file or agent   / command or skill', 'faint', 'input')
        for kind, label in self.chips:
            sym = '/' if kind == 'skill' else '@'
            if kind == 'session':                      # an address: it must not look like a file
                x = self.chip(x, chip_y, f' {sym} {label} ', 'warn', 'warnbg', True) + 1
            else:
                x = self.chip(x, chip_y, f' {sym} {label} ', 'accent', 'raised') + 1
        if not flush:
            hint = (f'Enter sends to {self.route()} · Esc browse' if self.route() else 'Enter send · Esc browse') if focus else 'Esc/Enter back to input · q quit'
            if self.w - width(hint) - INNER > x:
                self.put(self.w - width(hint) - INNER, chip_y, hint, 'faint', 'input')
            x = INNER
        avail = max(4, self.w - x - INNER)
        start = max(0, self.cursor - avail + 1)
        self.put(x, text_y, self.draft[start:start + avail], 'fg' if focus else 'faint', 'input')
        if flush and not self.draft and not self.chips:
            self.put(x, text_y, '@ file   / command or skill', 'faint', 'input')
        cx = x + width(self.draft[start:self.cursor])
        char = self.draft[self.cursor] if self.cursor < len(self.draft) else ' '
        if focus:
            self.put(cx, text_y, char, 'fg', 'input', rev=True)

    def route(self):
        """The session a draft is addressed to with @, or None when it goes to this session."""
        for kind, label in self.chips:
            if kind == 'session':
                return label.split(':', 1)[-1]
        return None

    def setting_index(self, attr, options):
        v = getattr(self, attr)
        if attr == 'pad':
            return PADS.index(v) if v in PADS else 1
        if attr == 'thick':
            return v - 1
        if isinstance(v, str):
            return options.index(v)
        return int(v)

    def set_setting(self, attr, i, options):
        i %= len(options)
        if attr == 'thick':
            self.thick = i + 1
        elif attr == 'pad':
            self.pad = PADS[i]
        elif attr in ('accent', 'stroke', 'layout'):
            setattr(self, attr, options[i])
        else:
            setattr(self, attr, i)
        if attr in ('accent', 'stroke'):
            self.retheme()

    def snapshot(self):
        return {k: getattr(self, k) for k in SAVED}

    def restore(self, data):
        """Load saved settings, ignoring anything this version does not have (older files had themes, surfaces, presets)."""
        for k in SAVED:
            if k in data:
                setattr(self, k, data[k])
        self.accent = self.accent if self.accent in ACCENTS else 'blue'
        self.sep = 0 if self.sep == 0 else 1             # older files had four separator styles; anything but pixel is a block line
        self.bottom = int(self.bottom) % 3
        self.pad = 1 if self.pad not in PADS else self.pad
        self.stroke = self.stroke if self.stroke in STROKES else 'subtle'
        legacy = data.get('variant')             # older files: 1 flat, 2 surfaces, 3 workbench. Flat and surfaces are one layout now.
        if 'layout' not in data and legacy in (1, 2, 3):
            self.layout = 'workbench' if legacy == 3 else 'standard'
        self.layout = self.layout if self.layout in LAYOUTS else 'standard'
        self.thick = 2 if int(self.thick) == 2 else 1
        self.retheme()

    def popup_extent(self, bottom):
        """(top row, height) of the open popup when it ends just above row `bottom`."""
        n = len(SETTING_ROWS) if self.modal == 'settings' else max(4, len(self.matches()[:7]))
        h = self.sep_rows() + 1 + n
        return max(2, bottom - h), h

    def draw_settings(self, bottom):
        self.xlim = self.w
        sr = self.sep_rows()
        n = len(SETTING_ROWS)
        top, h = self.popup_extent(bottom)
        body = top + sr
        for r in range(top, bottom):
            self.fill(0, r, self.w, 'panel')
        self.rule(top, 0, self.w)
        x = self.chip(0, body, ' SETTINGS ', 'accentfg', 'accent', True)
        self.put(x + 1, body, 'live preview · saved automatically', 'muted', 'panel')
        hint = '↑↓ choose · ←→ change · Esc close'
        self.put(self.w - width(hint) - 1, body, hint, 'faint', 'panel')
        split = max(38, self.w * 11 // 20)
        self.selected = min(self.selected, n - 1)
        for i, (label, attr, options, note) in enumerate(SETTING_ROWS):
            y = body + 1 + i
            if y >= bottom:
                break
            bg = 'raised' if i == self.selected else 'panel'
            self.fill(0, y, split, bg)
            self.put(INNER, y, label, 'accent' if i == self.selected else 'fg', bg, i == self.selected)
            value = options[self.setting_index(attr, options)]
            self.put(28, y, fit(value, split - 32), 'accent' if i == self.selected else 'muted', bg, i == self.selected)
        self.vrule(split, body + 1, bottom - body - 1, 'panel')
        label, attr, options, note = SETTING_ROWS[self.selected]
        px = split + 2
        for j, line in enumerate(wrap(note, self.w - px - 2)[:3]):
            self.put(px, body + 1 + j, line, 'fg' if j == 0 else 'muted', 'panel', j == 0)
        sw = body + 5
        if sw < bottom:                       # the colours as they are used: words, never fills
            x = px
            for text, fg, bold in (('accent', 'accent', True), ('good', 'good', False), ('warn', 'warn', True), ('bad', 'bad', False),
                                   ('fg', 'fg', False), ('muted', 'muted', False), ('faint', 'faint', False)):
                if x + width(text) < self.w - 1:
                    self.put(x, sw, text, fg, None, bold)
                    x += width(text) + 3
            if sw + 1 < bottom:
                self.rule(sw + 1, px, min(24, self.w - px - 2)) if self.pixel() else self.put(px, sw + 1, '▁' * min(24, self.w - px - 2), 'line')
        if sw + 3 < bottom:
            self.put(px, sw + 3, fit('colours: ' + self.theme_note, self.w - px - 2), 'muted')
        if sw + 4 < bottom and self.term:
            self.put(px, sw + 4, fit(f"terminal background {self.term['base']}  foreground {self.term['fg']}", self.w - px - 2), 'faint')

    def settings_key(self, k):
        n = len(SETTING_ROWS)
        label, attr, options, note = SETTING_ROWS[self.selected]
        if k in ('\x1b', '\r', '\n'):
            self.close_modal()
        elif k == '\x1b[A':
            self.selected = (self.selected - 1) % n
        elif k in ('\x1b[B', '\t'):
            self.selected = (self.selected + 1) % n
        elif k in ('\x1b[C', 'l', ' '):
            self.set_setting(attr, self.setting_index(attr, options) + 1, options)
        elif k in ('\x1b[D', 'h'):
            self.set_setting(attr, self.setting_index(attr, options) - 1, options)
        elif k == 'r':
            self.rescan = True
        return True

    def matches(self):
        q = self.query.lower().lstrip('/@$')
        hits = [r for r in DATA[self.modal] if q in ' '.join(r[:3]).lower()]
        return sorted(hits, key=lambda r: (not r[0].lower().lstrip('/@$').startswith(q), hits.index(r)))

    def draw_popup(self, bottom):
        if self.modal == 'settings':
            return self.draw_settings(bottom)
        self.xlim = self.w
        rows = self.matches()[:7]
        self.selected = min(self.selected, max(0, len(rows) - 1))
        sr = self.sep_rows()
        top, h = self.popup_extent(bottom)
        body = top + sr
        for r in range(top, bottom):
            self.fill(0, r, self.w, 'panel')
        self.rule(top, 0, self.w)
        names = {'commands': 'COMMANDS', 'refs': 'FILES · AGENTS · SESSIONS', 'agents': 'AGENTS', 'tasks': 'TASKS', 'permission': 'APPROVAL'}
        x = self.chip(0, body, f' {names[self.modal]} ', 'accentfg', 'accent', True)
        shown = self.query if self.trigger is None else self.query
        self.put(x + 1, body, 'filter: ' + shown, 'muted', 'panel')
        if not self.trigger:                                       # a typed filter has a cursor, like the input
            self.put(x + 1 + width('filter: ' + shown), body, ' ', 'fg', 'panel', rev=True)
        hint = {'commands': 'Enter insert · Esc close', 'refs': 'Enter attach · Esc close',
                'agents': 'Enter inspect · Esc close', 'tasks': 'Enter inspect · Esc close', 'permission': 'Enter choose · Esc deny'}[self.modal]
        self.put(self.w - width(hint) - 1, body, hint, 'faint', 'panel')
        split = max(30, self.w * 11 // 20)
        for i, (title, desc, kind, detail) in enumerate(rows):
            y = body + 1 + i
            bg = 'raised' if i == self.selected else 'panel'
            self.fill(0, y, split, bg)
            self.put(INNER, y, fit(title, 28), 'accent' if i == self.selected else 'fg', bg, i == self.selected)
            self.put(31, y, fit(desc, split - 41), 'muted', bg)
            self.put(split - 9, y, fit(kind, 8), 'accent' if kind not in ('BLOCKED',) else 'warn', bg, True)
        if not rows:
            self.put(2, body + 1, 'No matches', 'faint', 'panel')
        else:
            self.vrule(split, body + 1, bottom - body - 1, 'panel')
            title, desc, kind, detail = rows[self.selected]
            self.put(split + 2, body + 1, fit(desc, self.w - split - 3), 'fg', 'panel', True)
            for i, text in enumerate(detail.splitlines()[:max(0, bottom - body - 2)]):
                self.put(split + 2, body + 2 + i, fit(text, self.w - split - 3), 'muted', 'panel')

    # ---------- frame ----------
    def render(self, size=None, cell=None):
        self.w, self.h = size or shutil.get_terminal_size((120, 42))
        self.cw, self.ch = cell if cell else (0, 0)
        self.gfx = self.gfx_ok()
        self.out = ['\033[?25l'] + (['\033_Ga=d,d=a,q=2\033\\'] if self.gfx else [])
        self.grid = [[' '] * self.w for _ in range(self.h)]
        self.strokes, self.placed, self.phase, self.img_clip = [], [], 'page', None
        self.clip_y, self.xlim = self.h, self.w
        for r in range(self.h):
            self.fill(0, r, self.w, 'base')
        if self.w < 76 or self.h < 26:
            self.put(2, 1, 'UI lab needs at least 76 columns x 26 rows. q quits.', 'warn')
            return ''.join(self.out)
        sr = self.sep_rows()
        status_y = self.h - 1
        in_rows = 2 * self.pad + (1 if self.bottom == 2 else 2)       # the input is a block too: the same padding
        in_y = status_y - in_rows
        rule_y = in_y - sr
        self.in_y, self.in_rows = in_y, in_rows
        side = self.layout == 'workbench' and self.w >= 108
        ws_y = rule_y - 1 if (self.bottom == 0 and not side) else None
        self.bottom_y = ws_y if ws_y is not None else rule_y
        self.img_clip = None
        if self.modal:
            top_, _h = self.popup_extent(rule_y)
            self.img_clip = (top_, rule_y)
        vp_y0, vp_y1 = 2, (ws_y if ws_y is not None else rule_y)
        vp_right = self.w - (30 if side else 0)
        vp_h = vp_y1 - vp_y0

        # transcript viewport: the only region expansion may touch
        self.clip_y, self.xlim = vp_y1, vp_right - 1
        text_w = vp_right - 1
        lines = self.build(text_w)
        total = len(lines)
        self.scroll = max(0, min(self.scroll, max(0, total - vp_h)))
        start = max(0, total - vp_h - self.scroll)
        for i, ln in enumerate(lines[start:start + vp_h]):
            self.draw_line(ln, vp_y0 + i, text_w)
        self.xlim = vp_right
        # One stroke at the boundary. With a sidebar it is the divider *and* the scrollbar track: the thumb rides on it.
        if total > vp_h:
            self.draw_scrollbar(vp_right - 1, vp_y0, vp_h, total, start, edge=side)
        elif side:
            self.draw_divider(vp_right - 1, vp_y0, vp_h)
        if self.scroll > 0:
            pill = f'{self.scroll} lines below · End'
            self.put(vp_right - 1 - width(pill) - INNER, vp_y1 - 1, pill, 'accent', None, True)
        self.clip_y = self.h

        # header: text only
        self.xlim = self.w
        self.put(INNER, 1, 'ask', 'accent', None, True)
        self.put(INNER + 5, 1, 'render-loop', 'fg', None, True)
        self.put(INNER + 19, 1, 'git:main', 'muted')
        right = 'gpt-5.5 · high · edits ask first'
        self.put(self.w - width(right) - INNER, 1, right, 'muted')
        if self.pixel():
            self.px_hline(0, 2, self.w)

        # sidebar or work strip: words and colour, no icons, no fills
        if side:
            sx = vp_right
            self.xlim = self.w
            rows = [('TASKS', None, 'faint', True), ('Trace event path', 'done', 'good', False), ('Review cancellation', 'running', 'fg', True),
                    ('Verify restoration', 'approval', 'warn', True), ('Summarize findings', 'queued', 'faint', False), ('', None, 'fg', False),
                    ('AGENTS', None, 'faint', True), ('reviewer', 'running', 'fg', False), ('test-runner', 'approval', 'warn', True), ('', None, 'fg', False),
                    ('CONTEXT', None, 'faint', True), ('2 files · 1 skill', None, 'muted', False), ('42%  114k/272k', None, 'muted', False)]
            for i, (label, state, fg, bold) in enumerate(rows):
                if vp_y0 + i >= vp_y1:
                    break
                self.put(sx + INNER + 1, vp_y0 + i, fit(label, 19), fg if label.isupper() or not state else 'fg', None, bold if label.isupper() else False)
                if state:
                    self.put(sx + 30 - INNER - width(state), vp_y0 + i, state, fg, None, bold)
        elif ws_y is not None:
            self.xlim = self.w
            self.put(INNER, ws_y, 'WORK', 'accent', None, True)
            x = INNER + 4
            for text, fg, bold in (('1 done', 'good', False), ('1 running', 'fg', False), ('1 approval', 'warn', True)):
                x += 3
                self.put(x, ws_y, text, fg, None, bold)
                x += width(text)
            tail = 'reviewer   test-runner   Esc, then a / t / p'
            if self.w - width(tail) - INNER > x:
                self.put(self.w - width(tail) - INNER, ws_y, tail, 'muted')

        self.rule(rule_y, 0, self.w)
        self.draw_input(in_y)
        self.draw_status(status_y)
        if self.modal:
            self.img_clip, self.phase = None, 'popup'          # the popup's own strokes are drawn, nothing under it
            self.draw_popup(rule_y)
            self.phase = 'page'

        # the lab's own strip (not part of the product UI): reverse video, so it paints nothing either
        self.xlim = self.w
        names = ['1 Standard', '2 Workbench']
        shown = '  '.join(('[' + n + ']') if LAYOUTS[i] == self.layout else n for i, n in enumerate(names))
        sep = SEPS[self.sep] if self.sep or self.gfx else 'block line (this terminal has no pixel lines)'
        text = f' LAB  {shown} │ s settings   b separators  x thickness  v bottom   r rescan colours │ Esc: browse keys │ {sep} '
        self.put(0, 0, ' ' * self.w, 'fg', None, True, rev=True)
        self.put(0, 0, fit(text, self.w), 'fg', None, True, rev=True)
        return ''.join(self.out)

    def draw_divider(self, x, y, rows):
        """The boundary stroke when there is nothing to scroll: the same line the scrollbar track would be."""
        self.strokes.append(('d', x))
        if self.sep == 0 and self.gfx:
            t, hpx = self.thick, rows * self.ch
            raw = (b'\0' + self.rgba('line') * t) * hpx
            self.place(self.image(('e', hpx, t, self.col('line')), t, hpx, raw), x, y, self.cw - t, 0, rows)
        else:
            for r in range(y, y + rows):
                self.put(x, r, '▕', 'line')

    def draw_scrollbar(self, x, y, rows, total, start, edge=False):
        self.strokes.append(('s', x))
        if self.sep == 0 and self.gfx:
            hpx = rows * self.ch
            size = max(8, int(hpx * rows / total))
            top = int((hpx - size) * (start / max(1, total - rows)))
            self.px_scrollbar(x, y, rows, top, size, edge)
            return
        half = 2 * rows
        size = max(1, round(half * rows / total))
        top = round((half - size) * (start / max(1, total - rows)))
        for r in range(rows):
            lo, hi = 2 * r, 2 * r + 2
            cover = max(0, min(hi, top + size) - max(lo, top))
            glyph = '▐' if cover == 2 else ('▗' if cover == 1 and top > lo else '▝' if cover == 1 else '▕')
            self.put(x, y + r, glyph, 'accent' if cover else 'line', 'base')

    # ---------- input ----------
    def open_modal(self, name, trigger=None):
        self.modal, self.trigger, self.query, self.selected = name, trigger, '', 0

    def close_modal(self):
        self.modal = self.trigger = None
        self.query = ''

    def accept(self):
        rows = self.matches()
        if not rows:
            return
        title, desc, kind, detail = rows[self.selected]
        if self.modal == 'commands' and title == '/theme' and self.trigger is not None:
            self.draft = self.draft[:self.trigger] + self.draft[self.cursor:]
            self.cursor = self.trigger
            self.after = 'settings'
            return
        if self.trigger is not None:
            insert = (title if self.modal == 'commands' else '@' + (title if kind != 'FILE' else title.split(':')[0])) + ' '
            self.draft = self.draft[:self.trigger] + insert + self.draft[self.cursor:]
            self.cursor = self.trigger + len(insert)
            if self.modal == 'refs':
                self.chips.append(({'AGENT': 'agent', 'SESSION': 'session'}.get(kind, 'file'), title))
            elif kind == 'SKILL':
                self.chips.append(('skill', title.lstrip('/')))
            self.toast = 'Inserted; nothing was sent or executed.'
        else:
            self.toast = f'{title}: simulated; no context change.'

    def key(self, k):
        if k == '\x03':
            return False
        if k.startswith('\x1b[?997;'):
            self.rescan = True
            return True
        if k.startswith('\x1b[<'):
            try:
                button = int(k[3:-1].split(';')[0])
            except ValueError:
                return True
            if button == 64:
                self.scroll += 3
            elif button == 65:
                self.scroll = max(0, self.scroll - 3)
            return True
        if k in ('\x1b[5~', '\x1b[6~'):
            self.scroll = max(0, self.scroll + (self.page if k.endswith('5~') else -self.page))
            return True
        if self.modal:
            return self.modal_key(k)
        if self.browse:
            return self.browse_key(k)
        return self.input_key(k)

    def modal_key(self, k):
        if self.modal == 'settings':
            return self.settings_key(k)
        if k == '\x1b':
            if self.modal == 'permission' and self.trigger is None:
                self.toast = 'Simulated: denied.'
            self.close_modal()
        elif k in ('\x1b[A', '\x1b[B'):
            self.selected = (self.selected + (1 if k.endswith('B') else -1)) % max(1, len(self.matches()))
        elif k in ('\r', '\n', '\t'):
            self.accept()
            self.close_modal()
            if self.after:
                self.after, name = None, self.after
                self.open_modal(name)
        elif k in ('\x7f', '\b'):
            if self.trigger is not None:
                if self.cursor > 0:
                    self.draft = self.draft[:self.cursor - 1] + self.draft[self.cursor:]
                    self.cursor -= 1
                if self.cursor <= self.trigger:
                    self.close_modal()
                else:
                    self.query = self.draft[self.trigger:self.cursor]
            else:
                self.query = self.query[:-1]
            self.selected = 0
        elif len(k) == 1 and k.isprintable():
            if self.trigger is not None:
                self.draft = self.draft[:self.cursor] + k + self.draft[self.cursor:]
                self.cursor += 1
                if k == ' ':
                    self.close_modal()
                else:
                    self.query = self.draft[self.trigger:self.cursor]
            else:
                self.query += k
            self.selected = 0
        return True

    def browse_key(self, k):
        if k in ('q',):
            return False
        if k in ('\x1b', '\r', '\n'):
            self.browse = False
        elif k in ('1', '2'):
            self.layout = LAYOUTS[int(k) - 1]
        elif k == 'b':
            self.sep = 1 - self.sep
        elif k == 'x':
            self.thick = 3 - self.thick
        elif k == 'v':
            self.bottom = (self.bottom + 1) % 3
        elif k == 'r':
            self.rescan = True
        elif k == 's':
            self.open_modal('settings')
        elif k == 'i':
            self.thinking = not self.thinking
        elif k == 'o':
            self.tools = not self.tools
        elif k in ('k', '\x1b[A'):
            self.scroll += 1
        elif k in ('j', '\x1b[B'):
            self.scroll = max(0, self.scroll - 1)
        elif k in ('G', '\x1b[F'):
            self.scroll = 0
        elif k == 'g':
            self.scroll = 10 ** 6
        elif k in BROWSE_MODALS:
            self.open_modal(BROWSE_MODALS[k])
        return True

    def input_key(self, k):
        if k == '\x1b':
            self.browse = True
        elif k == '\x14':
            self.thinking = not self.thinking
        elif k == '\x0f':
            self.tools = not self.tools
        elif k == '\x15':
            self.draft, self.cursor = '', 0
        elif k in ('\r', '\n'):
            if self.draft.strip():
                target = self.route()
                self.sent.append(self.draft.strip() if not target else f'[to {target}] ' + self.draft.strip())
                self.draft, self.cursor, self.chips, self.scroll = '', 0, [], 0
                self.toast = 'Simulated send. Nothing ran.'
        elif k in ('\x7f', '\b'):
            if self.cursor:
                self.draft = self.draft[:self.cursor - 1] + self.draft[self.cursor:]
                self.cursor -= 1
        elif k == '\x1b[3~':
            self.draft = self.draft[:self.cursor] + self.draft[self.cursor + 1:]
        elif k == '\x1b[D':
            self.cursor = max(0, self.cursor - 1)
        elif k == '\x1b[C':
            self.cursor = min(len(self.draft), self.cursor + 1)
        elif k in ('\x1b[H', '\x01'):
            self.cursor = 0
        elif k in ('\x1b[F', '\x05'):
            self.cursor = len(self.draft)
        elif len(k) == 1 and k.isprintable():
            at_token_start = self.cursor == 0 or self.draft[self.cursor - 1] == ' '
            self.draft = self.draft[:self.cursor] + k + self.draft[self.cursor:]
            self.cursor += 1
            if k in TRIGGERS and at_token_start:
                self.open_modal(TRIGGERS[k], self.cursor - 1)
                self.query = k
        return True


def _component(text):
    """One OSC colour component: 1-4 hex digits scaled to 0-255."""
    return round(int(text, 16) / (16 ** len(text) - 1) * 255)


def parse_colors(buf):
    """Read the terminal's answers to OSC 10, 11 and 4. Returns {'base','fg','ansi'} or None without both."""
    comp = rb'rgb:([0-9a-fA-F]{1,4})/([0-9a-fA-F]{1,4})/([0-9a-fA-F]{1,4})'

    def color(m):
        return rgb_hex([_component(m.group(i).decode()) for i in (2, 3, 4)])
    out = {'ansi': {}}
    for m in re.finditer(rb'\x1b\]((?:10|11));' + comp, buf):
        out['fg' if m.group(1) == b'10' else 'base'] = color(m)
    for m in re.finditer(rb'\x1b\]4;(\d+);' + comp, buf):
        out['ansi'][int(m.group(1))] = color(m)
    return out if 'base' in out and 'fg' in out else None


def detect_colors(fd, timeout=0.6):
    """Ask the terminal for its own colours. Terminals answer in order; a DA1 reply marks the end."""
    query = '\033]10;?\033\\\033]11;?\033\\' + ''.join(f'\033]4;{i};?\033\\' for i in (1, 2, 3, 4, 5, 6, 8)) + '\033[c'
    os.write(1, query.encode())
    buf, deadline = b'', time.monotonic() + timeout
    while time.monotonic() < deadline:
        if select.select([fd], [], [], max(0, deadline - time.monotonic()))[0]:
            buf += os.read(fd, 4096)
            if re.search(rb'\x1b\[\?[0-9;]*c', buf):
                break
    return parse_colors(buf)


def cell_size():
    try:
        rows, cols, xp, yp = struct.unpack('HHHH', fcntl.ioctl(1, termios.TIOCGWINSZ, b'\0' * 8))
        return (xp // cols if cols and xp else 0, yp // rows if rows and yp else 0)
    except OSError:
        return (0, 0)


def getkey(fd):
    first = os.read(fd, 1)
    if first != b'\x1b':
        while True:
            try:
                return first.decode('utf-8')
            except UnicodeDecodeError:
                first += os.read(fd, 1)
    if not select.select([fd], [], [], 0.045)[0]:
        return '\x1b'
    rest = os.read(fd, 1).decode('utf-8', 'replace')
    if rest == '[':
        while select.select([fd], [], [], 0.02)[0]:
            c = os.read(fd, 1).decode('utf-8', 'replace')
            rest += c
            if c.isalpha() or c == '~':
                break
    return '\x1b' + rest


TERMS = {
    'solarized-dark': dict(base='#002b36', fg='#839496', ansi={1: '#dc322f', 2: '#859900', 3: '#b58900', 4: '#268bd2', 5: '#d33682', 6: '#2aa198', 8: '#586e75'}),
    'solarized-light': dict(base='#fdf6e3', fg='#657b83', ansi={1: '#dc322f', 2: '#859900', 3: '#b58900', 4: '#268bd2', 5: '#d33682', 6: '#2aa198', 8: '#93a1a1'}),
    'dracula': dict(base='#282a36', fg='#f8f8f2', ansi={1: '#ff5555', 2: '#50fa7b', 3: '#f1fa8c', 4: '#bd93f9', 5: '#ff79c6', 6: '#8be9fd', 8: '#6272a4'}),
    'kitty-default': dict(base='#000000', fg='#dddddd', ansi={1: '#cc0000', 4: '#0d73cc'}),
}


def check():
    n_pal = count = 0
    assert PADS == [0, 1], 'block padding goes up to one block and no further'
    assert len(dict((r[1], r) for r in SETTING_ROWS)['pad'][2]) == len(PADS)
    # 1. Text colours are readable on the terminal's own background, on real terminal palettes (including Solarized, whose own
    #    foreground is low-contrast), for every accent; strokes keep their level and stay quieter than text.
    for name, t in dict(TERMS, **{n: PRESETS[n] for n in PRESETS}).items():
        for accent in ACCENTS:
            levels = []
            for level, (_, least) in STROKES.items():
                pal = derive(t['base'], t['fg'], t['ansi'], accent, level)
                assert contrast(pal['fg'], pal['base']) >= 7.0 and contrast(pal['muted'], pal['base']) >= 5.0, (name, accent)
                for key in ('faint', 'accent', 'good', 'warn', 'bad'):
                    assert contrast(pal[key], pal['base']) >= 4.5, (key, name, accent, level)
                assert contrast(pal['line'], pal['base']) >= least - 0.01, (level, name, accent)
                assert contrast(pal['line'], pal['base']) < contrast(pal['fg'], pal['base'])     # a stroke is never as loud as text
                levels.append(contrast(pal['line'], pal['base']))
                n_pal += 1
            assert levels[0] < levels[1] < levels[2], ('subtle < normal < strong', levels, name, accent)
    # 2. NOTHING IS EVER PAINTED. No background escape code is emitted, in any layout, separator, padding, bottom section or
    #    popup, with the terminal's colours or without (plain ANSI colours, no truecolour at all).
    app = Lab()
    app.term = TERMS['solarized-dark']
    app.retheme()
    fallback = Lab()
    for layout in LAYOUTS:
        for sep in (0, 1):
            for pad in PADS:
                for bottom in range(3):
                    for gfx in (False, True):
                        for modal in (None, 'refs', 'commands', 'settings', 'agents', 'permission'):
                            for shape in ((80, 30), (110, 34), (140, 45))[:2 if modal else 3]:
                                for who in (app, fallback):
                                    who.layout, who.sep, who.pad, who.bottom = layout, sep, pad, bottom
                                    who.force_gfx, who.modal, who.trigger = gfx, modal, None
                                    out = who.render(shape, (16, 30) if gfx else None)
                                    assert '\x1b[48' not in out, ('a background was painted', layout, sep, pad, bottom, modal)
                                    assert who is app or '38;2;' not in out, 'ANSI fallback must not use truecolour'
                                    count += 1
    assert app.pal['accent'].startswith('#') and fallback.pal['accent'].startswith('ansi:')
    assert not hasattr(Line([]), 'bg'), 'a Line has no background to paint'
    # 3. One block model in every layout: the same padding above and below every kind of block (yours, output, thinking, tool
    #    calls), and a separator between a block and the one above it, as a pixel line (no row) or a block-line row.
    shapes = {}
    for layout in LAYOUTS:
        for pad in PADS:
            for gfx in (False, True):
                app = Lab(layout)
                app.pad, app.force_gfx, app.gfx = pad, gfx, gfx
                blocks = app.blocks(100)
                assert {kind for kind, _ in blocks} == set(KINDS)
                rows = app.build(100)
                by_block = {}
                for ln in rows:
                    by_block.setdefault(ln.block, []).append(ln)
                for i, (kind, _) in enumerate(blocks):
                    r = by_block[i]
                    lead = next(j for j, ln in enumerate(r) if ln.role == 'content')
                    trail = next(j for j, ln in enumerate(reversed(r)) if ln.role == 'content')
                    assert lead == pad and trail == pad, (layout, kind, pad, lead, trail)
                pads = sum(ln.role == 'pad' for ln in rows)
                seps = sum(ln.role == 'sep' for ln in rows)
                edges = sum(ln.edge for ln in rows)
                shapes[(layout, pad, gfx)] = (pads, sum(ln.role == 'content' for ln in rows), seps, edges)
                if gfx:
                    assert seps == 0 and edges == len(blocks) - 1, 'a pixel line separates blocks and costs no row'
                else:
                    assert seps == len(blocks) - 1 and edges == 0, 'a block-line row separates blocks'
    for pad in PADS:                                           # the sidebar changes the width, never the spacing
        for gfx in (False, True):
            assert shapes[('standard', pad, gfx)] == shapes[('workbench', pad, gfx)], (pad, gfx)
    assert LAYOUTS == ['standard', 'workbench'], 'flat and surfaces are one layout'
    # The input is a block too: the same padding, in every bottom section.
    for pad in PADS:
        for bottom in range(3):
            app = Lab()
            app.pad, app.bottom = pad, bottom
            app.render((120, 42))
            assert app.in_rows == 2 * pad + (1 if bottom == 2 else 2), (pad, bottom, app.in_rows)
            for r in list(range(app.in_y, app.in_y + pad)) + list(range(app.in_y + app.in_rows - pad, app.in_y + app.in_rows)):
                assert ''.join(app.grid[r]).strip() == '', (pad, bottom, r)       # padding rows are empty
            assert any('Review cancellation' in ''.join(app.grid[r]) for r in range(app.in_y + pad, app.in_y + app.in_rows - pad))
    # No leading bar and no leading icon anywhere: the transcript, the input, the pickers, the status bar, the sidebar.
    for layout in LAYOUTS:
        for pad in PADS:
            for sep in (0, 1):
                for bottom in range(3):
                    for modal in (None, 'refs', 'settings', 'agents'):
                        app = Lab(layout)
                        app.pad, app.sep, app.bottom = pad, sep, bottom
                        app.thinking = app.tools = bool(bottom % 2)
                        app.force_gfx, app.modal, app.trigger = sep == 0, modal, None
                        app.render((120, 42), (16, 30) if sep == 0 else None)
                        icons = set('▸▾◆›↪⠹●▲✓○')
                        assert not (icons & set(''.join(''.join(r) for r in app.grid[1:]))), (layout, pad, sep, bottom, modal)
                        assert not (set('▌▏') & set(''.join(''.join(r) for r in app.grid[1:-1]))), (layout, pad, sep, bottom, modal)
    # 4. Expanding thinking or tools never changes the input, status or work rows, in every bottom section.
    for bottom in range(3):
        for sep in (0, 1):
            for layout in LAYOUTS:
                app = Lab(layout)
                app.sep, app.bottom, app.force_gfx = sep, bottom, sep == 0
                app.draft, app.cursor = 'half typed @re', 8
                cell = (16, 30) if sep == 0 else None
                app.render((120, 42), cell)
                before = [''.join(r) for r in app.grid[app.bottom_y:]]
                app.key('\x14')
                app.key('\x0f')
                app.render((120, 42), cell)
                assert before == [''.join(r) for r in app.grid[app.bottom_y:]], (bottom, sep, layout)
                assert app.draft == 'half typed @re' and app.cursor == 8
    heights = []
    for bottom in range(3):
        app = Lab()
        app.bottom, app.force_gfx = bottom, True
        app.render((120, 42), (16, 30))
        heights.append(42 - app.bottom_y)
    assert heights[0] > heights[1] > heights[2], heights                 # roomy > tight > flush
    # Reading earlier output: expanding must not move the viewport offset.
    app = Lab()
    app.render((100, 28))
    assert len(app.build(99)) - (28 - 2 - 2 - 3 - 1) >= 7
    app.scroll = 7
    app.key('\x14')
    app.render((100, 28))
    assert app.scroll == 7
    # 5. Workbench draws ONE stroke between the transcript and the sidebar: the divider is the scrollbar track.
    for sep in (0, 1):
        for overflow in (True, False):
            app = Lab('workbench')
            app.sep, app.force_gfx = sep, sep == 0
            if not overflow:
                full = app.build
                app.build = lambda tw, full=full: full(tw)[:10]
            out = app.render((140, 45), (16, 30) if sep == 0 else None)
            boundary = 140 - 30 - 1
            assert len(app.strokes) == 1 and app.strokes[0][1] == boundary, (sep, overflow, app.strokes)
            assert app.strokes[0][0] == ('s' if overflow else 'd')
            for y in range(3, 40):
                assert app.grid[y][boundary + 1] != '│' and app.grid[y][boundary - 1] != '│', (sep, y)
            if sep == 0:
                assert ('X=14,Y=0\x1b' in out) if overflow else ('X=15,Y=0\x1b' in out), 'the track sits on the cell edge'
            else:
                assert all(app.grid[y][boundary] in '▕▐▗▝' for y in range(3, 38)), (sep, overflow)
    app = Lab()
    app.force_gfx = True
    app.render((140, 45), (16, 30))
    assert app.strokes == [('s', 139)]
    # 6. Nothing under a popup shows through it. Strokes are images above the text layer, so a line behind an open popup would
    #    be drawn across it (the settings panel showed exactly that).
    for modal in ('settings', 'refs', 'commands', 'agents', 'tasks', 'permission'):
        for layout in LAYOUTS:
            for pad in PADS:
                for bottom in range(3):
                    app = Lab(layout)
                    app.pad, app.bottom, app.force_gfx, app.modal, app.trigger = pad, bottom, True, modal, None
                    app.render((120, 42), (16, 30))
                    bottom_row = app.in_y - app.sep_rows()
                    top, _ = app.popup_extent(bottom_row)
                    page = [(y, v) for y, v, phase in app.placed if phase == 'page']
                    assert page, 'there are strokes to test against'
                    assert all(y + v <= top or y >= bottom_row for y, v in page), (modal, layout, pad, bottom, top, page)
                    assert any(phase == 'popup' for _, _, phase in app.placed), 'the popup draws its own strokes'
    # 7. The defaults are the owner's settled setup.
    app = Lab()
    assert (app.sep, app.thick, app.stroke, app.pad, app.bottom, app.layout) == (0, 1, 'subtle', 1, 0, 'standard')
    # 5. '/' is for commands and skills, '@' for files, agents and sessions; '$' is not a trigger.
    app = Lab()
    app.draft, app.cursor, app.chips = '', 0, []
    app.key('$')
    assert app.modal is None
    app.draft, app.cursor = '', 0
    app.key('/')
    assert app.modal == 'commands'
    for c in 'code':
        app.key(c)
    assert app.matches()[0][0] == '/code-review'
    app.key('\r')
    assert app.draft == '/code-review ' and ('skill', 'code-review') in app.chips
    app.draft, app.cursor, app.chips = '', 0, []
    app.key('@')
    assert app.modal == 'refs'
    for c in 'session:ren':
        app.key(c)
    assert app.matches()[0][0] == 'session:render-review'
    app.key('\r')
    assert app.route() == 'render-review' and app.draft == '@session:render-review '
    app.render((120, 42))
    assert ' to render-review ' in ''.join(app.grid[-1]), 'the route shows in the status bar, in words'
    app.draft, app.cursor = app.draft + 'please look at cancellation', len(app.draft) + 27
    app.key('\r')
    assert app.sent[-1].startswith('[to render-review]') and app.route() is None
    app = Lab()
    app.draft, app.cursor = '', 0
    app.key('@')
    for c in 'revi':
        app.key(c)
    assert app.matches()[0][0] == 'reviewer'
    app.key('\x1b')
    assert app.modal is None and app.draft == '@revi'
    app.key(' ')
    app.key('/')
    assert app.modal == 'commands'
    app.key('\x1b')
    app.key('x')
    app.key('/')
    assert app.modal is None  # a '/' inside a word (a path) is not a trigger
    # 6. Wheel scrolls and leaves the draft; a terminal colour-scheme notification asks for a rescan.
    app = Lab()
    app.draft, app.cursor = 'keep me', 3
    for k in ('\x1b[<64;10;10M', '\x1b[<64;10;10M', '\x1b[<65;10;10M'):
        app.key(k)
    assert app.scroll == 3 and app.draft == 'keep me' and app.cursor == 3
    assert not app.rescan
    app.key('\x1b[?997;1n')
    assert app.rescan
    # 8. Settings: the panel opens, changes apply live, the snapshot round-trips, older files load.
    def row(attr):
        return [r[1] for r in SETTING_ROWS].index(attr)

    def change(app, attr, delta):
        app.selected = row(attr)
        app.key('\x1b[C' if delta > 0 else '\x1b[D')

    app = Lab()
    app.browse = True
    app.key('s')
    assert app.modal == 'settings'
    assert [r[1] for r in SETTING_ROWS] == ['accent', 'sep', 'thick', 'stroke', 'pad', 'bottom', 'layout']
    change(app, 'accent', +1)
    assert app.accent == 'cyan' and app.pal['accent'] != app.pal['fg']
    change(app, 'sep', +1)
    assert app.sep == 1
    change(app, 'pad', -1)
    assert app.pad == 0
    change(app, 'pad', +1)
    assert app.pad == 1
    change(app, 'pad', +1)
    assert app.pad == 0, 'padding goes up to one block and wraps'
    assert PADS == [0, 1]
    change(app, 'stroke', +1)
    assert app.stroke == 'normal'
    snap = app.snapshot()
    other = Lab()
    other.restore(snap)
    assert other.snapshot() == snap and other.pal == app.pal
    other.restore({'accent': 'bogus', 'sep': 3, 'bottom': -5, 'layout': 'bogus', 'pad': 9, 'stroke': 'x', 'theme': 'dark', 'surface': 3,
                   'paint': 1, 'density': 'aerial', 'status_mode': 1, 'margin': 4})
    assert other.accent == 'blue' and other.sep == 1 and other.pad in PADS and other.layout == 'standard' and 0 <= other.bottom <= 2
    assert not hasattr(other, 'surface') and not hasattr(other, 'theme') and not hasattr(other, 'density')
    # older files had three layouts: flat and surfaces became standard, workbench stayed workbench
    for legacy, expected in ((1, 'standard'), (2, 'standard'), (3, 'workbench'), (9, 'standard')):
        old = Lab()
        old.restore({'variant': legacy})
        assert old.layout == expected, (legacy, old.layout)
    new = Lab()
    new.restore({'layout': 'workbench', 'variant': 1})
    assert new.layout == 'workbench', 'a current file wins over the legacy key'
    app.key('\x1b')
    assert app.modal is None
    app = Lab()
    app.draft, app.cursor = 'abc ', 4
    app.key('/')
    for c in 'theme':
        app.key(c)
    app.key('\r')
    assert app.modal == 'settings' and app.draft == 'abc '
    # 8. Permission defaults to the safe choice.
    app = Lab()
    app.browse = True
    app.key('p')
    assert app.matches()[0][0] == 'Deny'
    # 9. OSC reply parsing.
    assert parse_colors(b'\x1b]10;rgb:dddd/dddd/dddd\x1b\\\x1b]11;rgb:0000/0000/0000\x1b\\\x1b]4;1;rgb:cc/00/00\x1b\\') == {'ansi': {1: '#cc0000'}, 'fg': '#dddddd', 'base': '#000000'}
    assert parse_colors(b'\x1b[?62;c') is None
    print(f'PASS: {n_pal} palettes meet contrast, {count} renders and none paints a background, one block model in every layout, '
          'no leading icon or bar, one stroke at the sidebar, nothing under a popup, commands/skills under /, files/agents/sessions '
          'under @, routing, settings, rescan.')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    if args.check:
        check()
        return
    app = Lab()
    path = os.environ.get('LAB_SETTINGS', '/tmp/ask-ui-lab/settings.json')
    try:
        with open(path) as f:
            app.restore(json.load(f))
    except (OSError, ValueError):
        pass
    saved = app.snapshot()
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        app.term = detect_colors(fd)
        app.retheme()
        # alternate screen, mouse reporting, and "tell me when the terminal colour scheme changes"
        sys.stdout.write('\033[?1049h\033[?1000h\033[?1006h\033[?2031h')
        sys.stdout.flush()
        running, redraw, last = True, True, None
        while running:
            if app.rescan:
                app.rescan = False
                app.term = detect_colors(fd) or app.term
                app.retheme()
                redraw = True
            size = shutil.get_terminal_size((120, 42))
            cell = cell_size()
            if redraw or (size, cell) != last:
                app.page = max(3, size[1] - 12)
                sys.stdout.write('\033[?2026h' + app.render(size, cell) + '\033[?2026l')
                sys.stdout.flush()
                redraw, last = False, (size, cell)
            if select.select([fd], [], [], 0.2)[0]:
                key = getkey(fd)
                if os.environ.get('LAB_KEYLOG'):
                    with open(os.environ['LAB_KEYLOG'], 'a') as log:
                        log.write(repr(key) + '\n')
                running = app.key(key)
                redraw = True
                if app.snapshot() != saved:
                    saved = app.snapshot()
                    try:
                        with open(path, 'w') as f:
                            json.dump(saved, f)
                    except OSError:
                        pass
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
        sys.stdout.write('\033[?2031l\033[?1006l\033[?1000l\033_Ga=d,d=A,q=2\033\\\033]111\033\\\033[0m\033[?25h\033[?1049l')
        sys.stdout.flush()


if __name__ == '__main__':
    main()
