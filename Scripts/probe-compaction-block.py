#!/usr/bin/env python3
"""A compaction is a block (roadmap 0105) through the real binary, a scripted provider and a PTY.

ASK_PYTE=/tmp/ask-pty/lib Scripts/probe-compaction-block.py .build/release/ask

`/compact` with nothing to summarise ends as a failed block, folded, with no notice, and a click opens it onto the reason. (The done
path is covered by CompactionBlockTests.) The binary is the one probe-folding takes: .build/release/ask. pyte, not a physical terminal.
"""
import importlib.util, os, sys, tempfile
spec = importlib.util.spec_from_file_location("pf", os.path.join(os.path.dirname(os.path.abspath(__file__)), "probe-folding.py")); pf = importlib.util.module_from_spec(spec); spec.loader.exec_module(pf)
agent = pf.agent
with tempfile.TemporaryDirectory() as root:
    project, config = root + "/p", root + "/c"; os.makedirs(project); os.makedirs(config + "/ask")
    open(config + "/ask/config.json", "w").write('{"ui":{"inputPrefix":"ask> ","separator":"off","fold":{"tools":true}}}')
    server = agent.Server([agent.turn([("text", "ANSWER 1")], "end_turn")])
    env = agent.environment(root + "/s", server.url, config=config); env.update(TERM="xterm-256color", TERM_PROGRAM="ghostty", LANG="en_US.UTF-8")
    t = pf.Terminal(project, env)
    try:
        t.until(lambda: "ask>" in t.text()); t.send(b"hello there\r"); t.until(lambda: "ANSWER 1" in t.text())
        t.send(b"/compact\r"); t.until(lambda: "compact · earlier messages" in t.text()); t.repaint()
        pf.check("a failed compaction is a block with a cross", any("compact · earlier messages" in l and l.rstrip().endswith("✗") for l in t.screen.display))
        pf.check("and no notice says it", "Could not compact" not in t.text())
        row = t.row("compact · earlier"); t.send(f"\x1b[<0;4;{row+1}M\x1b[<0;4;{row+1}m".encode()); t.until(lambda: "Could not" in t.text() or "nothing" in t.text().lower() or "No " in t.text()); t.repaint()
        pf.check("a click opens the block onto the reason", "nothing before the recent messages" in t.text())
    finally:
        t.close(); server.httpd.shutdown()
