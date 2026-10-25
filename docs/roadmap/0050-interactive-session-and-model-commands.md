---
status: done
blocked-by: []
date: 2026-10-20
---

# 0050 — Interactive session and model commands

The screen can resume only at launch and choose its model only through configuration or flags.
Make the active conversation switchable without leaving ask: `/new`, `/resume` and `/model`.

Keep session writer locks, usage, history, settings provenance and running jobs coherent. A failed switch must
leave the previous conversation usable. Refuse or defer a switch while a turn or queued input is active;
never silently move pending messages into a different session.

## Done when

Real-PTY probes switch to a new session, return to an old one, refuse a locked or unknown session without losing
the current one, and change the model observed by the fake provider on the next request. Model choices should
use the catalog work (0038) where available, not duplicate its discovery.

## Delivered — /new (2026-10-20, ADR-0041)

Starts a new conversation without leaving ask. It releases the old writer lock and leaves the old file
unchanged, clears context/usage/learned-window state, preserves the editor draft, and creates no new file
until the next prompt. Running jobs and bad arguments refuse without changing the active conversation.
Real-PTY N/O inspect archives, requests, writer locking and the job's continued operation.
The screen's busy boundary refuses switches while a turn or queued input is active.

## Delivered — /resume (2026-10-20, diary 36)

With no argument, lists up to 20 project sessions with their first prompt and marks the current one.
A name, unique prefix or path opens that session before releasing the current writer, then replaces the
transcript and usage. Selecting the current session is a no-op. Lookup, open and lock failure leave the
active session usable. Running jobs refuse a switch, while listing remains available.
Damage is reported, reading never rewrites it, and the first later change preserves the damaged original.

Real-PTY P checks two archives, ambiguous/unknown/missing/locked selection, exact next-request context,
history, usage, both locks, current-session reselection and damaged-session recovery. O checks the running-job guard.

## Delivered — /model (2026-10-20, ADR-0042, diary 37)

`/model` shows the model and its source; `/model MODEL` and `/model PROVIDER MODEL` choose one for this run;
`/model --reset` returns to the configuration. A choice replaces provider and model together as a top layer named
`/model (this run)`, is adopted only if the whole configuration resolves, is never written to a file, and survives
`/reload` (the replacement and its self-check get the same hidden arguments). Real-PTY Q checks requests, labels,
provenance, refusals, a file edit, a reload and a reset.

## Still owed, and not claimed by this entry

- A model **list** to choose from. Codex's account catalog (0038) and named connections (0047) own discovery; today
  `/model` takes an id you already know.
- Remembering a choice in the session archive, so a resumed session starts on the model it last used.
- A pre-flight check that an Anthropic or signed-out Codex account may use the model; the first request says so.
- A picker for `/resume` (it prints a list), and `/new` / `/resume` while a turn is running (refused by design).

## Update (2026-10-25, ADR-0093)

`/tree` and `/tree N` navigate the session's branches from the screen. `/fork` is not built.
