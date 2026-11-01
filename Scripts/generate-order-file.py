#!/usr/bin/env python3
"""Write Scripts/ask-startup.order: the functions ask runs from launch to its idle prompt and its first keystroke, in the order
they first run (roadmap 0088).

The `ask` executable is linked with this file as its order file (Package.swift), so those functions sit together at the start of
its code instead of across most of it: starting then touches fewer pages, and fewer pages stay resident. Measured on 2026-11-01:
idle resident size 15.6 MiB without it, 14.1 MiB with it.

How the list is made: a release build with coverage tracing (`-sanitize=address -sanitize-coverage=func,trace-pc-guard`; Swift
allows the tracing only beside a sanitizer) records each function the first time it runs, after optimisation, so the witnesses,
specialisations, accessors and thunks the compiler adds are in it too. The run is the budget script's: a PTY 120x40, isolated
configuration and state, the prompt, one key, `/quit`. The sanitizer runtime writes the addresses at exit; they are named from the
build's symbol table.

The file goes stale as the code changes: a name that no longer exists is skipped by the linker, and a new startup function lands
where the code puts it, so the gain wears off rather than breaking anything. Run this again after a large change, and compare the
idle figure of Scripts/measure-budgets.py before and after.

    python3 Scripts/generate-order-file.py            write the file
    python3 Scripts/generate-order-file.py --check    how many of its names .build/release/ask still has
"""
import bisect, glob, os, pty, select, struct, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ORDER = os.path.join(ROOT, "Scripts", "ask-startup.order")
SCRATCH = os.path.expanduser("~/Library/Caches/g-cqd-build/ask-order-file")
PROMPT = "────".encode()
FRAME_END = b"\x1b[?2026l"


def names_in(binary):
    """The binary's code symbols, by address."""
    out = subprocess.run(["nm", "-n", binary], capture_output=True, text=True, check=True).stdout
    symbols = []
    for line in out.splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[1] in "tT":
            symbols.append((int(parts[0], 16), parts[2]))
    return symbols


def check():
    binary = os.path.join(ROOT, ".build", "release", "ask")
    wanted = open(ORDER).read().split()
    present = {name for _, name in names_in(binary)}
    found = sum(1 for name in wanted if name in present)
    print(f"{found} of {len(wanted)} names in {ORDER} are in {binary} ({100 * found // max(1, len(wanted))}%)")


def build():
    subprocess.run(
        ["swift", "build", "-c", "release", "--product", "ask", "--scratch-path", SCRATCH,
         "-Xswiftc", "-sanitize=address", "-Xswiftc", "-sanitize-coverage=func,trace-pc-guard"],
        cwd=ROOT, check=True)
    return os.path.join(SCRATCH, "release", "ask")


def read_until(fd, needle, timeout):
    buffer = b""
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        ready, _, _ = select.select([fd], [], [], 0.05)
        if not ready:
            continue
        try:
            buffer += os.read(fd, 65536)
        except OSError:
            return False
        at = buffer.rfind(needle)
        if at >= 0 and FRAME_END in buffer[at:]:
            return True
    return False


def run(binary, directory):
    """Starts ask in a PTY as the budget script does, waits for the prompt, types a key, quits."""
    config, state = tempfile.mkdtemp(prefix="ask-order-config-"), tempfile.mkdtemp(prefix="ask-order-state-")
    pid, fd = pty.fork()
    if pid == 0:
        import fcntl, termios
        fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
        for key in list(os.environ):
            if key.startswith(("ASK_", "ANTHROPIC_", "OPENAI_", "CODEX_")):
                os.environ.pop(key)
        os.environ.update(
            TERM="xterm-kitty", TERM_PROGRAM="kitty", XDG_CONFIG_HOME=config, XDG_STATE_HOME=state,
            ASAN_OPTIONS=f"coverage=1:coverage_dir={directory}:detect_leaks=0")
        os.execv(binary, [binary])
        os._exit(127)
    try:
        if not read_until(fd, PROMPT, 20.0):
            sys.exit("ask did not show its prompt")
        time.sleep(0.25)
        os.write(fd, b"x")
        read_until(fd, b"x", 5.0)
        os.write(fd, b"\x7f/quit\r")
        end = time.monotonic() + 20
        while time.monotonic() < end:
            ready, _, _ = select.select([fd], [], [], 0.05)
            if ready:
                try:
                    os.read(fd, 65536)
                except OSError:
                    pass
            done, _ = os.waitpid(pid, os.WNOHANG)
            if done:
                return
        sys.exit("ask did not quit")
    finally:
        os.close(fd)


def main():
    if "--check" in sys.argv:
        return check()
    binary = build()
    directory = tempfile.mkdtemp(prefix="ask-order-coverage-")
    run(binary, directory)
    dumps = glob.glob(os.path.join(directory, "*.sancov"))
    if len(dumps) != 1:
        sys.exit(f"expected one coverage dump, found {dumps}")
    data = open(dumps[0], "rb").read()
    addresses = struct.unpack(f"<{(len(data) - 8) // 8}Q", data[8:])
    symbols = names_in(binary)
    starts = [address for address, _ in symbols]
    order, seen = [], set()
    for address in addresses:
        index = bisect.bisect_right(starts, address) - 1
        if index < 0:
            continue
        name = symbols[index][1]
        # The sanitizer's own functions are not in the build that ships.
        if name in seen or "asan" in name or "sanitizer" in name:
            continue
        seen.add(name)
        order.append(name)
    with open(ORDER, "w") as file:
        file.write("\n".join(order) + "\n")
    print(f"{len(order)} functions written to {ORDER}")


if __name__ == "__main__":
    main()
