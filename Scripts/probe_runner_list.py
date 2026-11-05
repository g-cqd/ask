"""The list of threads and jobs as the probes read it (roadmap 0195): the rows under the status line, flat for jobs alone and the
sidebar's tree once a thread exists, and how a probe opens a runner's lane from it."""
import re
import time

# A row's mark, as the tree draws it; a spinner or ● is a runner at work, and ◇ (a thread) or $ (a job) one at work but quiet.
MARKS = {"✓": "merged", "■": "stopped", "?": "waiting", "◌": "held", "✗": "failed"}


def lines(terminal):
    """The list's rows: everything drawn under the status line."""
    display = terminal.screen.display
    status = next((index for index, line in enumerate(display) if "anthropic/" in line), len(display))
    return [line.rstrip() for line in display[status + 1:] if line.strip()]


def runner_rows(terminal):
    """The rows the keys move through, in order: neither main, nor the Jobs heading, nor "… N more"."""
    return [line for line in lines(terminal) if not line.startswith("◆ main") and line != "Jobs" and not line.startswith("… ")]


def row(terminal, name):
    """The row of the runner shown as `name`, or None."""
    pattern = re.compile(r"^(?:[│ ] |[├└] )*(?:\+\d+ )?\S+ " + re.escape(name) + r"(?: |$)")
    return next((line for line in runner_rows(terminal) if pattern.match(line)), None)


def mark_of(terminal, text):
    """The mark of the first runner row that shows `text`, or None."""
    shown = next((line for line in runner_rows(terminal) if text in line), None)
    return re.match(r"^(?:[│ ] |[├└] )*(?:\+\d+ )?(\S+) ", shown).group(1) if shown else None


def state(terminal, name):
    """What the runner's mark says: merged, stopped, waiting, held, failed, or running; None when it is not listed."""
    shown = row(terminal, name)
    if shown is None:
        return None
    mark = re.match(r"^(?:[│ ] |[├└] )*(?:\+\d+ )?(\S+) ", shown).group(1)
    return MARKS.get(mark, "running")


def show(terminal):
    """Opens the list unless it is shown: /jobs toggles it."""
    if not any(line.startswith("◆ main") or re.match(r"^\[#", line) for line in lines(terminal)):
        terminal.send(b"/jobs\r")
    terminal.until(lambda: any(line.startswith("◆ main") for line in lines(terminal)))


def open_lane(terminal, name):
    """Shows the runner `name`'s lane through the list: Down to its row, then Enter."""
    show(terminal)
    terminal.until(lambda: row(terminal, name) is not None)
    index = runner_rows(terminal).index(row(terminal, name))
    for _ in range(index + 1):
        terminal.send(b"\x1b[B")
        time.sleep(0.2)
    terminal.send(b"\r")
    terminal.until(lambda: "back to the conversation" in terminal.text())


def open_thread(terminal, name):
    """Shows thread `name`'s lane through `/threads NAME`, the way to a merged thread, which the list leaves out."""
    terminal.send(b"/threads " + name.encode() + b"\r")
    terminal.until(lambda: "back to the conversation" in terminal.text())
