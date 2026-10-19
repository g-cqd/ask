---
status: not-started
blocked-by: []
date: 2026-10-20
---

# 0046 — Interactive session and model commands

The screen can resume only at launch and choose its model only through configuration or flags.
Make the active conversation switchable without leaving ask: `/new`, `/resume` and `/model`.

Keep session writer locks, usage, history, settings provenance and running jobs coherent. A failed switch must
leave the previous conversation usable. Refuse or defer a switch while a turn or queued input is active;
never silently move pending messages into a different session.

## Done when

Real-PTY probes switch to a new session, return to an old one, refuse a locked or unknown session without losing
the current one, and change the model observed by the fake provider on the next request. Model choices should
use the catalog work (0038) where available, not duplicate its discovery.
