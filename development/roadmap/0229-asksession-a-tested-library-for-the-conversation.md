---
status: not-started
blocked-by: []
date: 2026-11-13
---

# 0229 — The conversation in a library of its own, tested and mutation-checked

Engineering plan phase B (`development/research/engineering-plan-2026-11.md`), the owner's yes of 2026-11-13.

`AgentConversation` and what it owns (commands, sessions, threads, goals, loops, forge, naming: 46 files, 4,028 lines, of 9,806 in
`Sources/ask` with no test) move into a library target, `AskSession`, behind the `ConversationUpdate` channel it already speaks.
`Sources/ask` keeps `main`, the arguments and the wiring. Then `AskSessionTests`, and the mutation run covers it.

## Steps

1. The move, mechanical, behaviour unchanged: the PTY sweep green before and after.
2. The command registry of roadmap 0210 (t243) lands in it: one table, typed handlers, tested without a screen.
3. Tests for the session lifecycle the probes found: `/new`, fork, resume, reload each release the old session's lock at once.

## Done when

`AskSessionTests` exists, the mutation run reaches the conversation, and the sweep is green.
