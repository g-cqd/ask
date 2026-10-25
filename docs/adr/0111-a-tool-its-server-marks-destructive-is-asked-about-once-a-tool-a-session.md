---
status: accepted
date: 2026-10-25
---

# 0111 — A tool its server marks destructive is asked about, once a tool a session

## Context

ADR-0099 made naming a server the consent, with no per-call approval, and left per-call approval open in roadmap 0067. A server's
`destructiveHint` is the one mark it gives about what a tool does, and the owner asked to continue twice after the item was listed. This
is the policy ADR-0099 deferred; it narrows that decision and nothing else in it.

## Decision

1. **A tool marked `destructiveHint` is put to the user before it runs** — the same approval screen as a sandbox widening (`y` once,
   `a` for this session, `n` no), with a question that names the server and the tool, shows the call's arguments, and says what the mark
   means: "it may destroy or overwrite". **`a` remembers, per tool per session**: a later call of the same server's tool runs without
   asking. `y` allows one call; `n` refuses it and the model is told.
2. **A run with no one to ask allows the call.** `ask -p` has no screen to ask on; refusing would break every one-shot use of a server
   that marks most of its tools destructive. Naming the server was the user's consent, and the run's stderr already says which servers
   are connected. This is the opposite of a sandbox widening, which is refused without an approver: a widening goes beyond what the user
   set up, while a destructive tool is what the user's own configuration asked for.
3. **Both call paths ask**: a tool offered directly (`mcp__server__tool`) and one called through `mcp_call` after `mcp_search`. The
   search also marks a destructive tool in what it shows ("the server marks this destructive: ask may ask before it runs"), so the model
   is not surprised by the question.
4. **The mark is the server's word, not a fact** (as ADR-0099 said of all hints). A tool that lies about being destructive runs with no
   question; one marked destructive need not be. ask asks anyway, because the cost of an unnecessary question is one keypress once per
   tool per session, and the cost of an unasked one is data. A server that marks everything destructive pays one question per tool.

## Consequences

The model can no longer call a marked tool without the person's first `a` in an interactive session. A malicious or careless server
cannot be stopped by this — it can mark nothing destructive, or do its damage in a tool marked read-only — so this is a guardrail, not
a boundary; the boundary remains what it was (ADR-0099: the server runs outside the sandbox, with the user's consent to name it).

## Probes

| Claim | Result |
|---|---|
| A marked tool is asked about before it runs, and allowing for the session runs it | `Scripts/probe-mcp-screen.py` through the real binary, a PTY and a fake provider: the question with `y once · a for this session · n no`, then "Allowed for this session." and the tool's result |
| The grant is remembered | the same probe: a second call of the same tool runs with no second question |
| Another marked tool is asked about, and refusing it tells the model | the same probe: `n`, "Not allowed.", and the refusal as the tool's result in the next request the provider receives |
| A one-shot run allows the call with no question | `Scripts/probe-mcp.py` F: the marked tool ran, the file was moved, and stderr asked nothing |
| Unit tests | 8 in `MCPApprovalTests`: asked with the server, tool and arguments; a refusal is an error and the server is not called; an unmarked tool is never asked; no approver allows; the ask is per call (grants are the approver's to keep); the search path asks too and marks; a refusal through `mcp_call` is an error |
| Compiling mutants | all caught: not asked (both paths), the mark inverted, the refusal ignored, the search mark removed |
| Not covered | the composition's own grant bookkeeping beyond the probe (it lives in `Sources/ask`, which has no tests, roadmap 0028); a server that mislabels its tools |
