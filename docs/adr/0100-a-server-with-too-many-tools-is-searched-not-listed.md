---
status: accepted
date: 2026-10-25
---

# 0100 — A server with too many tools is searched, not listed

## Context

ADR-0099 offered no tools from a server with more than 16 and no `tools` list, and said how to choose. That keeps the request small
and leaves the model blind to a server the user named: `rea`, which is in the owner's own configuration, has 207 tools, and "list the
ones you want" means reading 207 names first. The cost to avoid is real (about 689 KB of schemas in every request); the answer is not
to hide the tools but to make them reachable without listing them.

## Decision

1. **Two tools stand in front of every such server**: `mcp_search` (words, optionally a server) and `mcp_call` (server, tool, arguments).
   They exist only while some server is searched, and are withdrawn when none is. Their description names the servers they reach and
   how many tools each has.
2. **Search is by words, over names and descriptions.** A word in a tool's name counts three and in its description one, as a part of
   the text and not only a whole word (`function` finds `list_functions`); the best eight are shown, ties in the order the server listed
   them. Each match shows the server and tool, the first 300 characters of what it does, and the schema of its arguments, because the
   model must write a call that fits it. The schema budget (12,000 bytes) is shared among the matches and never less than 3,000 each, so a
   search naming one tool shows nearly all its schema: a cut before its `$defs` leaves references nothing resolves. A cut is said.
   An empty query lists the names, a line a server.
3. **A call is the same call.** `mcp_call` sends the arguments as the model wrote them, refuses anything that is not an object before
   sending, answers an unknown server or tool with the servers there are and a pointer to the search, and refuses a narrowed session as
   every server's tool does (ADR-0099). Its result is read as any other (text, named non-text, `isError`).
4. **A `tools` list still wins**: such a server is offered whole, however many tools it has. A server that comes down to 16 or fewer
   is offered whole after all, and one that goes away takes its entries with it.
5. **The state is `searchable`**, shown by `/mcp` as "ready, N tools reachable through mcp_search and mcp_call", and said once as a
   notice (on stderr for a one-shot run) with the key that offers them directly. The "skipped" state of ADR-0099 is gone; this
   supersedes its point 4 and nothing else in it.

## Consequences

The tool list the model sees gains two tools once a large server connects, so the prompt-cache prefix changes once at that moment, not
on each request. A model must search before it calls, one extra turn the first time it uses such a server; a server it already knows
(by a `tools` list) costs none. Ranking is a plain substring count: it will miss a tool whose name shares no word with the model's
description of it, and it will not be better than the server's own names. A better ranking is possible and measured, not guessed.

## Probes

| Claim | Result |
|---|---|
| A large server is reachable through the search and the call | `Scripts/probe-mcp.py` B, through the real binary: a 20-tool server, the two tools offered and none of the server's own, the search finds `t17` and does not list the rest, the call reaches it with its arguments, stderr says how to offer them whole |
| It works on a real large server | Once, ad hoc (not kept), with `rea` (207 tools): the request carried the two tools and was 21 KB; a search for "decompile function" answered in 9.9 KB with eight matches; a browse listed all names in 4.5 KB; the run took 2.8 s including the server's start |
| The ranking finds what the words name | by tests over a small catalog (names beat descriptions, more words beat fewer, case and punctuation do not matter); **not evaluated** on a real corpus: the top match for "decompile function" on `rea` was `annotate_native_function`, plausible and not obviously best |
| Compiling mutants | name weight, description ignored, ties, non-matches kept, server filter ignored, schema cut not said, description not cut, "more" not said, call ignoring the narrowed session, wrong argument kinds accepted, a shrunk server staying searchable, a gone server staying searchable, the search tools never withdrawn, an unknown tool reaching the server: all caught except the tie order, which is a stable sort in practice and is kept as a guarantee, not a behaviour |
