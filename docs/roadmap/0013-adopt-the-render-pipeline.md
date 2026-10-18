---
status: not-started
blocked-by: 
date: 2026-10-18
---

# 0013 — Adopt TerminalKit's render pipeline

`ask` today has a `ContiguousArray<UInt8>` and a `switch` over bytes. `ScreenBuffer`, `DiffRenderer`,
`DirtyTracker` and `RenderPipeline` all exist in TerminalKit, are used by nobody in `ask`, and are exactly
the machinery a real agent UI needs.

## Why this entry exists

`0014` measures pixel chrome, and chrome lives inside `RenderPipeline.flush()`. So pixel work and
renderer adoption are the same dependency. Doing them separately means building a renderer twice.

## What lands

- `ScreenBuffer` and the double-buffered `DiffRenderer`, so a repaint costs a **diff** rather than a
  full redraw — the first item in the white paper's order of attack.
- `DirtyRegions` / `DirtyTracker`, so only what changed is recomputed.
- `RenderPipeline` for frame bracketing and flush, keeping DEC 2026 synchronised output on every frame.
- `ask`'s line editor expressed against the screen model instead of appending to a byte array.

## The invariant to keep

Nothing instruments the hot path. `AskTUI`'s own comment says it: a program that reports its own latency
reports the flattering number. Timings come from the PTY harness.

## Risk

This is the largest single change so far, and it replaces code that currently works. That is the point —
but it is also why it wants its own commit per slice, and why `0009` should not start before it lands:
the agent loop needs a screen model to render streaming text into.

## Done when

`ask` renders through `RenderPipeline`, a repaint emits a diff rather than a full redraw, synchronised
output still wraps every frame, and all four budgets still pass.

## Reordered (ADR-0019)

`0014` no longer blocks this entry: its last item needs a renderer, so the dependency runs the other way. The agent loop no longer waits for this entry either; it lands headless first. This is what the *interactive* loop needs, and it comes next after the headless loop.
