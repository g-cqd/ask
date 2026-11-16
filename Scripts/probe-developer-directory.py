#!/usr/bin/env python3
"""A run kept to its workspace for reading can still read the Xcode this Mac uses, whatever it is called and wherever it is.

    python3 Scripts/probe-developer-directory.py .build/release/ask

`cc`, `git`, `python3` and `swift` in /usr/bin go through xcrun, which loads libxcrun.dylib from the developer directory. CI's runner
has no /Applications/Xcode.app: its Xcode is /Applications/Xcode_26.6.app, and under `--read workspace` every such command ended with
"unable to load libxcrun … file system sandbox blocked open()".

Here the developer directory is a stand-in application in the home directory, holding xcrun's library and nothing else, named by
DEVELOPER_DIR. xcrun finds no tools in it, which is not the question: the question is whether its library could be opened.
"""
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile

BINARY = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".build/release/ask")
sys.argv = [sys.argv[0], BINARY]
here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("agent_probe", os.path.join(here, "probe-agent-run.py"))
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)


def said(developer, extra):
    """What the command `xcrun --find cc` printed in a run whose developer directory is `developer`."""
    with tempfile.TemporaryDirectory() as root:
        project = os.path.join(root, "project")
        os.makedirs(project)
        server = agent.Server([agent.turn([("tool", "t1", "xcrun --find cc 2>&1; echo ran")], "tool_use"),
                               agent.turn([("text", "done")], "end_turn")])
        env = agent.environment(os.path.join(root, "state"), server.url)
        env["DEVELOPER_DIR"] = developer
        subprocess.run([BINARY, "-p", "run it", *extra], cwd=project, env=env, capture_output=True, text=True, timeout=120,
                       stdin=subprocess.DEVNULL)
        server.httpd.shutdown()
        if len(server.requests) < 2:
            return ""
        return json.dumps([block for message in server.requests[1]["body"]["messages"]
                           for block in (message["content"] if isinstance(message["content"], list) else [])
                           if block.get("type") == "tool_result"])


def main():
    if sys.platform != "darwin":
        print("PASS (nothing to probe: xcrun is Darwin's)")
        return 0
    real = subprocess.run(["xcode-select", "-p"], capture_output=True, text=True).stdout.strip()
    library = os.path.join(real, "usr", "lib", "libxcrun.dylib")
    if not os.path.exists(library):
        print(f"PASS (nothing to probe: {library} is not there, so the developer tools are not an Xcode)")
        return 0
    # In the home directory: what a run kept to its workspace cannot read, as it cannot read an Xcode that is not Xcode.app.
    root = tempfile.mkdtemp(prefix=".ask-probe-developer-", dir=os.path.expanduser("~"))
    try:
        developer = os.path.join(root, "Xcode_0.0.app", "Contents", "Developer")
        os.makedirs(os.path.join(developer, "usr", "lib"))
        shutil.copy(library, os.path.join(developer, "usr", "lib", "libxcrun.dylib"))
        kept = said(developer, ["--read", "workspace"])
        anywhere = said(developer, [])
    finally:
        shutil.rmtree(root, ignore_errors=True)
    blocked = "sandbox blocked" in kept or "unable to load libxcrun" in kept
    results = [
        agent.check("the experiment ran: the command ran in both runs, and xcrun used the stand-in",
                    "ran" in kept and "ran" in anywhere and "Xcode_0.0.app" in anywhere, (kept[:400], anywhere[:400])),
        agent.check("kept to its workspace for reading, the run opens xcrun's library in the developer directory", not blocked,
                    kept[:600]),
        agent.check("and xcrun then says what it says in a run that reads anywhere", kept == anywhere, (kept[:400], anywhere[:400])),
    ]
    print("PASS" if all(results) else "FAIL")
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
