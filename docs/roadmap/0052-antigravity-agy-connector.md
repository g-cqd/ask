---
status: in-progress
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
discovered client secret, and what that secret's exposure costs.

Probed: **a connection cannot be made without the secret** (the token endpoint refuses the client), and the owner accepts its
exposure (ADR-0066).

## Done (2026-10-23, ADR-0066, diary 2026-10-23-15)

The client secret is found in the user's installed `agy` (1.4.2 and 1.4.6, the same value) and confirmed with Google's token endpoint;
18 deliberate faults killed. `agy` was upgraded from 1.4.2 to 1.4.6 with `agy update` (the old binary is kept in
`~/Library/Caches/ask-mutation/agy/`).

## Still owed, in order

1. **The sign-in**, which needs the owner's browser: authorize URL with PKCE and the CLI's scopes, a pasted code, the exchange with the
   verified secret, stored as a connection (ADR-0048, ADR-0039). Decide where the verified secret lives between sign-in and refresh.
2. **Onboarding** (`loadCodeAssist`: project and tier), the **model list** (`fetchAvailableModels`, ADR-0037), and the **streaming
   protocol** (`streamGenerateContent`), each probed with a signed-in account before any code relies on it.
3. **The client identity.** pi found the backend gates the full model catalog and model routing on a User-Agent starting with
   `antigravity/cli/`. ask identifies itself honestly elsewhere (ADR-0007). First live probe: does an honest identity work, and what
   does it cost in catalog and routing? If it costs something, the owner chooses, and the choice gets its own record.
4. A live run through the agent loop, recorded.

Nothing past the secret is known to work.
