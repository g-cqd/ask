#!/usr/bin/env python3
"""Probe of the block model on the real binary over a PTY (roadmap 0074): tinted tool blocks scrolling off the top of the transcript leave no band behind.

The transcript is a terminal scroll region. A terminal fills the rows a scroll exposes with the *current* background, so if the renderer ever scrolled
with a tint still set, a coloured band would appear at the edge. The probe reads the raw bytes the renderer wrote and checks, at every scroll sequence
(`CSI n S`, `CSI n T`, `ESC D`, `ESC M`), that no background is set. It also checks that tints were written at all (the control: without them the
check proves nothing). The screen is not read back through an emulator: pyte has no scroll-up (`CSI S`), so what it shows after a scroll is wrong.

A control makes the byte check able to fail: synthetic bytes that scroll with a tint set must be reported.

Usage: Scripts/probe-blocks.py .build/release/ask
"""
import importlib.util, os, re, sys, tempfile

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("interactive", os.path.join(here, "probe-interactive.py"))
interactive = importlib.util.module_from_spec(spec)
spec.loader.exec_module(interactive)
agent = interactive.agent

SGR = re.compile(rb"\x1b\[([0-9;:]*)m")
SCROLL = re.compile(rb"\x1b\[[0-9]*[ST]|\x1bD|\x1bM")
TOKEN = re.compile(rb"\x1b\[([0-9;:]*)m|\x1b\[[0-9]*[ST]|\x1bD|\x1bM")


def background_set_at_scrolls(data):
    """The offsets of scroll sequences written while a background colour was set."""
    set_bg, found = False, []
    for match in TOKEN.finditer(data):
        if match.group(0).endswith(b"m") and match.group(1) is not None:
            params = match.group(1).decode().replace(":", ";").split(";") if match.group(1) else ["0"]
            i = 0
            while i < len(params):
                p = params[i] or "0"
                if p in ("0", "49"):
                    set_bg = False
                elif p == "48":
                    set_bg = True
                    i += 2 if i + 1 < len(params) and params[i + 1] == "5" else 4 if i + 1 < len(params) and params[i + 1] == "2" else 0
                elif p.isdigit() and (40 <= int(p) <= 47 or 100 <= int(p) <= 107):
                    set_bg = True
                i += 1
        else:
            if set_bg:
                found.append(match.start())
    return found


def control():
    clean = b"\x1b[48;2;1;2;3mtext\x1b[0m\x1b[1S"
    dirty = b"\x1b[48;2;1;2;3mtext\x1b[1S\x1b[0m"
    return background_set_at_scrolls(clean) == [] and len(background_set_at_scrolls(dirty)) == 1


def run():
    project = tempfile.mkdtemp()
    turns = [agent.turn([("tool", f"t{i}", f"echo block-{i}")], "tool_use") for i in range(8)]
    server = agent.Server(turns + [agent.turn([("text", "All done.")], "end_turn")])
    screen = interactive.Screen(server.url, project)
    screen.until("\x00", 1.5)
    screen.type("Run them all\r")
    ok = screen.until("All done.", 30)
    screen.until("\x00", 0.8)
    data = screen.output
    screen.type("\x03\x03")
    screen.finish(3)
    server.httpd.shutdown()
    return ok, data


def main():
    results = [agent.check("the byte check can fail: a scroll with a tint set is reported, one after a reset is not", control())]
    ok, data = run()
    results.append(agent.check("the run finished", ok))
    scrolls = len(SCROLL.findall(data))
    results.append(agent.check("the transcript scrolled (the check had something to check)", scrolls > 0, scrolls))
    bad = background_set_at_scrolls(data)
    results.append(agent.check("no scroll was written with a background set", not bad, bad[:5]))
    tints = len(re.findall(rb"\x1b\[[0-9;]*48;2;", data))
    results.append(agent.check("tints were written (the control for the scroll check)", tints > 0, tints))
    return all(results)


if __name__ == "__main__":
    sys.exit(0 if main() else 1)
