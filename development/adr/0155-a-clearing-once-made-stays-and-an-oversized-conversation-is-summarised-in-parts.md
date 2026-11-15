---
status: accepted
date: 2026-11-15
---

# 0155 — A clearing once made stays made, and a conversation too long for the window is summarised in parts

Extends ADR-0030 (decision 5, the summary's fallbacks) and the light compaction of roadmap 0032 (`ContextClearing`).

## Context

A session ran 546 requests on a model with a 1,048,576-token window, then was continued on one with 1,000,000. The first request
was refused: `prompt is too long: 3330961 tokens > 1000000 maximum`, and the run ended with "does not fit the model's context
window, even after compacting". The session had never been near its window: its requests had stayed between 62,000 and 417,000
tokens. Ledger in `development/diary/2026-11-15-09.md`.

Three things, each enough to end the run:

1. **The clearing was undone.** `ContextClearing` records nothing: how far it reaches is worked out for every request, from the
   sizes the responses reported, against a trigger that is 0.6 of the *current* model's compaction threshold. The session had
   cleared 14 times at 408,945 tokens. The new model's trigger was 463,200, no response had reported that much, so nothing was
   cleared: the request went from 607 KB of text to 14.4 MB.
2. **Nothing looked before sending.** Compaction is decided from the newest response's reported size (239,710), which described
   the cleared request, not this one.
3. **The summary's fallback did not fit either.** After the refusal, the summary request was the whole context (refused), then the
   part being replaced with each output clipped to 4,096 bytes: 2,487 outputs, 8.9 MB, about 2 million tokens. Refused, and the
   run ended. That fallback is bounded per output and not in total.

## Decision

1. **A clearing that shows in the sizes is kept.** A context only grows, so a response that reports far less than the one before
   it, with no compaction between, is a clearing that was made: the reach is at least the kept tail's cut at the earlier response,
   whatever the trigger is now. "Far less" is an eighth of the earlier size and at least 8,192 tokens; the two must be to the same
   destination and model, and neither a request a hook rewrote, since those change a count without a clearing. Nothing is
   recorded, as before: the reach is still read from the context alone, and a resumed session sends what it sent.
2. **A request clearly longer than the known window is not sent.** Its text in bytes over six, compared with the window the model
   declares or a server showed. It is treated as the refusal it would get: compact, send again. Applied only once a
   response has come since the last compaction, so the request that follows a compaction always goes to the server and a wrong
   estimate costs a compaction, never the run; not applied when no window is known.
3. **The fallback summary is made in parts.** The part being replaced, as it was last sent (cleared, then clipped), is cut at
   turn boundaries into parts of at most the window less the reply at three bytes a token. Each request carries the summary so
   far and the next part; its answer is the summary so far for the next. A part refused for its length is halved; one turn that
   still cannot fit, or a part the model answers with nothing, is recorded mechanically. A tool call's input in that record is
   clipped to 2,000 bytes, as the user's words already were.

## Why not record the reach

A `clearing` entry in the session would say exactly what was sent. It is a new entry kind (ADR-0144's rules for older builds), it
makes reading the session write to it on the request path, and it would not have helped the session that showed the problem,
which was written before it. The inference needs no migration and reads that session correctly (below). Revisit if a provider
turns up whose counts fall without a clearing often enough to matter.

## Evidence

- The session, replayed through `ContextClearing.reach` at the new model's trigger: reach `nil` and 14,446,724 bytes before the
  change; reach 3,006 of 3,041 entries and 606,622 bytes after, the same reach as at the old model's trigger.
- `ContextClearingTests`, `AgentLoopOversizedTests`: red before, with the error the session ended on; green after.

## Consequences

- A change of model, or of `compactAt`, no longer brings back what was cleared.
- A conversation of any length can be compacted, at the cost of one request per part: about four for the session above, uncleared.
  Only "compacting" shows while they run.
- A false inference clears earlier than the trigger asked: old outputs become stubs sooner, and the provider's cache breaks once.
  Known ways to get one: a provider that leaves cached tokens out of some counts, or drops an eighth of the context by itself.
- The mechanical record now says "the model wrote no summary" also for a turn no request could hold; the wording is left.
- Not addressed: why the model re-read five files about 300 times each while outputs were being cleared, and the generic HTTP 400
  one server answered the 14 MB request with. Both are in the diary as open questions.
