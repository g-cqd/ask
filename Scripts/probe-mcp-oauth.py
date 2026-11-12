#!/usr/bin/env python3
"""Probe the sign-in to an MCP server behind OAuth (roadmap 0067) through the real binary, a PTY, a local fake provider and the fixture
OAuth server; no browser opens: with `ASK_NO_BROWSER` the address is only shown, and the probe follows it as a browser that approves at
once.

Scripts/probe-mcp-oauth.py .build/release/ask

The first message connects the server, which refuses; the screen asks whether to sign in; yes registers ask, sends the person to
approve, takes the code back on this machine, exchanges it with PKCE, saves the tokens and connects the server: `/mcp` says it is ready.
"""
import importlib.util
import os
import re
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("mcp_screen", os.path.join(HERE, "probe-mcp-screen.py"))
saved = sys.argv
sys.argv = [saved[0], saved[1]]
ms = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ms)
sys.argv = saved
pp = ms.pp
FIXTURE = os.path.join(HERE, "..", "Tests", "AskMCPTests", "Fixtures", "oauth-server.py")


def main():
    binary = os.path.abspath(sys.argv[1])
    scratch = tempfile.mkdtemp(prefix="ask-oauth-probe-")
    port_file = os.path.join(scratch, "port")
    server = subprocess.Popen([sys.executable, FIXTURE, port_file])
    try:
        while not os.path.exists(port_file) or not open(port_file).read():
            time.sleep(0.05)
        port = open(port_file).read()
        authorize = re.compile(rf"http://127\.0\.0\.1:{port}/authorize\S+")
        servers = lambda project: {"mcp": {"secure": {"url": f"http://127.0.0.1:{port}/mcp"}}}
        with pp.Session(binary, [pp.short_answer("ANSWER ONE")], settings=servers) as session:
            terminal = session.terminal
            terminal.resize(400, 30)  # the address on one row, to read it whole
            ms.send(session, "hello", "ANSWER ONE")
            terminal.until(lambda: "needs you to sign in" in terminal.text())
            pp.check("the refusal is asked about on the screen", "Open the browser to sign in now?" in ms.screen(terminal))
            ms.press(terminal, b" ")
            ms.press(terminal, b"\r")
            # The whole address: its last part, the resource (the fixture asks for no scope), drawn.
            terminal.until(lambda: "resource=" in (authorize.search(terminal.text()) or [""])[0])
            pp.check("no browser: the address is only shown", "Open this address in a browser" in terminal.text())
            subprocess.run(["/usr/bin/curl", "-sL", "-o", "/dev/null", authorize.search(terminal.text()).group(0)], check=True)
            terminal.until(lambda: "Signed in to secure" in terminal.text())
            flat = " ".join(line.strip() for line in ms.screen(terminal).split("\n"))
            pp.check("the address to approve is shown", f"http://127.0.0.1:{port}/authorize" in flat)
            pp.check("the sign-in is said", "Signed in to secure: it connects now." in flat)
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                ms.send(session, "/mcp", "secure:")
                if "secure: ready, 1 of 1 tool offered" in ms.screen(terminal):
                    break
                time.sleep(0.3)
            pp.check("with the token, the server connects and offers its tool", "secure: ready, 1 of 1 tool offered" in ms.screen(terminal))
    finally:
        server.kill()
    print(f"{len(pp.checks)} checks passed")


if __name__ == "__main__":
    main()
