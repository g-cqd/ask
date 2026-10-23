---
status: accepted
supersedes: ADR-0033
date: 2026-10-22
---

# 0061 — Codex reasoning is replayed inside the tool loop, and dropped if refused

## Context

ADR-0033 kept a Responses reasoning item whole behind a provenance marker and sent none of it back, because nothing had been
probed against a real account. The cost was unmeasured. Roadmap 0040 owed four things: the `include` option, a real stream,
the replay shape and what the item's id must pair with, and what replay buys. Probed on the live ChatGPT Codex backend with
ask's own credentials (diary 2026-10-22-10; the probe is archived in `docs/research/probes/ReplayProbe.swift.txt`):

- Sealed content arrives with or without `include: ["reasoning.encrypted_content"]`.
- A reasoning item is accepted with or without its id, in front of a call that carries no id (ask's shape), alone, before a
  new user message, and when replayed to another Codex model (gpt-6.1-sol to gpt-6-luna).
- One altered character, a truncated value and invented text are each refused: HTTP 400, `invalid_request_error`, code
  `invalid_encrypted_content`, `param: input`. An item with an id and no sealed content is accepted.
- Where the model reasons between steps, replay cut median reasoning from 318 to 64 tokens and the step from 16.1 s to 6.4 s
  (n=8), at about 5x the input (145 to 816 tokens). Over a four-step loop of real reasoning: input 1279 to 2776, output 1082 to
  799, wall time 51.9 s to 34.7 s, correct answers 3/4 to 4/4 (n=4). Where it does not reason, nothing is returned to replay and
  the request is identical (2783 input tokens either way).
- Prompt caching did not help the measured steps (cached tokens were 0 in all but one).

## Decision

1. **The Codex dialect replays reasoning; no other Responses endpoint does.** Direct OpenAI accounts and local servers are
   unprobed and keep ADR-0033's behaviour. The flag is `ResponsesDialect.replaysReasoning`.
2. **Only the tool loop in progress.** Reasoning is sent for assistant messages after the latest prompt (a user message with
   text). Older reasoning costs input tokens on every request and nothing shows it helps.
3. **Verbatim, in order, ahead of the call it preceded.** The stored item (type, id, summary, sealed content) is spliced in;
   calls still carry no item id. `include` is not sent: it is not needed on this backend.
4. **Nothing else can ride in that slot.** The stored payload is parsed and must be a `reasoning` object with non-empty sealed
   content, or it is not sent. A session file can be edited.
5. **A refusal costs one request, once.** If the server refuses with `invalid_encrypted_content` before any event, the request
   is sent again without the reasoning, the person is told, and the run stops replaying (`ReasoningReplayGate`). A refusal after
   events were delivered is not retried, so nothing is shown twice. The kind is decoded from the server's code, not its wording.
   This is what makes a session resumed on another account or after a key change a notice, not a dead run.
6. **`ModelEvent.notice`** carries such provider repairs to the screen and to `--print`. It is not part of the response.
7. **Unchanged from ADR-0033:** foreign signatures stay behind the `ask-foreign:` marker, the Anthropic encoder sends only what
   is its own, and the decoder stores only reasoning that arrived with sealed content.

## Consequences

- A Codex tool loop where the model reasons runs fewer output tokens and finishes sooner, and bills more input. Whether that
  is cheaper depends on pricing and on the subscription's accounting, which is not known.
- Input grows with each reasoning item in the loop (about 500 to 1000 tokens each). Four steps were measured; a long loop was
  not, and neither was whether compaction should drop the items earlier.
- Not established: direct OpenAI accounts (the ADR-0033 caveat stands there), reasoning older than the current prompt, other
  efforts and models, a second real account's refusal (the refusal path is tested against the observed body, and the
  decoder's own payload was accepted by the live server in eight runs), and `CodexProvider`'s gate wiring, which sits in the
  composition root without a unit test.
- Reasoning summaries are still shown from the stream; nothing about display changed.
