---
status: not-started
blocked-by: []
date: 2026-10-19
decision: ADR-0027
---

# 0036 — The Responses protocol, and Codex sign-in on it

Codex's ChatGPT subscription is served by the Responses API at `chatgpt.com/backend-api/codex/responses`, not chat
completions (`docs/research/provider-connections-2026-10.md`). This entry owes, in order:

1. **Provenance on reasoning**, decided in an ADR first. A Responses reasoning item must be replayed whole
   (`encrypted_content`), stored as the thinking block's signature; Anthropic refuses a signature it did not issue.
   Today only empty signatures are dropped, so a session moved between the two would fail.
2. The Responses decoder and encoder, tested against recorded streams, as chat completions was.
3. Codex sign-in, ask's own: browser PKCE with the loopback callback on 1455 and a pasted-URL fallback, and the
   device-code flow; rotating refresh tokens stored and replaced whole. Never `~/.codex/auth.json`.
4. A live run, which needs the user to sign in once.
