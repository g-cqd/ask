#!/usr/bin/env python3
"""Every kind of block ask draws, in your own terminal, against a scripted model: nothing reaches a real provider.

    python3 Scripts/showcase.py [.build/release/ask] [--appearance light|dark|auto]

Type a scene's number as the prompt (1 to 8) and look at what the guide printed before the start says to look at; `/quit` leaves. Each
scene goes on by itself when a tool returns, so answering no, or stopping a command, never puts the script out of step. ask runs in a
scratch project with its own configuration, state and HOME, all removed at the end (development/research/priorities-2026-10-30.md, item 2).
"""

import json, os, shutil, subprocess, sys, tempfile, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CODE = "\n".join(["import Foundation", "", "/// Greets everyone it is given.", "struct Greeter {", "    let names: [String]", "",
                  "    func run() {", "        for name in names {", "            print(\"Hello, \\(name)!\")", "        }", "    }", "}"]
                 + [f"// line {n}: long enough to fold" for n in range(13, 31)])
MARKDOWN = f"""# Markdown, drawn

Some **bold**, some *emphasis*, `inline code`, and ~~struck~~ text. Links open on a click: https://www.swift.org, \
someone@example.com, and files in the project: README.md and Sources/Demo/main.swift:3.

- a list
  - nested once
- [x] a task done
- [ ] a task to do

> A quotation, set apart.

| Setting | Default | Notes |
|---|:-:|---|
| `ui.tint` | on | tinted blocks |
| `ui.markdown` | on | this table |

```swift
{CODE}
```

Click the code block's header, or press Ctrl+G, to unfold it."""
THINKING = ("The person asked to see reasoning. I will think in a few lines:\n\n1. reasoning is folded to one line by default;\n"
            "2. Ctrl+T or a click unfolds it;\n3. it is drawn as Markdown, **like this**.")
SCRIPT = "python3 - <<'PY'\nimport platform\nfor key in ('system', 'release', 'machine'):\n    value = getattr(platform, key)()\n" \
         "    print(f'{key:>8}: {value}')\nprint('a multi-line command, folded in the question')\nPY"

SCENES = {
    "1": ("Markdown: headings, emphasis, a list, a quote, a table, links, a long code block (folded)",
          [[("text", MARKDOWN)]]),
    "2": ("Reasoning: a folded thinking block, then the answer",
          [[("thinking", THINKING), ("text", "That was the reasoning block: **folded** by default, Ctrl+T unfolds it.")]]),
    "3": ("Commands: a short one, a long output (folded), a failure, a header with a timeout",
          [[("bash", {"command": "ls -la"})], [("bash", {"command": "seq 1 200"})],
           [("bash", {"command": "ls /no/such/place"})], [("bash", {"command": "sleep 1; echo slow", "timeout_seconds": 300})],
           [("text", "Four commands: the second folded, the third failed, the fourth has `timeout 5 min` in its header.")]]),
    "4": ("Approvals: a multi-line command (Ctrl+O shows all of it), then a write",
          [[("bash", {"command": SCRIPT})], [("write", {"path": "notes.md", "content": "# Notes\n\nWritten by the showcase.\n"})],
           [("text", "Both questions came in the section above the input; neither left a block behind.")]]),
    "5": ("Stopping: a command that waits a minute; press Esc twice (or Ctrl+C) to stop it",
          [[("bash", {"command": "echo waiting; sleep 60; echo done"})], [("text", "The wait ran to its end.")]]),
    "6": ("A background job: ticks for 30 seconds; the status line counts it, /tasks shows it",
          [[("bash", {"command": "for i in $(seq 1 30); do echo tick $i; sleep 1; done", "yield_seconds": 2})],
           [("text", "The command moved to the background: the status line counts it until it ends, and /tasks shows it.")]]),
    "7": ("A dropped answer: the connection breaks mid-reply, and ask asks the model to carry on",
          [[("text", "This answer starts, and then the connection ")], [("text", "came back, and the answer went on where it stopped.")]]),
    "8": ("Streaming: a long reply arriving word by word, with the spinner",
          [[("text", " ".join(["Streaming arrives a few words at a time, the way a real model sends it."] * 12))]]),
}
DROPPED = {"7": 0}  # scene: the step whose response is cut short


def event(kind, **fields):
    return f"event: {kind}\ndata: {json.dumps(dict(type=kind, **fields))}\n\n".encode()


def response(blocks, cut=False):
    """The response's events, in pieces small enough to show streaming; `cut` stops before the message ends."""
    pieces = [event("message_start", message={"id": "m", "model": "showcase", "usage": {"input_tokens": 1, "output_tokens": 1}})]
    for index, (kind, value) in enumerate(blocks):
        if kind == "text" or kind == "thinking":
            delta = "text_delta" if kind == "text" else "thinking_delta"
            pieces.append(event("content_block_start", index=index, content_block={"type": kind, kind: ""}))
            words = value.split(" ")
            for start in range(0, len(words), 4):
                chunk = " ".join(words[start:start + 4]) + (" " if start + 4 < len(words) else "")
                pieces.append(event("content_block_delta", index=index, delta={"type": delta, kind: chunk}))
            if kind == "thinking":
                pieces.append(event("content_block_delta", index=index, delta={"type": "signature_delta", "signature": "showcase"}))
        else:
            call = {"type": "tool_use", "id": f"call-{time.monotonic_ns()}", "name": kind, "input": {}}
            pieces.append(event("content_block_start", index=index, content_block=call))
            pieces.append(event("content_block_delta", index=index, delta={"type": "input_json_delta", "partial_json": json.dumps(value)}))
        if cut:
            return pieces
        pieces.append(event("content_block_stop", index=index))
    stop = "tool_use" if any(kind not in ("text", "thinking") for kind, _ in blocks) else "end_turn"
    return pieces + [event("message_delta", delta={"stop_reason": stop}, usage={"output_tokens": 5}), event("message_stop")]


def text_of(message):
    """The message's last text part: ask puts context before the first prompt, and a stopped call's result before the next one."""
    content = message.get("content")
    if isinstance(content, str):
        return content
    texts = [part.get("text", "") for part in content if part.get("type") == "text"] if isinstance(content, list) else []
    return texts[-1] if texts else ""


def is_prompt(message):
    """A message the person typed: one with text that is not ask's own note after a dropped connection."""
    text = text_of(message).strip()
    return message.get("role") == "user" and bool(text) and not text.startswith("[ask]")


def next_response(messages):
    """The scene the last prompt names, at the step after the answers already given since it."""
    prompt_index = max((i for i, m in enumerate(messages) if is_prompt(m)), default=None)
    if prompt_index is None:
        return response([("text", "Type a scene's number.")])
    scene = text_of(messages[prompt_index]).strip().split(" ")[0].rstrip(".")
    if scene not in SCENES:
        menu = "\n".join(f"{number}. {title}" for number, (title, _) in SCENES.items())
        return response([("text", f"Type a scene's number:\n\n{menu}")])
    step = sum(1 for m in messages[prompt_index + 1:] if m.get("role") == "assistant")
    steps = SCENES[scene][1]
    if step >= len(steps):
        return response([("text", "That scene is over; type another number.")])
    return response(steps[step], cut=DROPPED.get(scene) == step)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, *arguments):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["content-length"])))
        self.send_response(200)
        self.send_header("content-type", "text/event-stream")
        self.end_headers()
        for piece in next_response(body.get("messages", [])):
            self.wfile.write(piece)
            self.wfile.flush()
            time.sleep(0.03)
        self.close_connection = True


def project(root):
    os.makedirs(os.path.join(root, "Sources", "Demo"))
    with open(os.path.join(root, "README.md"), "w") as file:
        file.write("# Showcase project\n\nA scratch directory for Scripts/showcase.py.\n")
    with open(os.path.join(root, "Sources", "Demo", "main.swift"), "w") as file:
        file.write(CODE + "\n")


def main(arguments):
    binary = os.path.abspath(next((a for a in arguments if not a.startswith("--") and "/" in a), ".build/release/ask"))
    appearance = arguments[arguments.index("--appearance") + 1] if "--appearance" in arguments else "auto"
    root = tempfile.mkdtemp(prefix="ask-showcase-")
    try:
        work, config, home = (os.path.join(root, name) for name in ("project", "config", "home"))
        project(work)
        os.makedirs(os.path.join(config, "ask"))
        os.makedirs(home)
        with open(os.path.join(config, "ask", "config.json"), "w") as file:
            json.dump({"ui": {"appearance": appearance}}, file)
        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        env = {k: v for k, v in os.environ.items() if not k.startswith("ASK_")}
        env.update(ANTHROPIC_API_KEY="sk-ant-api-showcase", ANTHROPIC_BASE_URL=f"http://127.0.0.1:{server.server_address[1]}",
                   XDG_CONFIG_HOME=config, XDG_STATE_HOME=os.path.join(root, "state"), HOME=home)
        print("ask showcase: a scripted model, a scratch project; type a scene's number as the prompt.\n")
        for number, (title, _) in SCENES.items():
            print(f"  {number}. {title}")
        print("\nAlso try: a click on a link or a path, Ctrl+O on a command, /help, /jobs or /tasks, a light and a dark terminal "
              "page.\nPress Enter to start.")
        input()
        return subprocess.call([binary, "--provider", "anthropic", "--model", "showcase"], cwd=work, env=env)
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
