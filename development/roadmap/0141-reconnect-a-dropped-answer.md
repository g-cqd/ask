---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0141 — Reconnect a dropped answer: wait for the network, and carry on an answer already shown

Owner report (2026-10-29): a turn ended with the whole `NSError` of `NSURLErrorDomain -1005` ("The network connection was lost.") against
`https://api.anthropic.com/v1/messages`, printed as `ask: Error Domain=…`. The owner asked for a reconnection mechanism.

## What exists

- `8c7d539` (2026-10-29 09:07): the transport passes on the system's sentence, not the user-info dump; a dropped connection
  (`HTTPTransportError.interrupted`, `ProviderStreamError.interrupted`) is retryable. The running sessions at the time were built on 28 October,
  before it, which explains the dump.
- 0120: "Reconnecting…" in the status bar instead of a block.
- `RetryPolicy.standard`: five attempts, waits of 1, 2, 4 and 8 s. `AgentLoop+Streaming` retries **only while nothing has been shown**
  (`guard !shown`), so a drop part way through an answer ends the turn.

## What is missing

1. **A drop after text was shown.** Keep what arrived, then ask again so the answer goes on: the partial assistant text as the last message
   (Anthropic continues a trailing assistant turn; the OpenAI-compatible APIs need a "continue" user turn instead), or a fresh answer that
   replaces the partial one with the replacement visible. Decide which per provider; thinking blocks and a half-streamed tool call
   (its JSON cut) are dropped, never sent back incomplete.
2. **Wait for the network instead of a fixed count.** Offline (`-1009`), lost (`-1005`) and a changed network (`-1001`, `-1020`): watch the
   path (`NWPathMonitor`) and resume when it is satisfied, with the status saying so, up to a ceiling (minutes, not 15 s), cancellable with
   the interrupt keys. `URLSessionConfiguration.waitsForConnectivity` covers the request that has not started; the monitor covers the rest.
3. **Never end the session for it.** Check that no transport error reaches `fail("ask: …", code: 70)` from the screen; a turn may fail, the
   screen stays. A test with a scripted transport that drops mid-body, and a probe that cuts the fake provider's connection.
4. **Idempotence.** A retried request is a new request: tokens are counted twice in the usage line only if the provider billed twice;
   the session records one assistant message, not a partial plus a full one.

## Probes and tests

- Scripted transport: drop before the head, after the head, after N text events, inside a tool call's input; each ends in one assistant
  message and no error block.
- `probe-reconnecting.py` gains a case where the fake server closes the socket mid-answer, and one where it refuses connections for 20 s.
