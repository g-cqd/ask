#!/usr/bin/env python3
"""Records the wheel events the terminal sends, with their times (note n50, task t236), to tell whether the terminal keeps sending
scroll events after the person's gesture stopped the momentum, or whether ask drew them late.

Run it in the terminal where the scroll seems to go on (kitty, say): scroll with momentum, stop it with two fingers, then press q.
It prints each burst: how many events, up or down, and the gaps; a burst still arriving after you stopped is the terminal's.
Nothing is sent anywhere; the terminal is restored on exit.
"""
import os
import select
import sys
import termios
import time
import tty


def main():
    fd = sys.stdin.fileno()
    saved = termios.tcgetattr(fd)
    events = []
    try:
        tty.setraw(fd)
        # Any-event mouse reports in SGR form; the wheel is buttons 64 (up) and 65 (down).
        os.write(sys.stdout.fileno(), b"\x1b[?1000h\x1b[?1006h")
        os.write(sys.stdout.fileno(), b"Scroll, stop the momentum with two fingers, then press q.\r\n")
        buffer = b""
        while True:
            if not select.select([fd], [], [], 0.5)[0]:
                continue
            buffer += os.read(fd, 4096)
            now = time.monotonic()
            if b"q" in buffer.split(b"\x1b")[0] or buffer.endswith(b"q"):
                break
            while b"\x1b[<" in buffer:
                start = buffer.index(b"\x1b[<")
                end = min((i for i in (buffer.find(b"M", start), buffer.find(b"m", start)) if i != -1), default=-1)
                if end == -1:
                    break
                button = buffer[start + 3:end].split(b";")[0]
                if button in (b"64", b"65"):
                    events.append((now, "up" if button == b"64" else "down"))
                buffer = buffer[end + 1:]
    finally:
        os.write(sys.stdout.fileno(), b"\x1b[?1006l\x1b[?1000l")
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)
    bursts, current = [], []
    for event in events:
        if current and event[0] - current[-1][0] > 0.25:
            bursts.append(current)
            current = []
        current.append(event)
    if current:
        bursts.append(current)
    start = events[0][0] if events else 0
    for burst in bursts:
        gaps = [round((b[0] - a[0]) * 1000) for a, b in zip(burst, burst[1:])]
        print(f"at {burst[0][0] - start:6.2f} s: {len(burst):3} {burst[0][1]:4} events over "
              f"{(burst[-1][0] - burst[0][0]) * 1000:6.0f} ms; gaps (ms): {gaps[:12]}{' …' if len(gaps) > 12 else ''}")


if __name__ == "__main__":
    main()
