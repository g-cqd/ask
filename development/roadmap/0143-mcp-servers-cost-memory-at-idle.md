---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0143 — MCP servers cost resident memory before they are used

Found while configuring the owner's MCP servers (2026-10-29): Apple's documentation (`apple-docs`, the public instance over HTTP), and
Xcode's two local servers, `xcrun mcpbridge` (54 tools) and `xcrun lldb-mcp` (2 tools). All three connect when ask starts.

## Measured (release, a fresh screen, 8 s after the first frame, two runs, the owner's config copied without credentials)

| Servers configured | Resident size |
| --- | --- |
| none | 14.5 MiB |
| apple-docs only | 22.7-22.8 MiB |
| xcode only | 17.0-20.3 MiB |
| lldb only | 19.5 MiB |
| all three | 27.6 MiB |

The first frame is not delayed (12 to 20 ms either way): the servers connect in the background. The idle budget (15 MiB) holds only with no
server configured. apple-docs costs what a first model request costs (the URLSession and TLS stack, roadmap 0088: about 8 MiB), paid at
launch instead; the stdio servers' cost (2.5 to 5.8 MiB each) is not attributed yet.

## Options

1. **Connect on first need.** List the servers' tools when the first turn is sent, not at launch; the screen says "connecting" if it waits.
   Idle returns to 14.5 MiB; the first turn pays the connections (measure: `xcrun mcpbridge` and the HTTP handshake).
2. **Attribute the stdio cost** (`vmmap -summary` before and after one stdio server connects): `Subprocess`, the reader tasks, the tool
   schemas kept as JSON. Fix what is ours.
3. **Keep the tool lists, not the connections**: cache each server's `tools/list` beside the session, offer them from the cache, and connect
   when a tool is called (servers with `listChanged` refresh it then).

Option 1 first, with 2 measured beside it; 3 only if the first turn's wait shows.
