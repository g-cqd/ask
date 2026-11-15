---
status: accepted
date: 2026-11-15
---

# 0154 — `ask serve` is a second driver of the conversation, on a connection that admits requests in order

## Context

ADR-0153 decided the protocol (ACP v1), what a served session is (the conversation) and where the wire comes from (the family).
The design that followed was put to the owner as `development/research/serve-design-2026-11-14.md` with its open points; the
owner's answer was to go ahead with what was proposed (2026-11-14). Two things changed between the proposal and the first code,
both found by building it.

## Decision

1. **The design of the research note stands**, as proposed: `ask serve` on standard input and output; approvals asked through
   `session/request_permission` with ask's own policy and its own meaning of "always"; no secret in a form; ask's tools stay ask's
   (no `fs/*`, no `terminal/*`); the mapping table; what is not sent in the first version; the order of work.
2. **The open points, as proposed.** A `session/prompt` while a turn runs steers it, as Enter does on the screen. The protocol's
   types are written by hand for the subset used, each tested against the specification's examples. Sign-in stays `ask login`
   in a terminal; `authenticate` is not built. Nothing is sent under an extension name: the owner has not named a domain.
   Whether a form can ask a multiple choice is still unread.
3. **`AskACP` depends on the screen's `Conversation` protocol, not on `AskSession`** (a correction to the note, which put it
   above `AskSession`). `Conversation` (`start`, `enqueue`, `answer`, `command`, the updates) is the seam the screen
   already drives the agent through; the protocol front is a second driver of it, and is tested against a fake one as the screen
   is. `AskSession` makes a conversation for a session's folder and hands it over, as it does for the screen.
4. **Requests are admitted in the order they arrive**, by AemiJSONRPC. The spike showed `JSONRPCConnection` answering each
   request in a task of its own, so their order was lost, and dropping what it could not read. The owner chose to fix it there
   (AemiJSON `31ce461`: `init(serving:…admit:…)`, the family's roadmap 0011) rather than in ask. Until ask's pin of AemiJSON moves, which it can only do with the family's (AemiMarkdown pins the same
   revision), `AskACP` uses the connection as it was, and `serve` is not listed in the help.

## Consequences

- A client that writes `session/prompt` and `session/cancel` back to back is served correctly only after the pin moves. Every
  step up to that one (sessions, prompts, updates) can be built and tested before; cancellation lands after.
- The layering gains `AskACP` with `AskTUI` as its only internal dependency (none while it only answers `initialize`).
- The protocol's name stays in `AskACP` and in the command that starts it.

## Probes

Diary 2026-11-15-01.
