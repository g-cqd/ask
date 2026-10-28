---
status: accepted
date: 2026-10-20
---

# 0036 — The login callback is a small loopback listener, and Codex refreshes under a lock

## Context

Codex's browser sign-in ends with the provider redirecting the user's browser to `http://localhost:1455/auth/callback`, so
ask must answer one GET. `g-cqd/HTTP` was offered for it: a from-scratch HTTP/1.1, 2 and 3 server. Codex's refresh tokens
rotate and are single use, so how ask refreshes them decides whether two terminals can sign the user out.

## The probes

Ledger in `development/diary/2026-10-20-27.md`.

- **Does `g-cqd/HTTP` resolve next to ask's pins?** In a scratch package depending on its published `main`
  (`82dee19`) and ask's own Aemi revision: **REFUTED**. SwiftPM stops with "aemi is required using two different
  revision-based requirements", because HTTP follows Aemi's `main`.
- **What would it cost if that were fixed upstream?** With its Aemi requirement patched to ask's revision and ask's other
  four pins added, the resolved graph went from **8 packages to 15** (adding swift-crypto, swift-certificates,
  swift-asn1, swift-log, swift-metrics, swift-distributed-tracing, swift-service-context), and the `HTTPServer` product
  links HTTP/1, 2 and 3, WebSocket and a transport layer.
- **Is a sign-in's one GET worth that?** No measurement was needed to see the ratio, so none was made.

## Decision

1. The callback is a small listener on the Darwin sockets ask already loads (`LoopbackListener`, about 150 lines in
   `AskAI/SignIn`), with the checks a local listener needs, each pinned by a mutation: loopback only; only a GET of the
   exact path; a `Host` that is this machine on the bound port (DNS rebinding); exactly one value per parameter; a wrong
   or missing `state` ignored, so a stray request can neither end nor complete a sign-in; a provider error shown only as
   an allowlisted word; static pages that never echo the query; a read timeout, so a stalled tab delays the real
   callback by a second at most; a dedicated thread per wait, so two sign-ins do not wait on each other; the port free again
   however the wait ends.
2. If ask ever needs a real server (an extension host is a process, ADR-0028), `g-cqd/HTTP` is the first candidate, and
   the Aemi requirement is the first thing to settle with its owner.
3. Codex credentials are refreshed in one locked step: take an advisory lock beside the credential file (the system
   releases it if the holder dies), look again at what is stored, refresh, save the whole replacement. A failed refresh
   leaves what was stored and is never retried: the server may already have spent the token.
4. When port 1455 is taken, ask takes the address the browser ended on, pasted, with the same `state` rule: no
   bare-code shortcut. `--device` is the sign-in for a machine with no browser.
5. ask names itself `ask` as the originator. There is no default Codex model: the only catalogue to hand is pi's, which
   cannot be checked against an account, so the user names one with `--model` until roadmap 0038 reads the live list.

## Consequences

- Two `ask` processes cannot spend one refresh token twice. Claude's refresh has the same read-refresh-save shape and no
  lock; whether Claude's refresh tokens are single use is unprobed (roadmap 0044).
- Everything about the live service beyond what diary 27 probed is from pi's implementation, not observed here.
  The first real `ask login codex` is the test of the authorize step, which scripts cannot reach (a bot check answers 403).
