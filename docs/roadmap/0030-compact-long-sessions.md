---
status: done
blocked-by:
date: 2026-10-19
decision: ADR-0026
---

# 0030 — Compact long sessions

A session that outgrows the model's context window fails, however robust the rest of the run is. The parts
that exist already:
- `SessionPayload.compaction(summary:firstKept:)`;
- `RequestContext` carries the summary at the front of the context;
- `SessionTree.context()` starts from the compaction boundary;
- the request reports usage, so the size of the prompt is known after every response.

## The work

- **When.** Compact once the last prompt plus a reserve for the reply passes a share of the model's window.
  Probe the window rather than assume it, and probe what the API says when the prompt is too long, so that
  the overflow error itself also triggers compaction.
- **What.** Summarise everything before a kept tail of recent turns in one model request. Record the summary
  as a `.compaction` entry, so the full history stays in the file and only the context shrinks.
- **Shown.** A notice on the screen and on stderr. The replay shows the summary.
- **Cache.** The summary changes the prefix, so the first request after compacting reads nothing from
  cache. Measure the cost and the saving.
- **Research to re-read:** `docs/research/` and `Scripts/probe-pi-compaction-context.mjs`, on how other tools
  choose the kept tail.

## Done when

A scripted session past a small, injected window compacts and continues. The request after compacting
holds the summary and the kept tail only. A live run compacts and still answers about something from
before the boundary.

## Done (2026-10-19)

- **The trigger** is `--compact-at`: 150,000 tokens by default, and 0 means only when the window is full.
  `contextWindowExceeded` also triggers it.
- **The summary** comes from ask's own cached-prefix request (ADR-0026).
- **What stays:** an 80 KB kept tail, and the whole history in the file.

| Evidence | Where |
|---|---|
| 6 loop and rule tests; 9 compiling mutations caught | unit tests |
| Summary request, then summary before the kept tail, full history kept | probe E (fake server, default threshold) |
| A code word recalled after two compactions | live run |

The window is 1,000,000 tokens for claude-sonnet-5-5, and the models API reports it; ask does not read
it yet.
