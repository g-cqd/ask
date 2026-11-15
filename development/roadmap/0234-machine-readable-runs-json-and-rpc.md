---
status: in-progress
blocked-by: []
date: 2026-11-13
---

# 0234 — Machine-readable runs: `ask -p --json`, then an RPC mode

From the study of other agents (proposal 2), chosen 2026-11-13, a cheap one done first.

1. `ask -p --json`: the run's events as JSON lines on standard output (text, thinking, tool calls and results, usage, the end), one
   object each, with a version field; the final reply as today without it.
2. `ask serve`: JSON-RPC on stdio for a long-lived driver: send a prompt, stream its events, answer approvals and questions, cancel.
   ACP (the next entry) is built on it.

## Done when

A probe reads a `--json` run's lines and finds each event kind; the RPC mode drives two prompts and an approval.

## Step 1 done (2026-11-13)

`ask -p --json`: `JSONEventWriter` (AskAgentCore, on AemiJSON's `JSONStreamWriter`, the tool input spliced in as raw JSON) writes
`text`, `thinking`, `notice`, `tool_call`, `tool_result`, `response`, `retry`, `compacting`, `compacted`, `compaction_failed`,
`hook_continued` and `finished`, each `{"v":1,"type":…}`, then an `end` line with the session and the tokens. Tested
(`JSONEventWriterTests`, red with the input as a string) and live (`Scripts/probe-print-json.py`). Step 2, the RPC mode, is next for
ACP.

## Step 2: decided, design proposed (2026-11-14, ADR-0153)

The owner chose ACP as serve's protocol and the whole conversation as a served session, so this step and roadmap 0235 are one
piece of work. The wire is AemiJSONRPC's (already in the pinned AemiJSON). The design and the order of work are proposed in `development/research/serve-design-2026-11-14.md`; nothing is built.

## Step 2, first part: `initialize` (2026-11-15, ADR-0154, diary 2026-11-15-01)

The owner accepted the design. `AskACP` answers `initialize` over AemiJSONRPC; `ask serve` runs it, hidden from the help until
a session can be served. Building it showed the family's connection losing the order of requests and dropping what it could not
read; fixed in AemiJSON (`31ce461`), which ask takes at the family's next repin. Next: the session's folder, then `session/new`
and `session/prompt`.

## Step 2, second part: sessions and prompts in the protocol's library (2026-11-15, diaries 03, 06, 07)

A conversation reads its own folder and keeps its own task list and notes, so several can share a process. `AskACP` serves
`session/new` and `session/prompt` over the screen's `Conversation` seam: text and thinking as chunks in order, the answer after
them, a prompt during a turn steering it. Tested against a directed conversation. Next: `ask serve` makes real conversations,
and `Scripts/probe-serve.py` drives one against the fake model server.

## Step 2, third part: `ask serve` serves conversations (2026-11-15, diary 2026-11-15-08)

`ServedSessions` makes a conversation for each session a client asks for, in the client's folder; `Scripts/probe-serve.py`
drives one over pipes against the fake model server. Until the client can be asked, a call that needs approval is declined.
Next: tool calls and `session/request_permission`.

## Step 2, fourth part: tool calls and approvals (2026-11-15, diary 2026-11-15-10)

A served turn tells each tool call as it begins and ends, and asks the client for the approvals the screen would ask the
person, with the screen's answers. `probe-serve.py` allows one write and denies another. Next: `session/cancel` (needs the
AemiJSON pin), then `session/load`.

## Step 2, fifth part: `session/load` (2026-11-15, diary 2026-11-15-11)

A saved session is opened by its id for its folder, replayed to the client as updates, and continued. `probe-serve.py` loads the
first process's session from a second. Next: `session/cancel`, once ask pins the AemiJSON that admits requests in order.

