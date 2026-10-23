---
status: accepted
date: 2026-10-22
---

# 0061 — A held drag scrolls on a timer and waits for the frame it needs

## Context

TerminalKit's `SelectionController` reports a scroll request when a drag reaches the first or last transcript row, and ask answered
it once per motion report. A terminal sends no report while a button is held still, so the scroll stopped when the hand did and a
long selection needed continuous wiggling. The kit deliberately owns no timer (ADR-0027); the host owns policy and time.

The selection maps a cell to content through the **frame that was drawn**, and the frame is drawn on another thread. After a scroll,
the line that came into view is not in any frame the input side holds yet.

## Decision

- The controller records the edge (`DragAutoscroll`: request, last cell, and the scroll position at which the selection was last
  extended). `isAutoscrolling` is true while a drag is held, the mouse is on, and either more transcript lies that way or the line
  that last scrolled into view is not yet in the selection.
- The driver runs one timer task exactly while `isAutoscrolling` holds (`AutoscrollTimer`) and posts `.tick` into the same event
  stream as keys and updates, so state keeps its single owner. The interval is a constant 50 ms, about twenty lines a second. It is
  not a `ui.*` key: nothing says anyone needs to change it, and the configuration refuses keys without a feature behind them.
- `tick()` acts only on a frame whose recorded `scrollback` equals the controller's. A stale frame makes it wait for the next tick,
  so it never extends the selection over a position it has not seen and never scrolls twice for one frame. It first extends the
  selection to the pointer in the new frame, then scrolls one more line if there is room.
- Release, a click, typing, a fold toggle, `ui.mouse false` or the pointer returning inside the content clear the condition, and
  the next event cancels the timer.

## Consequences

The rate is bounded by the render thread, not only by the timer, which is the honest limit: a slow frame slows the scroll instead of
selecting text nobody saw. Streaming output that grows the transcript during a held drag is handled the same way, because the
condition is re-evaluated after every event. A timer tick that changes nothing does not draw.

Scrolling the other way with the pointer **below the transcript** (over the prompt or status) uses the same edge, since the kit
treats any row at or below the last scrollable one as the bottom edge. Edge scrolling inside the *input* is separate work.
