#!/usr/bin/env python3
"""Live PTY regression: /resume and bare --resume select without opening another session.
Usage: python3 Scripts/probe-session-picker.py .build/release/ask
"""
import importlib.util
import os
import subprocess
import sys
import tempfile

spec = importlib.util.spec_from_file_location(
    "interactive", os.path.join(os.path.dirname(__file__), "probe-interactive.py"))
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
p.ROWS, p.COLUMNS = 40, 120


def main():
    with tempfile.TemporaryDirectory() as root:
        project, state, config = [os.path.join(root, name) for name in ("project", "state", "config")]
        os.makedirs(project)
        os.makedirs(os.path.join(config, "ask"))
        server = p.agent.Server([p.agent.turn([("text", "SEEDED " + name)], "end_turn") for name in ("ALPHA", "BETA")])
        results = []
        try:
            for name in ("ALPHA", "BETA"):
                seeded = subprocess.run([p.ASK, "-p", name], cwd=project,
                                        env=p.agent.environment(state, server.url, config), capture_output=True, timeout=20)
                assert seeded.returncode == 0, seeded.stderr
            original = set(p.agent.sessions(state))
            for arguments in ((), ("--resume",), ("-r",), ("--resume", "--verbose")):
                screen = p.Screen(server.url, project, state=state, config=config, arguments=arguments)
                try:
                    assert screen.until("────"), "initial screen missing"
                    if not arguments:
                        screen.type("/resume\r")
                    shown = screen.until("ALPHA", 5) and screen.until("BETA", 5)
                    results.append(p.check(str(arguments or "/resume") + " opens searchable session choices", shown))
                    if not shown:
                        continue
                    screen.type("ALPHA")
                    screen.until("\x00", 0.2)
                    screen.type("\r")
                    resumed = screen.until("Resumed session", 5)
                    results.append(p.check("Enter selects the filtered session and restores its history",
                                           resumed and "SEEDED ALPHA" in screen.screen.text()
                                           and "SEEDED BETA" not in screen.screen.text()))
                finally:
                    screen.type("\x03\x03")
                    screen.finish(3)
            results.append(p.check("opening and selecting from pickers does not create sessions",
                                   set(p.agent.sessions(state)) == original))
            named = p.Screen(server.url, project, state=state, config=config,
                             arguments=("--resume", next(iter(original))))
            try:
                results.append(p.check("an explicit CLI session still restores history directly", named.until("SEEDED")))
            finally:
                named.type("\x03\x03")
                named.finish(3)
            empty = p.Screen(server.url, tempfile.mkdtemp(), state=state, config=config, arguments=("--resume",))
            try:
                results.append(p.check("an empty project explains that there are no sessions", empty.until("No sessions in this project yet.")))
            finally:
                empty.type("\x03\x03")
                empty.finish(3)
            invalid = subprocess.run([p.ASK, "--resume", "-p", "hello"], cwd=project,
                                     env=p.agent.environment(state, server.url, config), capture_output=True, timeout=20)
            results.append(p.check("bare resume cannot request a picker in print mode", invalid.returncode != 0))
            return all(results)
        finally:
            server.httpd.shutdown()


if __name__ == "__main__":
    sys.exit(0 if main() else 1)
