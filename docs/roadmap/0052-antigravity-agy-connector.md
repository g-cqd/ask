---
status: not-started
blocked-by: []
date: 2026-10-20
---

# 0052 — The Antigravity (agy) connector

Antigravity is installed on the development machine (`/opt/homebrew/bin/agy`) and was on the provider list from the start, but no
roadmap entry, research note or ADR mentions it, so it was only a line in a hand-off. Writing it down here so it is claimable.

What is known, from reading and not from a probe: it needs a Google OAuth PKCE sign-in with a client secret that is discovered
locally, a Cloud Code onboarding step that yields a project and a tier, and a custom streaming protocol that is neither chat
completions nor the Responses API. pi-integrations has a working implementation to read, but the evidence rule applies: run
its code against edge cases, and probe each claim with a real account, before adopting any of it.

Done when: the sign-in and its credential storage follow ADR-0039 (a transaction per save, compare-and-replace for a refresh)
and ADR-0048 (a connection, so several accounts can coexist); the model list, if there is one, is read from the account (ADR-0037);
and a live run through the agent loop is recorded. Probe first whether a connection to it can be made without the locally
discovered client secret, and what that secret's exposure costs. Not started; nothing is known to work.
