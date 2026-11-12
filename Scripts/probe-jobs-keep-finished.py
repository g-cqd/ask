#!/usr/bin/env python3
"""`jobs.keepFinished` (the owner, 2026-11-06; t232) through the real binary, a PTY and a local fake provider.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-jobs-keep-finished.py .build/release/ask

With a limit of 1, the model runs two commands to the background and waits for each to finish, then starts a third. Asked about
the first, the job tool says it finished and was let go, naming the setting; asked about the second, it still answers. Hermetic: no
window, credentials or clipboard.
"""
import importlib.util
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("fold_probe", os.path.join(HERE, "probe-folding.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


def main():
    with tempfile.TemporaryDirectory() as root:
        project, config = root + "/project", root + "/config"
        os.makedirs(project)
        os.makedirs(config + "/ask")
        with open(config + "/ask/config.json", "w") as file:
            json.dump({"ui": {"inputPrefix": "ask> "}, "jobs": {"keepFinished": 1}}, file)
        turn = probe.agent.turn
        # Each runs past the one second it is given, so it goes to the background, and is waited on to its end.
        slow = "sleep 1.5; echo {}"
        server = probe.agent.Server([
            turn([("call", "t1", "bash", {"command": slow.format("FIRST"), "yield_seconds": 1})], "tool_use"),
            turn([("call", "t2", "job", {"job": "job-1", "action": "wait", "timeout_seconds": 10})], "tool_use"),
            turn([("call", "t3", "bash", {"command": slow.format("SECOND"), "yield_seconds": 1})], "tool_use"),
            turn([("call", "t4", "job", {"job": "job-2", "action": "wait", "timeout_seconds": 10})], "tool_use"),
            turn([("call", "t5", "bash", {"command": slow.format("THIRD"), "yield_seconds": 1})], "tool_use"),
            turn([("call", "t6", "job", {"job": "job-1", "action": "status"})], "tool_use"),
            turn([("call", "t7", "job", {"job": "job-2", "action": "status"})], "tool_use"),
            turn([("text", "ALL ASKED")], "end_turn"),
        ])
        environment = probe.agent.environment(root + "/state", server.url, config=config)
        environment.update(TERM="xterm-256color")
        terminal = None
        try:
            terminal = probe.Terminal(project, environment, columns=140, rows=40)
            terminal.until(lambda: "ask>" in terminal.text())
            terminal.send(b"run them\r")
            deadline = probe.time.monotonic() + 40
            while b"ALL ASKED" not in terminal.raw and probe.time.monotonic() < deadline:
                terminal.pump()
            results = probe.agent.tool_results(server)
            first, second = results.get("t6", ""), results.get("t7", "")
            probe.check("the first finished job was let go, and the job tool says so, naming the setting",
                        "let go" in first and "jobs.keepFinished" in first)
            probe.check("the most recent finished one is still known", "job-2 status: exit 0" in second)
            print("INFO", json.dumps(first)[:160], "|", json.dumps(second)[:160])
        except AssertionError:
            if terminal:
                print(terminal.text(), file=sys.stderr)
            raise
        finally:
            if terminal:
                terminal.close()
            server.httpd.shutdown()


if __name__ == "__main__":
    main()
