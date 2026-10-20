---
status: in-progress
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

## Still owed

- `/model`: show and change the current model using existing provider resolution/catalogs, with explicit
  run-local provenance and coherent configuration refresh and binary reload.
