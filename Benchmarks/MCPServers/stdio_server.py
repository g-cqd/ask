#!/usr/bin/env python3
"""A fake MCP server on standard input and output, for MCPStress: echoes tools/call with a reply of the asked size."""
import json
import sys

replies = {}


def result(message):
    method = message.get("method")
    if method == "initialize":
        return {"protocolVersion": message["params"]["protocolVersion"], "capabilities": {"tools": {}},
                "serverInfo": {"name": "fake-python", "version": "1"}}
    if method == "tools/list":
        return {"tools": [{"name": "echo", "description": "Echo", "inputSchema": {"type": "object"}}]}
    if method == "tools/call":
        size = message["params"]["arguments"].get("size", 2)
        if size not in replies:
            replies[size] = {"content": [{"type": "text", "text": "x" * size}], "isError": False}
        return replies[size]
    return {}


for line in sys.stdin:
    message = json.loads(line)
    if "id" not in message:
        continue
    sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": message["id"], "result": result(message)}) + "\n")
    sys.stdout.flush()
