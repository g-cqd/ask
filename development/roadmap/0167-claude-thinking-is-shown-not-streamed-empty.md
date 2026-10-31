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
