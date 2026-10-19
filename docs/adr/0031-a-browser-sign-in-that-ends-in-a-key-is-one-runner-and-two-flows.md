---
status: accepted
date: 2026-10-19
---

# 0031 — A browser sign-in that ends in a key is one runner and two flows

## Context

Spettro and Mistral Vibe both sign in the same way: the client starts a session, the user approves in a browser, the
client polls until the server hands over a key (Vibe adds a PKCE exchange). pi-integrations implements both; its tests
pin the cases each one must refuse. Claude's sign-in is different (paste a code, receive a refreshable token pair) and
stays as ADR-0007 and ADR-0018 left it.

## Decision

1. `BrowserSignIn` is a protocol of three steps (start, poll, finish). `SignInRunner` owns the waiting, the deadline
   (measured on an injected clock, not summed from sleeps), cancellation and the stored result. A flow carries only its
   requests and the checks on what the server says.
2. A server's answer is never trusted for where to go. The browser link must be `https` without userinfo; Vibe's
   links must stay under Mistral's console origin and path with no encoded dot or slash; its process id must be
   `[A-Za-z0-9_-]{1,200}`; the API base can move only to `https` or this machine, with no userinfo, query or fragment.
3. A key or token is stored or sent only if it is non-empty, at most 16,384 bytes, and free of whitespace and control
   characters, which would split a header.
4. Unknown states end the sign-in. A server that adds a state cannot be mistaken for success.
5. Keys live in the credential file beside Claude's, saved by read-merge-write so one provider's sign-in never signs
   another out, and a file that cannot be read is never overwritten.
6. A preset gets its key from, in order: its `providers.json` entry, its environment variable, the stored key. The file
   is read only when the first two give none, so a damaged or exposed file blocks only the providers that need it.
7. Vibe's key is stored as `mistral`: it is a Mistral API key, so Mistral's preset finds it.

## Consequences

- A third sign-in of this shape is a struct and a table row, not a runner.
- The preset's key follows the preset's name: a `providers.json` entry named `groq` that moves its `baseUrl` sends
  the Groq key to the new address. `https` or loopback is still enforced (ADR-0024); the user wrote that name.
- Open, because they need a real account: that a Vibe-issued key is accepted on `api.mistral.ai/v1/chat/completions`
  (pi uses Mistral's own protocol there), and that Spettro's real service answers as pi-integrations' fixtures say.
  The flows are tested against the shapes pi-integrations pins and against a fake server on loopback.
