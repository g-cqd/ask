#!/usr/bin/env python3
"""Which Markdown do assistants write? Counts only: no text is kept or printed. Roadmap 0065, phase 0.

Reads the local agent session logs that probe-ui-content-sizes.py reads (Claude Code, Codex, Pi), takes the
assistant's text blocks, parses each with markdown-it-py (CommonMark, plus tables, strikethrough and bare-URL
links), and counts constructs, so the scope of the parser is cut by what occurs and not by taste.

  python3 -m venv /tmp/mdvenv && /tmp/mdvenv/bin/pip install markdown-it-py linkify-it-py
  /tmp/mdvenv/bin/python probe-markdown-constructs.py [--limit N] OUT.json

What it cannot say: markdown-it-py is the oracle here, not the parser ask will ship, so a construct it reads
differently from CommonMark's reference (cmark) is counted as it reads it.
"""
import importlib.util, json, os, re, statistics, sys, time
from collections import Counter

from markdown_it import MarkdownIt

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("sizes", os.path.join(HERE, "probe-ui-content-sizes.py"))
sizes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sizes)

PARSER = MarkdownIt("commonmark", {"linkify": True}).enable(["table", "strikethrough", "linkify"])
TASK = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+\[[ xX]\]\s", re.M)
MATH = re.compile(r"\$\$.+?\$\$|\\\(.+?\\\)|\\\[.+?\\\]", re.S)
FOOTNOTE = re.compile(r"^\[\^[^\]]+\]:", re.M)
CONTROL = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")
MERMAID_KIND = re.compile(r"^\s*(?:%%[^\n]*\n\s*)*([A-Za-z][A-Za-z0-9-]*)")
SCHEME = re.compile(r"^([A-Za-z][A-Za-z0-9+.-]*):")


def scheme(href):
    match = SCHEME.match(href)
    if match:
        return match.group(1).lower()
    return "fragment" if href.startswith("#") else "relative"


def census(text, c):
    c["messages"] += 1
    c["bytes"] += len(text.encode("utf-8", "replace"))
    lines = text.split("\n")
    c["longest_line_bytes"] = max(c["longest_line_bytes"], max(len(l.encode("utf-8", "replace")) for l in lines))
    c["longest_message_bytes"] = max(c["longest_message_bytes"], len(text.encode("utf-8", "replace")))
    if CONTROL.search(text):
        c["messages_with_control_bytes"] += 1
    if "\x1b" in text:
        c["messages_with_escape"] += 1
    if not text.isascii():
        c["messages_non_ascii"] += 1
    for name, pattern in (("task_items", TASK), ("math", MATH), ("footnotes", FOOTNOTE)):
        found = len(pattern.findall(text))
        c[name] += found
        c["messages_with_" + name] += 1 if found else 0
    tokens = PARSER.parse(text)
    constructs = 0
    list_depth = quote_depth = 0
    for index, t in enumerate(tokens):
        kind = t.type
        if kind == "heading_open":
            c["heading_h" + t.tag[1]] += 1
        elif kind in ("bullet_list_open", "ordered_list_open"):
            c[kind.replace("_open", "")] += 1
            list_depth += 1
            c["max_list_depth"] = max(c["max_list_depth"], list_depth)
        elif kind in ("bullet_list_close", "ordered_list_close"):
            list_depth -= 1
        elif kind == "blockquote_open":
            c["blockquote"] += 1
            quote_depth += 1
            c["max_quote_depth"] = max(c["max_quote_depth"], quote_depth)
        elif kind == "blockquote_close":
            quote_depth -= 1
        elif kind == "fence":
            language = t.info.strip().split(" ")[0].lower() or "(none)"
            c["fence"] += 1
            c["lang:" + language] += 1
            body = t.content.count("\n")
            c["fence_lines"].append(body)
            if language == "mermaid":
                found = MERMAID_KIND.match(t.content)
                c["mermaid:" + (found.group(1) if found else "(unknown)")] += 1
        elif kind == "code_block":
            c["indented_code"] += 1
        elif kind == "table_open":
            c["table"] += 1
            columns, rows = 0, 0
            for later in tokens[index + 1:]:
                if later.type == "table_close":
                    break
                if later.type == "th_open":
                    columns += 1
                elif later.type == "tr_open":
                    rows += 1
            c["table_columns"].append(columns)
            c["table_rows"].append(rows)
        elif kind == "hr":
            c["hr"] += 1
        elif kind == "html_block":
            c["html_block"] += 1
        elif kind == "inline":
            for child in t.children or []:
                k = child.type
                if k == "link_open":
                    href = child.attrGet("href") or ""
                    c["link_" + ("bare" if child.markup == "linkify" else "autolink" if child.markup == "autolink" else "inline")] += 1
                    c["scheme:" + scheme(href)] += 1
                elif k in ("strong_open", "em_open", "s_open"):
                    c[k.replace("_open", "")] += 1
                elif k == "code_inline":
                    c["code_inline"] += 1
                elif k == "image":
                    c["image"] += 1
                elif k == "hardbreak":
                    c["hardbreak"] += 1
                elif k == "html_inline":
                    c["html_inline"] += 1
    # Block markup: anything but a single plain paragraph.
    if len(tokens) > 3 or (tokens and tokens[0].type != "paragraph_open"):
        c["messages_with_block_markup"] += 1
    c["max_token_level"] = max(c["max_token_level"], max((t.level for t in tokens), default=0))


def summarize(counter):
    out = {}
    for key, value in counter.items():
        if isinstance(value, list):
            ordered = sorted(value)
            out[key] = {
                "count": len(ordered),
                "median": statistics.median(ordered) if ordered else 0,
                "p95": ordered[int(len(ordered) * 0.95)] if ordered else 0,
                "max": ordered[-1] if ordered else 0,
            }
        else:
            out[key] = value
    return dict(sorted(out.items()))


def main():
    limit = int(sys.argv[sys.argv.index("--limit") + 1]) if "--limit" in sys.argv else 10**9
    out = sys.argv[-1]
    roots = {"claude": "~/.claude/projects", "codex": "~/.codex/sessions", "pi": "~/.pi/agent/sessions"}
    result = {}
    for source, root in roots.items():
        counter = Counter({"fence_lines": [], "table_columns": [], "table_rows": []})
        started, fs = time.time(), sizes.files(root, limit)
        for path in fs:
            with open(path, errors="replace") as handle:
                for line in handle:
                    try:
                        event = json.loads(line)
                    except ValueError:
                        continue
                    for role, text, _ in sizes.texts(source, event):
                        if role == "assistant" and text:
                            census(text, counter)
        result[source] = dict(files=len(fs), seconds=round(time.time() - started, 1), **summarize(counter))
        print(source, len(fs), "files", counter["messages"], "assistant messages", flush=True)
    json.dump(result, open(out, "w"), indent=1)


if __name__ == "__main__":
    main()
