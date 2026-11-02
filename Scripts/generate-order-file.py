#!/usr/bin/env python3
"""Write Scripts/ask-startup.order: the functions ask runs from launch to its idle prompt and its first keystroke, in the order
they first run, then those a first tool turn adds (roadmap 0088).

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
import bisect, importlib.util, glob, os, pty, select, struct, subprocess, sys, tempfile, time

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
            ASAN_OPTIONS=f"coverage=1:coverage_dir={directory}:detect_leaks=0",
            # After the clean-up above, which removes every ASK_ variable: no first-start question (roadmap 0182), which would take the
            # keys and the run would never reach the prompt's code.
            ASK_SESSION_ENCRYPTION="off")
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


def first_turn(binary, directory):
    """Startup, then one tool turn, `read` of a small file, as the action budget measures it (Scripts/measure-action.py): a prompt
    typed, the model's tool call from a fake server, the result shown, the model's answer; then `/quit`, so the coverage is written.
    The turn's functions follow startup's in the file, so a first turn touches fewer of ask's pages too (roadmap 0088: a turn paged in
    2.9 MiB of ask's code, startup 2.2 MiB)."""
    here = os.path.dirname(os.path.abspath(__file__))
    sys.argv, saved = [sys.argv[0], binary], sys.argv
    spec = importlib.util.spec_from_file_location("measure_action", os.path.join(here, "measure-action.py"))
    action = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(action)
    sys.argv = saved
    project, state = tempfile.mkdtemp(prefix="ask-order-project-"), tempfile.mkdtemp(prefix="ask-order-state-")
    open(os.path.join(project, "note.txt"), "w").write("a small file\n")
    turns = [action.agent.turn([("call", "t1", "read", {"path": "note.txt"})], "tool_use"),
             action.agent.turn([("text", "Finished.")], "end_turn")]
    server = action.TimedServer(turns)
    environment = action.agent.environment(state, server.url)
    environment.update(TERM="xterm-kitty", TERM_PROGRAM="kitty",
                       ASAN_OPTIONS=f"coverage=1:coverage_dir={directory}:detect_leaks=0")
    pid, fd = pty.fork()
    if pid == 0:
        import fcntl, termios
        fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
        os.chdir(project)
        os.execve(binary, [binary], environment)
        os._exit(127)
    try:
        if not read_until(fd, PROMPT, 20.0):
            sys.exit("ask did not show its prompt")
        time.sleep(0.25)
        os.write(fd, b"Go\r")
        if not read_until(fd, "Finished.".encode(), 30.0):
            sys.exit("the first turn did not finish")
        time.sleep(0.25)
        os.write(fd, b"/quit\r")
        end = time.monotonic() + 20
        while time.monotonic() < end:
            if select.select([fd], [], [], 0.05)[0]:
                try:
                    os.read(fd, 65536)
                except OSError:
                    pass
            if os.waitpid(pid, os.WNOHANG)[0]:
                return
        sys.exit("ask did not quit")
    finally:
        os.close(fd)
        server.httpd.shutdown()


def traced(binary, symbols, starts, drive):
    """The functions `drive` runs ask through, in the order they first ran."""
    directory = tempfile.mkdtemp(prefix="ask-order-coverage-")
    drive(binary, directory)
    dumps = glob.glob(os.path.join(directory, "*.sancov"))
    if len(dumps) != 1:
        sys.exit(f"expected one coverage dump, found {dumps}")
    data = open(dumps[0], "rb").read()
    order = []
    for address in struct.unpack(f"<{(len(data) - 8) // 8}Q", data[8:]):
        index = bisect.bisect_right(starts, address) - 1
        if index < 0:
            continue
        name = symbols[index][1]
        # The sanitizer's own functions are not in the build that ships.
        if "asan" not in name and "sanitizer" not in name:
            order.append(name)
    return order


def main():
    if "--check" in sys.argv:
        return check()
    binary = build()
    symbols = names_in(binary)
    starts = [address for address, _ in symbols]
    # Startup as the idle budget measures it (signed out) first, so the idle figure keeps its gain; then what a first turn adds.
    runs = [run] if "--startup-only" in sys.argv else [run, first_turn]
    order, seen = [], set()
    for drive in runs:
        for name in traced(binary, symbols, starts, drive):
            if name not in seen:
                seen.add(name)
                order.append(name)
    with open(ORDER, "w") as file:
        file.write("\n".join(order) + "\n")
    print(f"{len(order)} functions written to {ORDER}")


if __name__ == "__main__":
    main()
