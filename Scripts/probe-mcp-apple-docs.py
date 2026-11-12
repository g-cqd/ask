#!/usr/bin/env python3
"""Probe resources against the live apple-docs server (roadmap 0067) through the real binary, a PTY and a local fake provider; it needs
the network.

Scripts/probe-mcp-apple-docs.py .build/release/ask

`@apple-docs:` lists the server's resources and its templates; choosing the page template writes `apple-docs://doc/` for the person to
finish; the finished `@apple-docs:apple-docs://doc/swiftui/view` is read when the message is sent and reaches the model after the typed
line, while the screen shows the line alone. Then the model's `server_resource` call reads the same page.
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("mcp_screen", os.path.join(HERE, "probe-mcp-screen.py"))
saved = sys.argv
sys.argv = [saved[0], saved[1]]
ms = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ms)
sys.argv = saved
pp = ms.pp


def main():
    binary = os.path.abspath(sys.argv[1])
    servers = lambda project: {"mcp": {"apple-docs": {"url": "https://apple-docs-mcp.everest.mt/mcp"}}}
    with pp.Session(binary, [pp.short_answer("Read the page.")], settings=servers) as session:
        terminal = session.terminal
        ms.type_text(terminal, "Explain @apple-docs:apple-docs://d")
        terminal.until(lambda: "· template" in terminal.text())
        shown = ms.screen(terminal)
        pp.check("the picker lists the server's templates", "apple-docs://doc/{+key}" in shown)
        # Narrow to the page template, then choose it.
        ms.type_text(terminal, "oc/")
        terminal.until(lambda: "apple-docs://doc/{+key}" in terminal.text())
        ms.press(terminal, b"\r")
        terminal.until(lambda: "ask> Explain @apple-docs:apple-docs://doc/" in terminal.text() and "{+key}" not in terminal.text().split("ask>")[-1])
        pp.check("choosing it writes the fixed part, to be finished",
                 terminal.text().split("ask>")[-1].split("\n")[0].strip().endswith("@apple-docs:apple-docs://doc/"))
        ms.type_text(terminal, "swiftui/view please")
        ms.press(terminal, b"\r")
        terminal.until(lambda: "Read the page." in terminal.text())
        sent = next((t for t in session.sent_texts() if t.startswith("Explain @apple-docs:")), "")
        pp.check("the finished URI reached the model with the page read from the live server",
                 "--- resource apple-docs:apple-docs://doc/swiftui/view ---" in sent and "View" in sent and len(sent) > 500)
        pp.check("the screen shows the typed line alone", "--- resource" not in ms.screen(terminal))
    # The model's side: the server_resource tool reads the same page from the live server.
    call = ("call", "r1", "server_resource", {"server": "apple-docs", "uri": "apple-docs://doc/swiftui/view"})
    with pp.Session(binary, [pp.probe.agent.turn([call], "tool_use"), pp.short_answer("Got it.")], settings=servers) as session:
        ms.send(session, "Read the View page.", "Got it.")
        results = [block.get("content") for request in session.server.requests for message in request["body"]["messages"]
                   for block in (message["content"] if isinstance(message["content"], list) else []) if block.get("type") == "tool_result"]
        text = " ".join(r if isinstance(r, str) else " ".join(part.get("text", "") for part in r) for r in results)
        pp.check("the server_resource tool reads the page from the live server", "View" in text and len(text) > 500)
    print(f"{len(pp.checks)} checks passed")


if __name__ == "__main__":
    main()
