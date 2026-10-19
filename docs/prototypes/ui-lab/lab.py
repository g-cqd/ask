#!/usr/bin/env python3
"""Disposable UI prototype for ask. Everything shown is fixture data.

No network, no subprocesses, no tool execution, nothing outside this file is touched.
Pixel lines use the kitty graphics protocol when available and fall back to glyphs.
"""
import argparse, base64, fcntl, json, os, re, select, shutil, struct, sys, termios, time, tty, unicodedata, zlib

PRESETS = {
    'light': dict(base='#ffffff', fg='#111111',
                  ansi={1: '#b3261e', 2: '#1b6636', 3: '#8a5a00', 4: '#154b85', 5: '#8a2f8f', 6: '#0b6b73', 8: '#6c7787'}),
    'dark': dict(base='#0e1217', fg='#f0f3f8',
                 ansi={1: '#ff9d9d', 2: '#8ee0ae', 3: '#f2c777', 4: '#8fc0ff', 5: '#e0a8ff', 6: '#7fe0e8', 8: '#66748a'}),
}
THEME_SOURCES = ['terminal', 'light', 'dark']
ACCENTS = {'blue': 4, 'cyan': 6, 'magenta': 5, 'green': 2, 'yellow': 3}
SURFACES = ['off', 'subtle', 'normal', 'strong']
SURFACE_K = [0.0, 0.6, 1.0, 1.6]
BOTTOMS = ['roomy', 'tight', 'flush']


def hex_rgb(h):
    h = h.lstrip('#')
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def rgb_hex(c):
    return '#%02x%02x%02x' % tuple(max(0, min(255, round(v))) for v in c)


def blend(a, b, t):
    ca, cb = hex_rgb(a), hex_rgb(b)
    return rgb_hex([ca[i] * (1 - t) + cb[i] * t for i in range(3)])


def nudge(h):
    """One unit lighter (or darker on a light colour). Kitty and others treat an explicit background equal to the
    default as the default, so it stays translucent; one unit apart it is painted. Invisible to the eye."""
    c = hex_rgb(h)
    step = 1 if sum(c) < 384 else -1
    return rgb_hex([v + step for v in c])


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


def derive(base, fg, ansi, accent='blue', surface=2):
    """Every colour the UI uses, derived from the terminal's own base, foreground and ANSI palette."""
    fallback = PRESETS['dark' if luminance(base) < 0.4 else 'light']['ansi']
    pick = lambda i: ansi.get(i) or fallback[i]
    k = SURFACE_K[surface]
    acc = ensure(pick(ACCENTS[accent]), base, 4.5, fg)
    good, warn, bad = (ensure(pick(i), base, 4.5, fg) for i in (2, 3, 1))
    return dict(
        base=base, fg=ensure(fg, base, 7.0, fg),
        panel=blend(base, fg, 0.045 * k), input=blend(base, fg, 0.065 * k), bar=blend(base, fg, 0.10 * k),
        raised=blend(base, acc, 0.20),
        muted=ensure(blend(fg, base, 0.22), base, 5.0, fg), faint=ensure(blend(fg, base, 0.40), base, 4.5, fg),
        line=ensure(blend(fg, base, 0.45), base, 2.6, fg),
        accent=acc, accentfg=base,
        good=good, warn=warn, bad=bad,
        addbg=blend(base, good, 0.16), delbg=blend(base, bad, 0.16), warnbg=blend(base, warn, 0.18))


SEPS = ['pixel line', 'eighth-block', 'box line', 'background only']
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
                 ('/theme', 'Tune colours, separators and density', 'SETTING', 'Opens the settings panel. Changes apply live.'),
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
    ('Theme source', 'theme', THEME_SOURCES, 'terminal: derive everything from your terminal\'s own background, foreground and ANSI colours. light / dark: fixed presets.'),
    ('Accent', 'accent', list(ACCENTS), 'Which ANSI colour is the accent (focus bar, chips, selection).'),
    ('Surfaces', 'surface', SURFACES, 'How far panels, the input and bars differ from the background. off: lines and the accent only.'),
    ('Background', 'paint', ['terminal default', 'painted'], 'terminal default: keeps your terminal\'s opacity, blur and wallpaper, but on a translucent terminal the surfaces can look darker than the page. painted: every cell is drawn, so surfaces always match; transparency is lost.'),
    ('Separators', 'sep', SEPS, 'pixel line is 1 or 2 real pixels (kitty graphics) and costs no row. The others are glyphs and cost one row each.'),
    ('Line thickness', 'thick', ['1px', '2px'], 'Pixel separators and the scrollbar only.'),
    ('Transcript spacing', 'tight', ['tight', 'airy'], 'A blank row between blocks, or none.'),
    ('Bottom section', 'bottom', BOTTOMS, 'roomy: work strip, two-row input, status. tight: no work strip. flush: one-row input with inline chips, then status.'),
    ('Status bar', 'status_mode', ['chips', 'line'], 'Coloured chips with a context meter, or one plain line.'),
    ('Layout', 'variant', ['flat', 'surfaces', 'workbench'], 'flat: markers only. surfaces: your messages on a band. workbench: adds the task and agent sidebar.'),
]
SAVED = ['theme', 'accent', 'surface', 'paint', 'sep', 'thick', 'tight', 'bottom', 'status_mode', 'variant']
BRACKET = {'terminal': '', }


class Line:
    def __init__(self, spans, bg=None, gutter=None, edge=False):
        self.spans, self.bg, self.gutter, self.edge = spans, bg, gutter, edge   # edge: draw a hairline at the top


class Lab:
    def __init__(self, variant=1):
        self.variant, self.theme, self.sep, self.thick = variant, 'terminal', 0, 1
        self.tight, self.status_mode = True, 0
        self.accent, self.surface, self.bottom, self.paint = 'blue', 2, 2, 0
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
        source = self.theme
        if source == 'terminal' and self.term:
            self.pal = derive(self.term['base'], self.term['fg'], self.term['ansi'], self.accent, self.surface)
            self.theme_note = 'terminal colours (OSC 10/11/4)'
        else:
            preset = PRESETS['light' if source == 'light' else 'dark']
            self.pal = derive(preset['base'], preset['fg'], preset['ansi'], self.accent, self.surface)
            self.theme_note = ('terminal colours unavailable, using the dark preset' if source == 'terminal'
                               else f'{source} preset')

    def col(self, name):
        return self.pal.get(name, name)

    def native(self):
        """True when the terminal's own colours are in charge: its default background and foreground are used as is."""
        return self.theme == 'terminal' and bool(self.term) and self.paint == 0

    def bg_code(self, name):
        if name == 'base' and self.native():
            return '\033[49m'          # default background: keeps the terminal's opacity, blur and wallpaper
        color = self.col(name)
        if color == self.pal['base']:
            color = nudge(color)       # painted, not "the default background"
        return self.rgb(color, True)

    def fg_code(self, name):
        if name == 'fg' and self.native() and self.pal['fg'] == self.term['fg']:
            return '\033[39m'
        return self.rgb(self.col(name))

    @staticmethod
    def rgb(hexcolor, bg=False):
        h = hexcolor.lstrip('#')
        return '\033[%d;2;%d;%d;%dm' % (48 if bg else 38, int(h[:2], 16), int(h[2:4], 16), int(h[4:], 16))

    def put(self, x, y, text, fg='fg', bg='base', bold=False, rev=False):
        if y < 0 or y >= min(self.h, self.clip_y) or x >= self.xlim or not text:
            return
        text = fit(text, self.xlim - x)
        if not text:
            return
        for i, c in enumerate(text):
            if x + i < self.w:
                self.grid[y][x + i] = c
        sgr = '\033[0' + (';1' if bold else '') + (';7' if rev else '') + 'm'
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

    def place(self, ident, x, y, xoff=0):
        self.out.append(f'\033[{y+1};{x+1}H\033_Ga=p,i={ident},C=1,z=1,q=2,X={xoff}\033\\')

    def rgba(self, name):
        h = self.col(name).lstrip('#')
        return bytes([int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255])

    def px_hline(self, x, y, w, color='line'):
        wpx, t = w * self.cw, self.thick
        raw = (b'\0' + self.rgba(color) * wpx) * t
        self.place(self.image(('h', wpx, t, self.col(color)), wpx, t, raw), x, y)

    def px_vline(self, x, y, h, color='line'):
        t, hpx = self.thick, h * self.ch
        raw = (b'\0' + self.rgba(color) * t) * hpx
        self.place(self.image(('v', hpx, t, self.col(color)), t, hpx, raw), x, y, self.cw // 2)

    def px_scrollbar(self, x, y, rows, start_px, size_px):
        hpx = rows * self.ch
        track, thumb = self.rgba('line'), self.rgba('accent')
        clear = bytes(4)
        row_track = clear * 2 + track + clear * 2
        row_thumb = clear + thumb * 3 + clear
        lines = []
        for r in range(hpx):
            lines.append(b'\0' + (row_thumb if start_px <= r < start_px + size_px else row_track))
        key = ('s', hpx, start_px, size_px, self.col('line'), self.col('accent'))
        self.place(self.image(key, 5, hpx, b''.join(lines)), x, y, max(0, self.cw - 6))

    # ---------- separators ----------
    def sep_rows(self):
        return 0 if (self.sep == 3 or (self.sep == 0 and self.gfx)) else 1

    def rule(self, y, x, w, color='line'):
        if self.sep == 3:
            return
        if self.sep == 0 and self.gfx:
            self.px_hline(x, y, w, color)
        elif self.sep == 2:
            self.put(x, y, '─' * w, color, 'base')
        else:
            self.put(x, y, '▁' * w, color, 'base')

    def vrule(self, x, y, h, bg='base', color='line'):
        if self.sep == 3:
            return
        if self.sep == 0 and self.gfx:
            self.px_vline(x, y, h, color)
        else:
            for r in range(y, y + h):
                self.put(x, r, '│', color, bg)

    # ---------- transcript ----------
    def build(self, tw):
        L, n = [], max(8, tw - 4)
        gap = [] if self.tight else [Line([])]
        band = 'panel' if self.variant >= 2 else None

        def user(text):
            if band:
                L.append(Line([], band, ('▌', 'accent'), edge=bool(L) and L[-1].bg is not None))   # padding inside, above
            for t in wrap(text, tw - 3):
                L.append(Line([(' ' + t, 'fg', None, False)], band, ('▌' if band else '›', 'accent')))
            if band:
                L.append(Line([], band, ('▌', 'accent')))          # padding inside the block, below

        def assistant(text):
            for t in wrap(text, n):
                L.append(Line([('  ' + t, 'fg', None, False)]))

        def disclosure(open_, label, detail, body):
            L.append(Line([(('▾ ' if open_ else '▸ ') + label, 'faint', None, False), ('  ' + detail if detail else '', 'faint', None, False)]))
            if open_:
                for t in body:
                    L.append(Line([('  ' + fit(t, n - 2), 'faint', None, False)], gutter=('▏', 'line')))

        def block(rows):
            """A surfaced block: its own background and edge bar, one padded row above and below inside it."""
            if self.variant < 2:
                for spans, bg in rows:
                    L.append(Line([('  ' + spans[0][0],) + spans[0][1:]] + spans[1:], bg))
                return
            touching = bool(L) and L[-1].bg is not None       # directly under another surfaced block
            L.append(Line([], 'panel', ('▌', 'line'), edge=touching))
            for spans, bg in rows:
                L.append(Line([(' ' + spans[0][0],) + spans[0][1:]] + spans[1:], bg or 'panel', ('▌', 'line')))
            L.append(Line([], 'panel', ('▌', 'line')))

        def agents():
            block([
                ([('◆ ', 'accent', None, False), ('reviewer', 'fg', None, True), ('  cancellation races', 'muted', None, False), ('   ● running 0:42', 'good', None, False)], None),
                ([('◆ ', 'accent', None, False), ('test-runner', 'fg', None, True), ('  restoration regression', 'muted', None, False), ('   ▲ needs approval', 'warn', None, True)], None)])

        def diff():
            block([
                ([('src/RenderLoop.swift', 'muted', None, True), ('   +2 −1', 'faint', None, False)], None),
                ([('− try pipeline.flush()', 'bad', None, False)], 'delbg'),
                ([('+ try halt()  // finish before restore', 'good', None, False)], 'addbg'),
                ([('+ terminal.leave()', 'good', None, False)], 'addbg')])

        topics = ['Where does a frame get its state?', 'Which state is shared between input and rendering?',
                  'What happens to a frame in flight on resize?', 'Does the status line ever block input?',
                  'How is the terminal restored after a signal?']
        for k in range(12):
            last = k == 11
            user(topics[k % 5] if not last else 'Review cancellation in the rendering loop.')
            L.extend(gap)
            assistant('I will trace ownership first, then check shutdown and restoration.' if last else 'Tracing the path from the event loop to the terminal writer. Reading the session and the loop.')
            disclosure(self.thinking, 'Thinking…', '' if self.thinking else '', ['The renderer and event loop share a terminal, not layout state.', 'A halt must finish before the session is restored.', 'Checking whether a pending frame can cross that boundary.'])
            disclosure(self.tools, 'Read 2 files', 'ScreenSession.swift, RenderLoop.swift', ['ScreenSession.swift: terminal.leave() follows renderer.finish().', 'RenderLoop.swift: halt waits for the write in flight.'])
            if last:
                agents()
                L.extend(gap)
                diff()
            L.extend(gap)
            assistant('Cancellation is safe on the normal path. A signal must stop the renderer before leaving the session; the test for that is the remaining gap.' if last else 'The two sides only share the connection. No change is needed here.')
            L.extend(gap)
        for text in self.sent:
            user(text)
            L.extend(gap)
            assistant('Simulated reply. Nothing was sent and nothing ran.')
            L.extend(gap)
        L.append(Line([('⠹ Working…', 'faint', None, False)]))
        return L

    def draw_line(self, ln, y, w):
        bg = ln.bg or 'base'
        if ln.edge and self.sep == 0 and self.gfx:
            self.px_hline(0, y, w)
        if ln.bg:
            self.fill(0, y, w, bg)
        if ln.gutter:
            self.put(0, y, ln.gutter[0], ln.gutter[1], bg, True)
        x = 0 if ln.gutter and ln.gutter[0] in '▌›' and False else 0
        x = 2 if ln.gutter and ln.gutter[0] in '▌›▏' else 0
        for text, fg, sbg, bold in ln.spans:
            self.put(x, y, text, fg, sbg or bg, bold)
            x += width(text)

    # ---------- chrome ----------
    def chip(self, x, y, text, fg, bg, bold=False):
        self.put(x, y, text, fg, bg, bold)
        return x + width(text)

    def draw_status(self, y):
        self.xlim = self.w
        self.fill(0, y, self.w, 'bar')
        mode = (' BROWSE ', 'warn', 'warnbg') if self.browse else (' INPUT ', 'accentfg', 'accent')
        meter_cells, ratio = 12, 0.42
        fill8 = int(ratio * meter_cells * 8)
        bar = '█' * (fill8 // 8) + (BAR[fill8 % 8] if fill8 % 8 else '')
        bar = bar + ' ' * (meter_cells - width(bar))
        right = f' 42%  114k/272k  $0.18 '
        ctx_w = 4 + meter_cells + width(right)
        if self.status_mode == 0:
            x = self.chip(0, y, mode[0], mode[1], mode[2], True)
            parts = ([(f' ↪ {self.route()} ', 'warn', 'warnbg')] if self.route() else []) + [(' gpt-5.5 · high ', 'fg', 'raised'), (' git:main +3 ', 'muted', 'panel'),
                     (' ● 2 working ', 'good', 'panel'), (' ▲ 1 approval ', 'warn', 'warnbg')]
            for text, fg, bg in parts:
                if x + width(text) + 1 + ctx_w > self.w:
                    break
                x = self.chip(x + 1, y, text, fg, bg, bg == 'warnbg')
            if x + ctx_w <= self.w:
                cx = self.w - ctx_w
                self.put(cx, y, 'ctx ', 'faint', 'bar')
                self.put(cx + 4, y, bar, 'accent', 'raised')
                self.put(cx + 4 + meter_cells, y, right, 'fg', 'bar')
        else:
            line = f'{mode[0].strip().lower()} · gpt-5.5 high · git:main +3 · 2 working · 1 approval            ctx 42% · 114k/272k'
            self.put(1, y, fit(line, self.w - 2), 'muted', 'bar')
            self.put(1, y, mode[0].strip().lower(), 'accent', 'bar', True)

    def draw_input(self, in_y):
        self.xlim = self.w
        focus = not self.browse
        flush = self.bottom == 2
        rows = (in_y,) if flush else (in_y, in_y + 1)
        for r in rows:
            self.fill(0, r, self.w, 'input')
            self.put(0, r, '▌', 'accent' if focus else 'line', 'input')
        text_y = in_y if flush else in_y + 1
        x = 2
        if flush:
            x = self.chip(x, text_y, '↪ ' if self.route() else '› ', 'warn' if self.route() else 'accent', 'input', True)
        chip_y = text_y if flush else in_y
        cx0 = x
        if not self.chips and not flush:
            self.put(x, chip_y, '@ file or agent   $ skill   / command', 'faint', 'input')
        for kind, label in self.chips:
            sym = {'file': '@', 'skill': '/', 'agent': '◆', 'session': '↪'}[kind]
            x = self.chip(x, chip_y, f' {sym} {label} ', 'accent', 'raised') + 1
        if not flush:
            hint = (f'Enter sends to {self.route()} · Esc browse' if self.route() else 'Enter send · Esc browse') if focus else 'Esc/Enter back to input · q quit'
            if self.w - width(hint) - 2 > x:
                self.put(self.w - width(hint) - 1, in_y, hint, 'faint', 'input')
            self.put(2, text_y, '↪ ' if self.route() else '› ', 'warn' if self.route() else 'accent', 'input', True)
            x = 4
        avail = max(4, self.w - x - 2)
        start = max(0, self.cursor - avail + 1)
        shown = self.draft[start:start + avail]
        self.put(x, text_y, shown, 'fg', 'input')
        if flush and not self.draft and not self.chips:
            self.put(x, text_y, '@ file   $ skill   / command', 'faint', 'input')
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
        if attr == 'variant':
            return v - 1
        if attr == 'thick':
            return v - 1
        if attr == 'tight':
            return 0 if v else 1
        if isinstance(v, str):
            return options.index(v)
        return int(v)

    def set_setting(self, attr, i, options):
        i %= len(options)
        if attr == 'variant':
            self.variant = i + 1
        elif attr == 'thick':
            self.thick = i + 1
        elif attr == 'tight':
            self.tight = i == 0
        elif attr in ('theme', 'accent'):
            setattr(self, attr, options[i])
        else:
            setattr(self, attr, i)
        if attr in ('theme', 'accent', 'surface', 'paint'):
            self.retheme()

    def snapshot(self):
        return {k: getattr(self, k) for k in SAVED}

    def restore(self, data):
        for k in SAVED:
            if k in data:
                setattr(self, k, data[k])
        self.theme = self.theme if self.theme in THEME_SOURCES else 'terminal'
        self.accent = self.accent if self.accent in ACCENTS else 'blue'
        self.surface = min(3, max(0, int(self.surface)))
        self.sep, self.bottom, self.paint = int(self.sep) % 4, int(self.bottom) % 3, int(self.paint) % 2
        self.variant = min(3, max(1, int(self.variant)))
        self.thick = 2 if int(self.thick) == 2 else 1
        self.retheme()

    def draw_settings(self, bottom):
        self.xlim = self.w
        sr = self.sep_rows()
        n = len(SETTING_ROWS)
        h = sr + 1 + n
        top = max(2, bottom - h)
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
            self.put(0, y, '▌' if i == self.selected else ' ', 'accent', bg)
            self.put(2, y, label, 'fg', bg, i == self.selected)
            value = options[self.setting_index(attr, options)]
            self.put(26, y, '‹ ' + fit(value, split - 32) + ' ›', 'accent' if i == self.selected else 'muted', bg, i == self.selected)
        self.vrule(split, body + 1, bottom - body - 1, 'panel')
        label, attr, options, note = SETTING_ROWS[self.selected]
        px = split + 2
        for j, line in enumerate(wrap(note, self.w - px - 2)[:3]):
            self.put(px, body + 1 + j, line, 'fg' if j == 0 else 'muted', 'panel', j == 0)
        sw = body + 5
        if sw < bottom:
            x = px
            for text, fg, bg in ((' accent ', 'accentfg', 'accent'), (' good ', 'good', 'addbg'), (' warn ', 'warn', 'warnbg'),
                                 (' bad ', 'bad', 'delbg'), (' bar ', 'fg', 'bar'), (' input ', 'fg', 'input'), (' selected ', 'fg', 'raised')):
                if x + width(text) < self.w - 1:
                    x = self.chip(x, sw, text, fg, bg) + 1
        if sw + 2 < bottom:
            self.put(px, sw + 2, fit('colours: ' + self.theme_note, self.w - px - 2), 'muted', 'panel')
        if sw + 3 < bottom and self.term:
            self.put(px, sw + 3, fit(f"terminal background {self.term['base']}  foreground {self.term['fg']}", self.w - px - 2), 'faint', 'panel')

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
        h = sr + 1 + max(4, len(rows))
        top = max(2, bottom - h)
        body = top + sr
        for r in range(top, bottom):
            self.fill(0, r, self.w, 'panel')
        self.rule(top, 0, self.w)
        names = {'commands': 'COMMANDS', 'refs': 'FILES · AGENTS · SESSIONS', 'agents': 'AGENTS', 'tasks': 'TASKS', 'permission': 'APPROVAL'}
        x = self.chip(0, body, f' {names[self.modal]} ', 'accentfg', 'accent', True)
        shown = self.query if self.trigger is None else self.query
        self.put(x + 1, body, 'filter: ' + shown + ('' if self.trigger else '▏'), 'muted', 'panel')
        hint = {'commands': 'Enter insert · Esc close', 'refs': 'Enter attach · Esc close',
                'agents': 'Enter inspect · Esc close', 'tasks': 'Enter inspect · Esc close', 'permission': 'Enter choose · Esc deny'}[self.modal]
        self.put(self.w - width(hint) - 1, body, hint, 'faint', 'panel')
        split = max(30, self.w * 11 // 20)
        for i, (title, desc, kind, detail) in enumerate(rows):
            y = body + 1 + i
            bg = 'raised' if i == self.selected else 'panel'
            self.fill(0, y, split, bg)
            self.put(0, y, '▌' if i == self.selected else ' ', 'accent', bg)
            self.put(2, y, fit(title, 28), 'fg', bg, i == self.selected)
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
        self.out = ['\033[?25l' + ('' if self.theme == 'terminal' and self.term else '\033]11;' + self.col('base') + '\033\\')] + (['\033_Ga=d,d=a,q=2\033\\'] if self.gfx else [])
        self.grid = [[' '] * self.w for _ in range(self.h)]
        self.clip_y, self.xlim = self.h, self.w
        for r in range(self.h):
            self.fill(0, r, self.w, 'base')
        if self.w < 76 or self.h < 26:
            self.put(2, 1, 'UI lab needs at least 76 columns x 26 rows. q quits.', 'warn')
            return ''.join(self.out)
        sr = self.sep_rows()
        status_y = self.h - 1
        in_rows = 1 if self.bottom == 2 else 2
        in_y = status_y - in_rows
        rule_y = in_y - sr
        side = self.variant == 3 and self.w >= 108
        ws_y = rule_y - 1 if (self.bottom == 0 and not side) else None
        self.bottom_y = ws_y if ws_y is not None else rule_y
        vp_y0, vp_y1 = 2, (ws_y if ws_y is not None else rule_y)
        vp_right = self.w - (30 if side else 0)
        vp_h = vp_y1 - vp_y0

        # transcript viewport: the only region expansion may touch
        self.clip_y, self.xlim = vp_y1, vp_right - 1
        lines = self.build(vp_right - 1)
        total = len(lines)
        self.scroll = max(0, min(self.scroll, max(0, total - vp_h)))
        start = max(0, total - vp_h - self.scroll)
        for i, ln in enumerate(lines[start:start + vp_h]):
            self.draw_line(ln, vp_y0 + i, vp_right - 1)
        self.xlim = vp_right
        if total > vp_h:
            self.draw_scrollbar(vp_right - 1, vp_y0, vp_h, total, start)
        if self.scroll > 0:
            pill = f' ↓ {self.scroll} lines below · End '
            self.put(vp_right - 1 - width(pill) - 1, vp_y1 - 1, pill, 'accentfg', 'accent', True)
        self.clip_y = self.h

        # header
        self.xlim = self.w
        self.fill(0, 1, self.w, 'bar')
        x = self.chip(0, 1, ' ask ', 'accentfg', 'accent', True)
        self.put(x + 1, 1, 'render-loop', 'fg', 'bar', True)
        self.put(x + 14, 1, 'git:main', 'muted', 'bar')
        right = 'gpt-5.5 · high · edits ask first'
        self.put(self.w - width(right) - 1, 1, right, 'muted', 'bar')
        if self.sep == 0 and self.gfx:
            self.px_hline(0, 2, self.w)

        # sidebar or work strip
        if side:
            sx = vp_right
            for r in range(vp_y0, rule_y):
                self.fill(sx, r, 30, 'panel')
            self.vrule(sx, vp_y0, rule_y - vp_y0, 'panel')
            self.xlim = self.w
            rows = [('TASKS', 'faint', True), ('✓ Trace event path', 'good', False), ('● Review cancellation', 'fg', True), ('▲ Verify restoration', 'warn', True), ('○ Summarize findings', 'faint', False), ('', 'fg', False),
                    ('AGENTS', 'faint', True), ('◆ reviewer      running', 'fg', False), ('◆ test-runner   approval', 'warn', False), ('', 'fg', False),
                    ('CONTEXT', 'faint', True), ('2 files · 1 skill', 'muted', False), ('42%  114k/272k', 'muted', False)]
            for i, (text, fg, bold) in enumerate(rows):
                self.put(sx + 2, vp_y0 + i, fit(text, 27), fg, 'panel', bold)
        elif ws_y is not None:
            self.xlim = self.w
            self.fill(0, ws_y, self.w, 'raised')
            x = self.chip(0, ws_y, ' WORK ', 'accentfg', 'accent', True)
            for text, fg in (('✓ 1 done', 'good'), ('● 1 running', 'fg'), ('▲ 1 approval', 'warn')):
                x = self.chip(x + 1, ws_y, text, fg, 'raised', fg == 'warn')
            tail = 'reviewer ●   test-runner ▲   Esc, then a / t / p'
            if self.w - width(tail) - 1 > x:
                self.put(self.w - width(tail) - 1, ws_y, tail, 'muted', 'raised')

        self.rule(rule_y, 0, self.w)
        self.draw_input(in_y)
        self.draw_status(status_y)
        if self.modal:
            self.draw_popup(rule_y)

        # lab strip (not part of the product UI)
        self.xlim = self.w
        names = ['1 Flat', '2 Surfaces', '3 Workbench']
        shown = '  '.join(('[' + n + ']') if i + 1 == self.variant else n for i, n in enumerate(names))
        sep = SEPS[self.sep] + ('' if self.sep != 0 or self.gfx else ' (n/a→eighth)')
        text = f' LAB  {shown} │ s settings   b x d v m l quick cycle   r rescan colours │ Esc: browse keys │ {self.theme} · {BOTTOMS[self.bottom]} bottom '
        self.put(0, 0, ' ' * self.w, '#ffffff', '#000000')
        self.put(0, 0, fit(text, self.w), '#ffffff', '#000000', True)
        return ''.join(self.out)

    def draw_scrollbar(self, x, y, rows, total, start):
        if self.sep == 0 and self.gfx:
            hpx = rows * self.ch
            size = max(8, int(hpx * rows / total))
            top = int((hpx - size) * (start / max(1, total - rows)))
            self.px_scrollbar(x, y, rows, top, size)
            return
        if self.sep == 3:
            half = 2 * rows
            size = max(1, round(half * rows / total))
            top = round((half - size) * (start / max(1, total - rows)))
            for r in range(rows):
                lo, hi = 2 * r, 2 * r + 2
                cover = max(0, min(hi, top + size) - max(lo, top))
                glyph = '▐' if cover == 2 else ('▗' if cover == 1 and top > lo else '▝' if cover == 1 else '▕')
                self.put(x, y + r, glyph, 'accent' if cover else 'line', 'base')
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
        elif k in '123':
            self.variant = int(k)
        elif k == 'b':
            self.sep = (self.sep + 1) % 4
        elif k == 'x':
            self.thick = 3 - self.thick
        elif k == 'd':
            self.tight = not self.tight
        elif k == 'm':
            self.status_mode = 1 - self.status_mode
        elif k == 'l':
            self.theme = THEME_SOURCES[(THEME_SOURCES.index(self.theme) + 1) % 3]
            self.retheme()
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
    # 1. Contrast holds on real terminal themes, including low-contrast ones, for every accent and surface level.
    palettes = dict(TERMS, **{n: PRESETS[n] for n in PRESETS})
    n_pal = 0
    for name, t in palettes.items():
        for accent in ACCENTS:
            for surface in range(4):
                pal = derive(t['base'], t['fg'], t['ansi'], accent, surface)
                where = (name, accent, surface)
                assert contrast(pal['fg'], pal['base']) >= 7.0, where
                assert contrast(pal['muted'], pal['base']) >= 5.0, where
                for key in ('faint', 'accent', 'good', 'warn', 'bad'):
                    assert contrast(pal[key], pal['base']) >= 4.5, (key,) + where
                assert contrast(pal['accentfg'], pal['accent']) >= 4.5, where
                assert contrast(pal['line'], pal['base']) >= 2.6, where
                for key, bg in (('good', 'addbg'), ('bad', 'delbg'), ('warn', 'warnbg')):
                    assert contrast(pal[key], pal[bg]) >= 3.5, (key, bg) + where
                assert contrast(pal['accent'], pal['raised']) >= 3.0, where
                assert (pal['panel'] == pal['base']) == (surface == 0), where
                n_pal += 1
    # 2. Rendering matrix.
    app = Lab()
    app.term = TERMS['solarized-dark']
    app.retheme()
    count = 0
    for variant in (1, 2, 3):
        for sep in range(4):
            for tight in (True, False):
                for status in (0, 1):
                    for bottom in range(3):
                        for gfx in (False, True):
                            for modal in (None, 'refs', 'commands', 'settings'):
                                for shape in ((80, 30), (110, 34), (140, 45))[:2 if modal else 3]:
                                    app.variant, app.sep, app.tight, app.status_mode, app.bottom = variant, sep, tight, status, bottom
                                    app.force_gfx, app.modal, app.trigger = gfx, modal, None
                                    assert app.render(shape, (16, 30) if gfx else None)
                                    count += 1
    for theme in THEME_SOURCES:
        for accent in ACCENTS:
            for surface in range(4):
                app.theme, app.accent, app.surface, app.modal = theme, accent, surface, None
                app.retheme()
                assert app.render((120, 40))
                count += 1
    assert 'terminal colours unavailable' in (lambda a: (setattr(a, 'theme', 'terminal'), a.retheme(), a.theme_note)[-1])(Lab())
    app = Lab()
    app.force_gfx = True
    out = app.render((120, 42), (16, 30))
    assert 'a=p' in out and 'a=t' in out
    # 3. Expanding thinking or tools never changes the input, status or work rows, in every bottom density.
    for bottom in range(3):
        for sep in (0, 1, 3):
            for variant in (1, 3):
                app = Lab(variant)
                app.sep, app.bottom, app.force_gfx = sep, bottom, sep == 0
                app.draft, app.cursor = 'half typed @re', 8
                cell = (16, 30) if sep == 0 else None
                app.render((120, 42), cell)
                before = [''.join(r) for r in app.grid[app.bottom_y:]]
                app.key('\x14')
                app.key('\x0f')
                app.render((120, 42), cell)
                assert before == [''.join(r) for r in app.grid[app.bottom_y:]], (bottom, sep, variant)
                assert app.draft == 'half typed @re' and app.cursor == 8
    # flush is the tightest: fewer bottom rows than tight than roomy
    heights = []
    for bottom in range(3):
        app = Lab(1)
        app.sep, app.bottom, app.force_gfx = 0, bottom, True
        app.render((120, 42), (16, 30))
        heights.append(42 - app.bottom_y)
    assert heights[0] > heights[1] > heights[2], heights
    # 3b. Every surfaced block has one padded row above and below, inside its own background; none between blocks.
    for variant in (2, 3):
        app = Lab(variant)
        lines = app.build(100)
        runs, run = [], []
        for ln in lines + [Line([])]:
            if ln.gutter and ln.gutter[0] == '▌':
                run.append(ln)
            else:
                if run:
                    runs.append(run)
                run = []
        assert len(runs) >= 13, len(runs)       # 12 user messages, the agent group and the diff
        for r in runs:
            assert not r[0].spans and not r[-1].spans, 'block must open and close with a padded row'
            assert r[0].bg == r[-1].bg and r[0].bg is not None
            assert any(ln.spans for ln in r), 'block has content'
        for a, b in zip(lines, lines[1:]):      # no blank margin rows between blocks (tight spacing)
            assert a.spans or b.spans or a.bg or b.bg
    flat = Lab(1).build(100)
    assert all(ln.spans for ln in flat if ln.gutter and ln.gutter[0] == '›')
    # 4. Reading earlier output: expanding must not move the viewport offset.
    app = Lab()
    app.render((100, 28))
    assert len(app.build(99)) - (28 - 2 - 2 - 3 - 1) >= 7
    app.scroll = 7
    app.key('\x14')
    app.render((100, 28))
    assert app.scroll == 7
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
    assert '↪' in ''.join(app.grid[-1]) + ''.join(app.grid[-2]) + ''.join(app.grid[-3])
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
    # 7. Settings: panel opens, changes apply live, snapshot round-trips, '/theme' opens it from the input.
    app = Lab()
    app.browse = True
    app.key('s')
    assert app.modal == 'settings'
    app.key('\x1b[C')
    assert app.theme == 'light' and app.pal['base'] == '#ffffff'
    app.key('\x1b[B')
    app.key('\x1b[C')
    assert app.accent == 'cyan'
    app.key('\x1b[B')
    app.key('\x1b[D')
    assert app.surface == 1
    snap = app.snapshot()
    other = Lab()
    other.restore(snap)
    assert other.snapshot() == snap and other.pal == app.pal
    other.restore({'theme': 'bogus', 'accent': 'bogus', 'surface': 99, 'sep': 99, 'bottom': -5, 'variant': 9})
    assert other.theme == 'terminal' and 0 <= other.surface <= 3 and 0 <= other.bottom <= 2
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
    # 8b. Painted cells never equal the terminal's own background, or a translucent terminal drops them.
    app = Lab()
    app.term = TERMS['kitty-default']
    app.paint = 1
    app.retheme()
    out = app.render((120, 40))
    assert '\x1b[49m' not in out and '48;2;0;0;0m' not in out and '48;2;1;1;1m' in out
    assert nudge('#000000') == '#010101' and nudge('#ffffff') == '#fefefe' and nudge('#fdf6e3') == '#fcf5e2'
    app.paint = 0
    app.retheme()
    assert '\x1b[49m' in app.render((120, 40))
    # 9. OSC reply parsing.
    assert parse_colors(b'\x1b]10;rgb:dddd/dddd/dddd\x1b\\\x1b]11;rgb:0000/0000/0000\x1b\\\x1b]4;1;rgb:cc/00/00\x1b\\') == {'ansi': {1: '#cc0000'}, 'fg': '#dddddd', 'base': '#000000'}
    assert parse_colors(b'\x1b[?62;c') is None
    print(f'PASS: {n_pal} palettes meet contrast, {count} renders, bottom-row invariance in 3 densities, '
          'commands/skills under /, files/agents/sessions under @, routing, settings, /theme, rescan.')


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
