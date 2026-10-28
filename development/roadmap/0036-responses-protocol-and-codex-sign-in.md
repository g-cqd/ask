---
status: done
blocked-by: []
date: 2026-10-19
decision: ADR-0027
---

# 0036 — The Responses protocol, and Codex sign-in on it

Codex's ChatGPT subscription is served by the Responses API at `chatgpt.com/backend-api/codex/responses`, not chat
completions (`development/research/provider-connections-2026-10.md`). This entry owes, in order:

1. **Provenance on reasoning**, decided in an ADR first. A Responses reasoning item must be replayed whole
   (`encrypted_content`), stored as the thinking block's signature; Anthropic refuses a signature it did not issue.
   Today only empty signatures are dropped, so a session moved between the two would fail.
2. The Responses decoder and encoder, tested against recorded streams, as chat completions was.
3. Codex sign-in, ask's own: browser PKCE with the loopback callback on 1455 and a pasted-URL fallback, and the
   device-code flow; rotating refresh tokens stored and replaced whole. Never `~/.codex/auth.json`.
4. A live run, which needs the user to sign in once.

## Done (diary 22, ADR-0033)

Steps 1 and 2: provenance on reasoning, the decoder and encoder, the client, `api: "openai-responses"`. Recorded on
llama.cpp only. Steps 3 and 4 remain, and replaying reasoning is roadmap 0040.

## Done (diary 27, ADR-0036)

Step 3: Codex sign-in by browser and by device code, locked refresh, the backend's headers and dialect, `ask login codex`,
`ask --provider codex`. Probed live where a script can reach it. Step 4 remains and needs the user: the authorize step,
a first inference request, and the originator, headers and body the backend accepts.

## Live check completed (diary 27)

The user ran the release binary from `main` at `042ee46`: browser sign-in completed, `gpt-6.1-sol` returned `CODEX_OK`,
and `gpt-6-luna` read a file, wrote its content to another file, and returned `DONE`. This confirms the authorize step
and the current inference headers/body on that account. `gpt-5.5` was refused as unsupported for the account, despite
appearing in pi's static catalog. The first tool-loop attempt lost its connection (`NSURLErrorDomain -1005`); the
identical manual retry succeeded. The disconnect is unexplained, not evidence that automatic retries would be safe.

Live rotating refresh and successful device-code sign-in remain unverified (their offline tests pass). Model discovery
is roadmap 0038; encrypted reasoning replay remains roadmap 0040. None is claimed proven by this smoke test.
