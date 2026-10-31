---
status: done
blocked-by: []
date: 2026-10-31
---

# 0167 — Claude's thinking is shown, not streamed empty

Owner wish (2026-10-30 22:21): Pi shows non-empty thinking blocks for Claude subscription sessions; ask showed empty ones.

## Why

Claude models from Opus 4.7 on default to `display: "omitted"`: the thinking blocks stream with an empty `thinking` field and only the
signature (Anthropic's "Extended thinking" and "Thinking with tool use" pages, read 2026-10-31). ask never sent `display`, and with the
default level (the owner's: no `thinking` set, on `claude-opus-5-5` and `claude-sonnet-5-5`) it sent no thinking configuration at all.
Pi's `anthropic-messages` (pi-ai, installed copy) sends `display: options.thinkingDisplay ?? "summarized"` in both modes, and on the
subscription.

## Done (2026-10-31)

- Adaptive and budgeted thinking ask for `display: "summarized"`; `disabled` and `between_tools` take none (the latter takes no other
  field).
- `ThinkingControl.adaptive`, chosen for the default level by `ThinkingControl.providerDefault(descriptor:)` on a Claude model whose
  catalog offers adaptive thinking and no way to disable it (Opus 5.5, Sonnet 5.5, Fable, Mythos): per Anthropic's table, "no thinking
  field" is adaptive thinking there, so sending it changes only the display. Read from the cached catalog, never the network at start.
- Left alone: the default level on models where thinking is optional (Opus 4.8 does not think unless asked; Opus 5 does, but its catalog
  entry reads like Opus 4.8's, so nothing tells them apart without naming models).
- Tests: `ThinkingDisplayTests` (red first); `probe-agent-run.py` section Y, red on the morning's build.

Not verified live: a summarized thinking block from the subscription in ask's own screen. Pi's use on the same subscription is the
evidence that the gate accepts it.

## Found live, fixed (2026-10-31, later)

Owner (same day): ask still shows many empty thinking blocks where pi-integrations does not.

**The bug.** With the morning's build, `claude-opus-5-5` on the subscription still streamed empty thinking (an `ask -p` run: a
thinking block with a signature and no text; `ask config` said "provider defaults; no control sent"). The default level read the
model's catalog entry from the cache only, and the cache is scoped by a fingerprint of the access token. A subscription token is
refreshed every few hours, so after a refresh the cache belonged to "another" scope and read as nil, and nothing was sent. The tests
and probe ran with a fresh cache, so they never saw it. Pi always sends `display`, so it never depends on a catalog.

**The fix.** When the cache cannot be used, the default level is looked up just before the first request, as a chosen level
already was (`ThinkingDiscovery`, `pending`). `ThinkingControl.select(.providerDefault, …)` gives the adaptive control on a Claude
model that always thinks. A failed lookup for the default sends nothing, as before, rather than failing the request. The lookup
also rewrites the cache under the current token.

- Test: `ThinkingDisplayTests`, written first and red.
- Checked live, same prompt, same model: the thinking block now holds the summary. The next start read the refreshed cache:
  "provider default (adaptive), its thinking shown".

Still to consider: the cache could be scoped by account, not by token, so a refresh does not cost a lookup. That needs a stable
account identity in the subscription's credentials.
