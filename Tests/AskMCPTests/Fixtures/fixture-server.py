#!/usr/bin/env python3
"""A small MCP server for ask's transport tests (ADR-0096). It speaks line-delimited JSON-RPC on stdin and stdout and can misbehave on
request, through its first argument:

  (none)     behaves
  garbage    prints a line that is not a message before it answers anything
  split      writes each answer in two pieces, with a pause between them
  stubborn   ignores end of input and SIGTERM, so it has to be killed
  crash      exits with status 3 when a tool is called, without answering
  resources  also has resources: note://a, whose text is "the note's text"

Tools: echo {message, slow} (with slow, a call that asks for progress is told "half way", then waits slow seconds); env (the names of its environment variables); pwd; big {kilobytes}; log {text} (writes to stderr).
"""
import json, os, signal, sys, time

mode = sys.argv[1] if len(sys.argv) > 1 else ""
if mode == "stubborn":
    signal.signal(signal.SIGTERM, signal.SIG_IGN)


def send(message):
    line = json.dumps(message)
    if mode == "split":
        half = len(line) // 2
        sys.stdout.write(line[:half]); sys.stdout.flush(); time.sleep(0.05)
        sys.stdout.write(line[half:] + "\n"); sys.stdout.flush()
    else:
        sys.stdout.write(line + "\n"); sys.stdout.flush()


def text(value):
    return {"content": [{"type": "text", "text": value}]}


TOOLS = [
    {"name": "echo", "description": "Echoes.", "inputSchema": {"type": "object", "properties": {"message": {"type": "string"}}},
     "annotations": {"readOnlyHint": True}},
    {"name": "env", "description": "Names of the environment.", "inputSchema": {"type": "object"}, "annotations": {"readOnlyHint": True}},
    {"name": "pwd", "description": "Working directory.", "inputSchema": {"type": "object"}, "annotations": {"readOnlyHint": True}},
    {"name": "big", "description": "A large result.", "inputSchema": {"type": "object"}, "annotations": {"readOnlyHint": True}},
    {"name": "log", "description": "Writes to stderr.", "inputSchema": {"type": "object"}, "annotations": {"readOnlyHint": True}},
    {
        "name": "boom",
        "description": "Deletes a file.",
        "inputSchema": {"type": "object", "properties": {"path": {"type": "string"}}},
        "annotations": {"destructiveHint": True},
    },
    {
        "name": "zap",
        "description": "Deletes a file too.",
        "inputSchema": {"type": "object", "properties": {"path": {"type": "string"}}},
        "annotations": {"destructiveHint": True},
    },
]

if mode == "garbage":
    sys.stdout.write("Server listening, oops\n"); sys.stdout.flush()

while True:
    if mode == "stubborn":
        try:
            line = sys.stdin.readline()
        except Exception:
            line = ""
        if not line:
            while True:
                time.sleep(1)
    else:
        line = sys.stdin.readline()
        if not line:
            break
    message = json.loads(line)
    method, ident, params = message.get("method"), message.get("id"), message.get("params") or {}
    if ident is None:
        continue
    if method == "initialize":
        capabilities = {"tools": {}, "resources": {}} if mode == "resources" else {"tools": {}}
        send({"jsonrpc": "2.0", "id": ident, "result": {"protocolVersion": params.get("protocolVersion"), "capabilities": capabilities,
                                                         "serverInfo": {"name": "fixture", "version": "1"}}})
    elif method == "resources/list":
        send({"jsonrpc": "2.0", "id": ident, "result": {"resources": [{"uri": "note://a", "name": "a", "mimeType": "text/plain"}]}})
    elif method == "resources/templates/list":
        send({"jsonrpc": "2.0", "id": ident, "result": {"resourceTemplates": []}})
    elif method == "resources/read":
        send({"jsonrpc": "2.0", "id": ident, "result": {"contents": [{"uri": params.get("uri"), "mimeType": "text/plain",
                                                                      "text": "the note's text"}]}})
    elif method == "tools/list":
        if params.get("cursor") is None:
            send({"jsonrpc": "2.0", "id": ident, "result": {"tools": TOOLS[:2], "nextCursor": "second"}})
        else:
            send({"jsonrpc": "2.0", "id": ident, "result": {"tools": TOOLS[2:]}})
    elif method == "tools/call":
        name, args = params.get("name"), params.get("arguments") or {}
        if mode == "crash":
            sys.exit(3)
        if name == "echo":
            token = (params.get("_meta") or {}).get("progressToken")
            if args.get("slow") and token is not None:
                send({"jsonrpc": "2.0", "method": "notifications/progress",
                      "params": {"progressToken": token, "progress": 1, "total": 2, "message": "half way"}})
            time.sleep(float(args.get("slow", 0)))
            send({"jsonrpc": "2.0", "id": ident, "result": text("Echo: " + str(args.get("message")))})
        elif name == "env":
            send({"jsonrpc": "2.0", "id": ident, "result": text(",".join(sorted(os.environ)))})
        elif name == "pwd":
            send({"jsonrpc": "2.0", "id": ident, "result": text(os.getcwd())})
        elif name == "big":
            send({"jsonrpc": "2.0", "id": ident, "result": text("x" * (1024 * int(args.get("kilobytes", 1024))))})
        elif name in ("boom", "zap"):
            target = args.get("path", "")
            gone = "gone" if not os.path.exists(target) and os.path.isfile(target + ".gone") else "not gone"
            try:
                if os.path.exists(target):
                    os.rename(target, target + ".gone")
                    gone = "gone"
            except OSError:
                gone = "failed"
            send({"jsonrpc": "2.0", "id": ident, "result": text("deleted " + target + ": " + gone)})
        elif name == "log":
            sys.stderr.write(str(args.get("text")) + "\n"); sys.stderr.flush()
            send({"jsonrpc": "2.0", "id": ident, "result": text("logged")})
        else:
            send({"jsonrpc": "2.0", "id": ident, "error": {"code": -32602, "message": "Tool %s not found" % name}})
    else:
        send({"jsonrpc": "2.0", "id": ident, "result": {}})
