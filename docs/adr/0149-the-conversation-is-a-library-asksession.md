---
status: accepted
date: 2026-11-13
---

# 0149 — The conversation is a library, `AskSession`, and the executable is arguments and wiring

## Context

ADR-0009 made the executable the composition root. It grew: on 2026-11-13 `Sources/ask` held 155 files and 9,806 lines, among them
the conversation (`AgentConversation`, 46 files), its commands, sessions, threads, goals, loops, sign-in, model discovery and the
composition of a run. An executable target has no test target here, so none of it was unit-tested and the mutation run skipped it
(544 mutants never ran); its defects were found by PTY probes only (the session left locked after `/new`, 2026-11-13). The engineering
plan (`development/research/engineering-plan-2026-11.md`, phase B) proposed moving it into a library; the owner said yes. The RPC and
ACP front ends (roadmap 0234, 0235) need the conversation outside the executable too.

## Decision

- A library target `AskSession` holds everything that was in `Sources/ask` except the ArgumentParser commands: 138 files moved
  unchanged. `Sources/ask` keeps `Ask` (the options), its subcommands and their two extensions: 18 files.
- Its surface is `package` access, not `public`: only this package's executable and tests use it. What the executable needs was
  widened by the compiler's own diagnostics (about 110 declarations, 12 imports); a memberwise initialiser the executable calls
  became an explicit `package init`. `LaunchRequest` is filled by assignment from `Ask`.
- Layering (`Scripts/check-layers.py`): `AskSession` may depend on every other library; nothing but the executable depends on it.
- `AskSessionTests` is its test target, and the mutation run covers it.

## Consequences

- The conversation still speaks `ConversationUpdate`, which lives in AskTUI, so `AskSession` depends on AskTUI; a front end without a
  screen (0234) will want that channel moved down. Not done here.
- Symbol names changed module (`ask` to `AskSession`), so the startup order file is regenerated.
- The source scans that named `Sources/ask` (the launch environment rule, the launch request's parity) read both folders.

Amends ADR-0009 (six targets), which stays as the record of the first layering.
