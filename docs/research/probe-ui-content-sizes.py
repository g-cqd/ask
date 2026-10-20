#!/usr/bin/env python3
"""How big are the things ask's screen would fold or bound? Counts only: no text is kept or printed.

Reads local agent session logs (Claude Code, Codex, Pi) and measures, per source:
  - fenced code blocks in assistant messages: lines per block
  - user prompts: lines per prompt, and display rows when wrapped at 100 columns
  - images: how many messages carry one

  python3 probe-ui-content-sizes.py [--limit N] OUT.json
"""
import json, math, os, re, sys, time

FENCE = re.compile(r"```[^\n]*\n(.*?)```", re.S)


def files(root, limit):
    found = []
    for directory, _, names in os.walk(os.path.expanduser(root)):
        found += [os.path.join(directory, n) for n in names if n.endswith(".jsonl")]
    found.sort(key=os.path.getsize, reverse=True)
    return found[:limit]


def texts(source, event):
    """Yield (role, text, image_count) for each message in one event of the given source."""
    if source == "claude":
        if event.get("type") not in ("user", "assistant"):
            return
        message = event.get("message") or {}
        content = message.get("content")
        role = event["type"]
        if isinstance(content, str):
            yield role, content, 0
        elif isinstance(content, list):
            images = sum(1 for b in content if isinstance(b, dict) and b.get("type") == "image")
            parts = [b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"]
            if parts or images:
                yield role, "\n".join(parts), images
    elif source == "pi":
        if event.get("type") != "message":
            return
        message = event.get("message") or {}
        role, content = message.get("role"), message.get("content")
        if isinstance(content, str):
            yield role, content, 0
        elif isinstance(content, list):
            images = sum(1 for b in content if isinstance(b, dict) and b.get("type") == "image")
            parts = [b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"]
            yield role, "\n".join(parts), images
    elif source == "codex":
        payload = event.get("payload") or {}
        if event.get("type") != "response_item" or payload.get("type") != "message":
            return
        role, content = payload.get("role"), payload.get("content")
        if isinstance(content, list):
            parts = [b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") in ("input_text", "output_text")]
            images = sum(1 for b in content if isinstance(b, dict) and "image" in str(b.get("type", "")))
            yield role, "\n".join(parts), images


def rows(text, width=100):
    return sum(max(1, math.ceil(len(line) / width)) for line in text.split("\n"))


def main():
    limit = int(sys.argv[sys.argv.index("--limit") + 1]) if "--limit" in sys.argv else 10**9
    out = sys.argv[-1]
    roots = {"claude": "~/.claude/projects", "codex": "~/.codex/sessions", "pi": "~/.pi/agent/sessions"}
    result = {}
    for source, root in roots.items():
        code, prompt_lines, prompt_rows, messages, image_msgs, started = [], [], [], 0, 0, time.time()
        fs = files(root, limit)
        for path in fs:
            with open(path, errors="replace") as f:
                for line in f:
                    try:
                        event = json.loads(line)
                    except ValueError:
                        continue
                    for role, text, images in texts(source, event):
                        messages += 1
                        image_msgs += 1 if images else 0
                        if role == "assistant":
                            for block in FENCE.findall(text):
                                code.append(block.count("\n") + (0 if block.endswith("\n") else 1))
                        elif role == "user" and text and not text.lstrip().startswith("<"):
                            prompt_lines.append(text.count("\n") + 1)
                            prompt_rows.append(rows(text))
        result[source] = dict(files=len(fs), messages=messages, messages_with_images=image_msgs,
                              code_blocks=sorted(code), prompt_lines=sorted(prompt_lines), prompt_rows=sorted(prompt_rows),
                              seconds=round(time.time() - started, 1))
        print(source, len(fs), "files", messages, "messages", len(code), "code blocks", len(prompt_lines), "prompts", flush=True)
    json.dump(result, open(out, "w"))


if __name__ == "__main__":
    main()
