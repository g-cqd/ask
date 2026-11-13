---
status: in-progress
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

## Step 1 done (2026-11-13)

ADR-0149. 138 files moved unchanged from `Sources/ask` to `Sources/AskSession`; 18 stay (the options and subcommands). The surface
is `package` access, widened by the compiler's diagnostics: about 110 declarations and 12 imports. `AskSessionTests` exists, with a
fixture (a conversation over a temporary home, no network) and `SessionSwitchTests`: the defect of 2026-11-13 (a session kept locked
while its name was asked for) is reproduced in a unit test, red with the fix removed. The mutation run's full matrix has two
`AskSession` shards. The release build, the probes and the suite pass.

## Left

Step 2 (the command registry, roadmap 0210) waits for the owner's answer on 0209/0210 (§5.1 of the rationalisation note). Step 3:
more lifecycle tests (fork, resume, reload) on the fixture; `ConversationUpdate` moved below AskTUI for the RPC front end (0234).
