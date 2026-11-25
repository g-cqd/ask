---
status: accepted
date: 2026-10-19
---

# 0026 — Compaction is ask's own summarisation request, recorded as plain text

## Context

A session that outgrows the context fails, so ask must compact (roadmap 0030). The models API reports
Anthropic's server-side mechanisms:
- `context_management` with `compact_20260112`, which compacts inside a normal request, by default at
  150,000 input tokens;
- a request parameter, `compaction: {type: "summarize"}`.

Both return a signed `compaction` block that later requests send back. Doing it in ask is the alternative.

## Probes (`/tmp/compact-probe.py`, diary 2026-10-19-11)

On claude-sonnet-5-5, through the subscription gate:

| Probe | Result |
|---|---|
| A summarize request | accepted (200) with the `compact-2026-09-04` beta; stop reason `compaction` |
| What the block holds | readable `content` and a `signature`; no `encrypted_content` |
| Usage of that request | zeros at the top level; the real counts are under `usage.iterations[]` |
| Follow-up with the signed block | recalled both facts from before the boundary |
| Follow-up with its content as plain text | recalled both facts as well |

## Decision

ask summarises with an ordinary request, and records the summary as `.compaction(summary:firstKept:)`.

- **The request** is the context as last sent, plus one instruction. Its prefix is therefore read from
  cache; only the instruction and the newest messages are new.
- **When:** before a request, once the newest response's prompt plus its reply reaches `--compact-at`. The
  default is 150,000 tokens, the server's own default trigger. A response stopped by a full window also
  triggers it.
- **What stays.** About 80 KB of recent text is kept verbatim, and the kept tail never starts at a tool
  result. The file keeps the whole history; only the context shrinks.

## Why not the server's

- **The plain text did as well** in the probe as the signed block.
- **Neutrality.** Plain text works with the second provider (0026) and keeps the session file readable and
  provider-neutral (ADR-0019).
- **Fewer surprises.** Server-side automatic compaction would change the context inside a request the loop
  thinks it controls. Its usage reports zeros where ask reads counts, and it cannot be combined with
  other context edits.

## Consequences

- **Each compaction costs one extra request.** Its cached prefix makes it cheap at the threshold. The
  first request after it starts a new prefix and is uncached.
- **The summary partly restates ask's standing instructions,** even when told not to. It costs a few lines;
  measured live.
- **Revisit when** a second provider exists, or if the server's summaries measure better on long real
  sessions. Roadmap 0032 (a summary kept up to date in the background) builds on this seam.
