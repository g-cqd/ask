---
status: done
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

## Done (2026-10-29): items 1 and 3

- **A drop after text was shown is carried on, for every provider.** The loop keeps the text that arrived (`ResponseAssembler.partial()`:
  text blocks only; reasoning and a half-sent tool call are never sent back), waits the retry delay with "Reconnecting..." in the status
  bar, records it as the response (stop reason `ask_connection_lost`) followed by `AgentLoop.reconnectionPrompt`, and asks again. One
  generic user turn rather than Anthropic's trailing-assistant continuation, so every API takes it; the output-limit continuation works
  the same way. Only reasoning shown: the request is sent again whole. Consecutive drops are bounded by the retry policy's attempts
  (`DropCount`, reset by a whole answer). A resumed session replays the prompt as `continuedAfterDrop`, which draws nothing; `ask -p`
  says it on standard error.
- **A stream that just ends before the answer's end is a drop too** (`ClosedEarly`): the probe found that a socket closed between two
  events reaches the loop as a normal end, then a protocol error ("incomplete(openBlocks: [0])"); no layer below saw it.
- **The screen never ends for it:** run and command errors are reported by the conversation; only terminal failures reach the process exit.
- Tests: `AgentLoopReconnectTests` (carry on, reasoning and a cut call dropped, reasoning only retried whole, a stream that ends early,
  drops bounded, replay); mutations of the bound and of the partial's filter turn them red. The old "not retried after text" test is
  replaced. `probe-reconnecting.py` gains a server that streams "FIRST HALF" on a chunked response and closes the socket: through the
  release binary, both halves are shown, no error block, and the second request carries the partial answer and the prompt.

## Done (2026-10-29): item 2

- **Offline, a failed request waits for the network.** On any retryable failure the loop asks the system's path (`SystemNetworkPath`,
  `NWPathMonitor`, made only once a request has failed): with no route it says `waitingForNetwork` and waits for one, up to 5 minutes
  (`networkWait`), then sends again at once; the wait spends no attempt and no backoff, since the network coming back is the signal. A
  network that does not come back ends the turn with the failure; stopping the turn stops the wait. With a route, the usual backoff applies.
  A drop part way waits the same way, then carries on. The status bar says `Offline, waiting for the network...` in the warning colour,
  until the next attempt, the model's answer or the run's end; `ask -p` says it on standard error. No error classification was needed:
  the path itself says whether the Mac is offline.
- Tests: `AgentLoopNetworkWaitTests` with a played path (waits not counted as attempts, a ceiling, no wait online, a drop part way, a
  permanent failure never waits; a mutation that never waits turns them red), `SystemNetworkPathTests` (a wait returns by its limit and when
  stopped, whatever the Mac's network), `OfflineStatusTests`.
- Cold start, linking the Network framework: median 13.34 ms against 13.10 ms for the previous commit (30 alternated runs), within noise.
- Item 4: a carried-on answer is one partial response and one continuation in the session; its usage is the partial's (the provider billed
  that request), not counted twice.

Not verified: a real loss of the Mac's network (the wait was tested with a played path and the system path's limits only).

