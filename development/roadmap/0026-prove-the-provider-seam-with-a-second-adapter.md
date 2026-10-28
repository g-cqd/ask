---
status: done
blocked-by: []
date: 2026-10-19
decision: ADR-0019
---

# 0026 — Prove the provider seam with a second adapter, before Spettro depends on it

ADR-0019 let tools proceed without a second provider on the claim that the seam, `ModelRequest` in and
`ModelEvent` out, is protocol-shaped and that a second adapter "must map onto it, never widen it". ADR-0021
holds the *names* (no provider word outside provider directories). It cannot hold the *shape*. This entry
tests the shape, in a scratch adapter, before the real second provider is written against it.

## The claims to try to refute

Each is written so a probe can fail it. Record verdicts in the diary.

1. A chat-completions-shaped stream (text deltas, indexed tool-call fragments, a finish reason, a usage
   chunk, no block start/stop) maps onto `ModelEvent` through `ResponseAssembler` with no change to either.
2. The assembled response survives `WirePayload` encode → decode → `RequestContext` → the second adapter's
   request, with the tool-call ids unchanged. A provider without call ids (some do not) is the hard case.
3. A stop reason that is not Anthropic's persists as `.other(...)` and resume behaves the same as for a
   known one. `StopReason.wire` strings are Anthropic's today.
4. `thinking` without a signature, and reasoning that needs provider-private round-trip state, can be
   carried. Today the block requires a signature and has nowhere to keep provider state.
5. Tool results that are not plain text, and a user turn with an attachment, have somewhere to go.
6. Compaction can learn the context window. No model catalog exists.

## Done when

A scratch adapter and its tests exist, each claim has a recorded verdict, and for each refuted one either the
neutral type is widened by a new ADR (never silently) or the claim is written down as a limit. If the seam
holds, a **provider contract test** (a suite every adapter's scripted stream runs through) is kept, so the
second and third providers cannot bend it.

## A finding that belongs here

dolly reports `ContentBlock` (an assembled response's blocks) and `RequestBlock` (a request's blocks) as a
near-clone: the same cases bar `unrecognized` and `toolResult`. The duplication is accepted in the code, with
this entry as the reason. Claim 5 (content that is not plain text) is where one block vocabulary, or a shared
part type both are built from, would be decided; do not unify them before that.

## Not this entry

Writing Spettro itself (0010). Auth, model catalogs and live probes stay there.

## Done (2026-10-19, ADR-0027)

Answered with a real second adapter, not a scratch one: the OpenAI-compatible provider, tested against streams
recorded from llama.cpp, MLX and Ollama and run end to end through `ask -p` on all three. Verdicts on the claims:

1. **Held.** Chat-completions streams map onto `ModelEvent` through `ResponseAssembler` with no change to either.
2. **Held.** Assembled responses persist and replay; a server that sends no call id gets a generated one.
3. **Held.** Finish reasons map onto the neutral `StopReason` (`stop`, `tool_calls`, `length`, `content_filter`).
4. **Held, with one fix in the Anthropic adapter.** Reasoning without a signature is kept with an empty one; the
   Anthropic encoder now drops unsigned thinking, which it would otherwise have sent and had refused.
5. **Not tested.** Non-text tool results and attachments: neither provider sends them yet.
6. **Open.** No model catalog: context windows are not known, so compaction uses its own threshold.
