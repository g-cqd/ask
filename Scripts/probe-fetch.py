#!/usr/bin/env python3
"""Roadmap 0237: `fetch` live. A scripted model calls fetch on a public page (example.com, unless a URL is given) through `ask -p --yes`;
the tool's result must hold the page as Markdown between the untrusted markers.

Scripts/probe-fetch.py .build/release/ask [URL]
"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("agent_probe", os.path.join(here, "probe-agent-run.py"))
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)


def main():
    binary = os.path.abspath(sys.argv[1])
    url = sys.argv[2] if len(sys.argv) > 2 else "https://example.com/"
    root = tempfile.mkdtemp()
    project = os.path.join(root, "project")
    os.mkdir(project)
    server = agent.Server([agent.turn([("call", "f1", "fetch", {"url": url})], "tool_use"),
                           agent.turn([("text", "Read it.")], "end_turn")])
    run = subprocess.run([binary, "-p", "Read the page.", "--json", "--yes"], cwd=project,
                         env=agent.environment(os.path.join(root, "state"), server.url), capture_output=True, text=True, timeout=120)
    events = [json.loads(line) for line in run.stdout.split("\n") if line.strip()]
    result = next((e for e in events if e.get("type") == "tool_result"), {})
    content = result.get("content", "")
    results = [
        agent.check("exits 0", run.returncode == 0, run.stderr[-400:]),
        agent.check("the tool ran without error", result and not result.get("is_error"), content[:300]),
        agent.check("the page is between the untrusted markers", "<untrusted-web-content>" in content and content.rstrip().endswith("</untrusted-web-content>"), content[:300]),
        agent.check("the page reads as Markdown text", "Example Domain" in content if "example.com" in url else len(content) > 200, content[:400]),
    ]
    server.httpd.shutdown()
    print("PASS" if all(results) else "FAIL")
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
