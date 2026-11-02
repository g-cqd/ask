#!/usr/bin/env python3
"""Whether configured MCP servers cost ask's first frame anything (roadmap 0114's budget): cold start and idle memory with no servers,
then with three (the fixture, one that cannot start, one that waits five seconds before it reads), measured as measure-budgets.py
measures them, from outside over a PTY. Servers connect with the first message (roadmap 0143), so none may be running at the first frame.

    python3 Scripts/measure-mcp-start.py [.build/release/ask] [runs]
"""
import importlib.util, json, os, statistics, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
BINARY = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".build/release/ask")
RUNS = int(sys.argv[2]) if len(sys.argv) > 2 else 15
FIXTURE = os.path.join(HERE, "..", "Tests", "AskMCPTests", "Fixtures", "fixture-server.py")
spec = importlib.util.spec_from_file_location("budgets", os.path.join(HERE, "measure-budgets.py"))
saved, sys.argv = sys.argv, [sys.argv[0], BINARY]
mb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mb)
sys.argv = saved
SERVERS = {
    "fx": {"command": "python3", "args": [FIXTURE]},
    "ghost": {"command": "/nonexistent/mcp-server"},
    "slow": {"command": "sh", "args": ["-c", "sleep 5; exec python3 " + FIXTURE]},
}


def configure(servers):
    os.makedirs(mb.ISOLATED_CONFIG + "/ask", exist_ok=True)
    with open(mb.ISOLATED_CONFIG + "/ask/config.json", "w") as file:
        json.dump({"mcp": servers} if servers else {}, file)


def running():
    return len(subprocess.run(["pgrep", "-f", FIXTURE], capture_output=True, text=True).stdout.split())


def one(servers):
    configure(servers)
    t0 = time.monotonic()
    pid, fd = mb.spawn()
    try:
        hit = mb.read_frame_showing(fd, mb.PROMPT, 10.0)
        if hit is None:
            return None
        cold = (hit[0] - t0) * 1000.0
        time.sleep(0.25)
        return cold, mb.rss_kb(pid), running()
    finally:
        os.write(fd, b"\x03")
        time.sleep(0.05)
        os.close(fd)
        try:
            os.waitpid(pid, 0)
        except ChildProcessError:
            pass


def main():
    results = {}
    # Interleaved, so a slow moment of the machine falls on both sides alike.
    for _ in range(RUNS):
        for name, servers in (("none", {}), ("three servers", SERVERS)):
            got = one(servers)
            if got:
                results.setdefault(name, []).append(got)
    for name, runs in results.items():
        colds = sorted(r[0] for r in runs)
        print("%-14s %2d runs  cold start median %6.2f ms  p95 %6.2f ms  idle RSS median %6.0f KiB  servers running at the frame: %d"
              % (name, len(runs), statistics.median(colds), colds[int(len(colds) * 0.95) - 1 if len(colds) > 1 else 0],
                 statistics.median(r[1] for r in runs), max(r[2] for r in runs)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
