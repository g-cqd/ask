---
status: done
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

## Done (2026-10-29): option 1, the owner's choice

An interactive session's hub keeps the configured servers and starts none until the first message (`MCPHub(connectsOnFirstNeed:)`); `/mcp`
says each "connects with the first message". That turn shows `Connecting MCP...` in the status bar (purple, no block) and waits, at most
10 s: a server that never answers (its own start timeout is 60 s, for a package fetched first) would otherwise hold the first message that
long. A server still connecting then goes on, a notice names it, and its tools are offered once it is ready. Stopping the turn stops the
wait, not the servers. `ask -p` connects at once and waits, as before. The startup summary (0145) now comes with the first message.

**Measured** (release, a PTY, 8 s after launch, the three servers of the owner's config without credentials, the previous commit built in a
worktree, alternated; this harness reads 16.4 MiB with no server, not the 14.5 above, so compare within it):

| | idle | after the first message | first answer (fake provider) |
| --- | --- | --- | --- |
| eager (`04766ba`), apple-docs + xcode | 28.5 MiB, 2 server processes | 30.9 MiB | 0.13 s |
| on first need, apple-docs + xcode | 16.4-16.5 MiB, none | 31.1-31.2 MiB | 0.33-0.43 s |
| eager, all three | 29.0-29.2 MiB | 31.2-31.4 MiB | 0.14 s |
| on first need, all three | 16.4-16.5 MiB | 30.4-31.4 MiB | 10.05-10.36 s |

With all three the first answer takes the full 10 s: in this harness `xcrun lldb-mcp` never answers `initialize` (it stays "connecting…"
after 20 s on the eager build too), so the wait runs out. Why it does not answer here and did in the owner's session is not known (the
harness strips ask's `ASK_*` variables and runs without Xcode open). Option 2 (attributing the stdio servers' memory) is not done.

