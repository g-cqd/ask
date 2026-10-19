# The ask extension protocol — version 1 (draft)

An extension is an executable, in any language, that adds tools to ask and sees tool calls before and after they
run. ask starts it as a child process and talks to it over its standard input and output. Decided in ADR-0028;
the host is roadmap 0033. **Draft**: this version is fixed when the host ships, and changes after that are new
versions, never edits.

## Transport

- **JSON-RPC 2.0**, one message per line, UTF-8, on stdin (from ask) and stdout (from the extension). A message
  never contains a raw newline; JSON escapes it.
- **stderr is a log.** ask keeps it for the user and never parses it. An extension must not print anything else
  to stdout.
- Requests carry an `id` and receive exactly one response; notifications carry none and receive none. ask may send
  a request before an earlier one is answered, so responses may come in any order; match them by `id`.
- Field names follow MCP where the meaning is the same (`inputSchema`, `content`, `isError`), so the transport can
  serve MCP servers too.

## Lifecycle

1. ask starts the extension **after its first frame**, never before: spawning costs 5 ms for a compiled program and
   25 to 53 ms for Python, against a 25 ms cold-start budget (diary 13).
2. ask sends `initialize`; the extension answers within **5 seconds** with what it provides, or is stopped.
3. ask sends `tools/call` and hook requests for as long as the session lasts, plus notifications.
4. ask sends `shutdown`, waits for its response, then closes stdin. An extension that has not exited **2 seconds**
   later is terminated with its process group.

## Methods

### `initialize` (ask → extension)

```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"ask":"0.1.0","workingDirectory":"/repo"}}
```

```json
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"name":"guard","version":"1.0.0",
 "tools":[{"name":"todo","description":"List TODO comments.","inputSchema":{"type":"object","properties":{}},
           "annotations":{"readOnlyHint":true}}],
 "hooks":[{"event":"tool_call","tools":["bash"],"onFailure":"block","timeoutMs":2000}]}}
```

- An answer with another `protocolVersion` is refused, and the extension stopped.
- A tool whose name another tool already has is refused; the extension's other tools stay.
- `annotations` carry MCP's hints (`readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint`). They are
  hints for approval and scheduling, never trusted as a guarantee.
- `hooks[].tools` limits a hook to those tool names; absent means every tool. `onFailure` is `allow` or `block`
  and decides what happens when the hook errs or misses its `timeoutMs` (default 2000).

### `tools/call` (ask → extension)

```json
{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"callId":"c1","name":"todo","input":{},"workingDirectory":"/repo"}}
```

```json
{"jsonrpc":"2.0","id":7,"result":{"content":"main.swift:12 TODO: remove","isError":false}}
```

A JSON-RPC error, a crash or a timeout (120 s unless the tool says otherwise) becomes an error result the model
reads; the run continues.

### `hooks/tool_call` (ask → extension)

Sent before a call to a tool the hook covers, with the input as earlier hooks left it.

```json
{"jsonrpc":"2.0","id":8,"method":"hooks/tool_call","params":{"callId":"c2","name":"bash","input":{"command":"rm -rf /"}}}
```

The result is one of:

```json
{"decision":"allow"}
{"decision":"block","reason":"recursive deletes are not allowed"}
{"decision":"rewrite","input":{"command":"ls"}}
```

### `hooks/tool_result` (ask → extension)

Sent after the call, with the output as earlier hooks left it. The result replaces it.

```json
{"jsonrpc":"2.0","id":9,"method":"hooks/tool_result","params":{"callId":"c2","name":"bash","input":{"command":"ls"},
 "output":{"content":"a\nb","isError":false}}}
```

```json
{"jsonrpc":"2.0","id":9,"result":{"output":{"content":"a\nb","isError":false}}}
```

### `notifications/agent_event` (ask → extension)

What happened in the run, for extensions that observe: `responded`, `toolStarted`, `toolFinished`, `finished`,
`retrying`. No response.

### `shutdown` (ask → extension)

`{"jsonrpc":"2.0","id":10,"method":"shutdown"}`, answered with `{"result":{}}`.

## Order

Hooks run in the order extensions are configured, each seeing what the previous one left; the first `block` ends
the chain (ADR-0028, `AgentHook`). **ask's own policy hooks run after every extension's**, so approval and sandbox
policy judge the input that would actually run.

## Configuration

`~/.config/ask/extensions.json`; a project's `.ask/extensions.json` is read only after the user trusts the project.

```json
{ "extensions": { "guard": { "command": ["/usr/bin/python3", "/Users/me/ask-ext/guard.py"], "env": {} } } }
```

`command` is an argument vector, never a shell string. Each extension runs as a sandboxed child under the
intersection of the layers ADR-0020 defines.

## A complete extension

```python
#!/usr/bin/env python3
import json, sys

def reply(id, result): print(json.dumps({"jsonrpc": "2.0", "id": id, "result": result}), flush=True)

for line in sys.stdin:
    msg = json.loads(line)
    method, params, id = msg.get("method"), msg.get("params", {}), msg.get("id")
    if method == "initialize":
        reply(id, {"protocolVersion": 1, "name": "guard", "version": "1.0.0", "tools": [],
                   "hooks": [{"event": "tool_call", "tools": ["bash"], "onFailure": "block"}]})
    elif method == "hooks/tool_call":
        risky = "rm -rf" in params["input"].get("command", "")
        reply(id, {"decision": "block", "reason": "recursive deletes need a person"} if risky else {"decision": "allow"})
    elif method == "shutdown":
        reply(id, {}); break
```
