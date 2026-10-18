#!/usr/bin/env python3
"""Measure what a REAL terminal reports for its cell size, and what chrome would cost.

Run this INSIDE the terminal you want to measure, and give it somewhere to write:

    python3 Scripts/verify-cell-pixels.py /tmp/ask-cell-probe/kitty.txt

It is a Python script for the same reason as TerminalKit's reset verifier: it has
to run inside somebody else's terminal without a build step, and it writes nothing
to stdout, because anything it printed would interleave with the measurement.

Three questions, and this entry (0014) exists because none of them has a number:

  1. Does TIOCGWINSZ report real pixel dimensions here, or zeros?
  2. What cell size does that imply, and is it inside TerminalKit's drawable
     ranges (1...256 wide, 1...512 high)?
  3. How many bytes would a pixel-chrome frame actually cost?

Question 3 is estimated here from the encoder's shape, not measured end to end:
TerminalKit's PixelChrome transmits a 4-byte RGBA pixel per pixel of image, once
per distinct image, then re-places without re-sending. That estimate is labelled
as an estimate in the report so it cannot later be read as a measurement.

A terminal reporting zeros is a RESULT here, not a skip. It means chrome is
unavailable on that terminal and the UI must fall back to characters — which is
exactly the degradation the white paper says must not be silent.
"""
import fcntl
import json
import os
import struct
import sys
import termios
import time

REPORT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/ask-cell-probe/probe.txt"

# TerminalKit's CellPixelSize.drawableWidths / drawableHeights.
DRAWABLE_WIDTHS = range(1, 257)
DRAWABLE_HEIGHTS = range(1, 513)


def say(s):
    with open(REPORT, "a") as f:
        f.write(s + "\n")


def winsize(fd):
    """TIOCGWINSZ: rows, cols, xpixel, ypixel."""
    packed = fcntl.ioctl(fd, termios.TIOCGWINSZ, b"\0" * 8)
    return struct.unpack("HHHH", packed)


def env_report():
    """The inputs TerminalCapabilities currently trusts, recorded for comparison."""
    keys = ("KITTY_WINDOW_ID", "TERM", "TERM_PROGRAM", "KONSOLE_VERSION", "COLORTERM")
    return {k: os.environ.get(k) for k in keys}


def guess_graphics(env):
    """TerminalCapabilities.init(environment:size:) logic, replicated so the two can be
    compared. If this guess and the measured cell size disagree, the guess is wrong
    for this terminal — which is the point of recording both."""
    program = (env.get("TERM_PROGRAM") or "").lower()
    term = (env.get("TERM") or "").lower()
    return bool(
        env.get("KITTY_WINDOW_ID")
        or "kitty" in term
        or program == "ghostty"
        or program == "wezterm"
        or env.get("KONSOLE_VERSION")
    )


def chrome_estimate(cell_w, cell_h, columns, rows):
    """Bytes the first frame of chrome would cost, from PixelChrome's own shape:
    one RGBA transmit per distinct image, then one placement each per frame."""
    if not (cell_w and cell_h):
        return None
    # A representative frame: one full-width horizontal rule, one full-height
    # vertical gutter rule, plus a scrollbar bar 4px x (a third of the height).
    h_rule_px = columns * cell_w
    v_rule_px = rows * cell_h
    thumb_px = max(1, (rows * cell_h) // 3)
    images = [
        (h_rule_px, 1),   # horizontal rule, 1px tall
        (1, v_rule_px),   # vertical rule, 1px wide
        (4, thumb_px),    # scrollbar thumb
    ]
    payload = sum(4 * w * h for w, h in images)   # RGBA, base64-encoded in transit
    # Placements: ESC + APC control + move-cursor, each roughly 40 bytes.
    placements = 3 * 40
    return {
        "distinctImages": len(images),
        "rgbaPayloadBytesFirstFrame": payload,
        "placementBytesPerFrame": placements,
        "note": "images transmit once and are cached; steady state is placements only",
    }


def main():
    os.makedirs(os.path.dirname(REPORT) or ".", exist_ok=True)
    # Truncate, so a re-run in the same file does not append to a stale result.
    open(REPORT, "w").close()

    say("# ask cell-pixel probe")
    say("")

    # Deliberately the controlling terminal's fd, not stdin: inside a terminal
    # process, fd 0 is the tty, and this must measure the window the user sees.
    try:
        rows, cols, xpix, ypix = winsize(0)
    except Exception as exc:  # noqa: BLE001 - the failure itself is the result
        say(json.dumps({
            "verdict": "NO_TTY",
            "error": str(exc),
            "note": "no controlling terminal; run this inside a real terminal",
        }, indent=2))
        return

    say("## TIOCGWINSZ (as reported)")
    say("")
    say(f"- rows            : {rows}")
    say(f"- columns         : {cols}")
    say(f"- pixelWidth      : {xpix}")
    say(f"- pixelHeight     : {ypix}")
    say("")

    cell_w = xpix // cols if (xpix and cols) else 0
    cell_h = ypix // rows if (ypix and rows) else 0

    env = env_report()
    graphics_guess = guess_graphics(env)

    say("## Implied cell size")
    say("")
    say(f"- cell width      : {cell_w} px")
    say(f"- cell height     : {cell_h} px")
    drawable = bool(cell_w) and bool(cell_h) and (
        cell_w in DRAWABLE_WIDTHS and cell_h in DRAWABLE_HEIGHTS)
    say(f"- drawable        : {drawable}")
    say("")

    say("## Environment variables TerminalCapabilities currently trusts")
    say("")
    for k, v in env.items():
        say(f"- {k:20s}: {v if v else '(unset)'}")
    say("")
    say(f"- guessed supportsKittyGraphics: {graphics_guess}")
    say(f"- measured cell size available : {drawable}")
    say("")

    verdict = "PIXELS" if drawable else "NO_PIXELS"
    say("## Verdict")
    say("")
    say(f"**{verdict}**")
    if verdict == "NO_PIXELS":
        say("")
        say("This terminal reports no usable pixel dimensions. Pixel chrome cannot be")
        say("drawn here and the UI must fall back to characters. That is a result, not")
        say("a skip: it is the case where a silent fallback would be a defect.")
    elif not graphics_guess:
        say("")
        say("NOTE: the environment variables do NOT name this terminal as graphics-")
        say("capable, yet real pixels are reported. TerminalCapabilities' env-var")
        say("guess is wrong here — which is roadmap 0003's claim, measured.")
    say("")

    est = chrome_estimate(cell_w, cell_h, cols, rows)
    if est:
        say("## Chrome cost, ESTIMATED from the encoder shape (not a measurement)")
        say("")
        say("```json")
        say(json.dumps(est, indent=2))
        say("```")
        say("")
        say("This is an estimate. The budget impact is measured separately by")
        say("Scripts/verify-chrome-cost.sh, which runs the real binary.")
    say("")
    say(f"_generated {time.strftime('%Y-%m-%dT%H:%M:%S')}_")


if __name__ == "__main__":
    main()