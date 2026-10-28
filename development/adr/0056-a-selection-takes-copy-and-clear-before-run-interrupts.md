---
status: accepted
date: 2026-10-22
---

# 0056 — A selection takes copy and clear before run interrupts

## Context

ADR-0046 makes copy-on-select tunable, but turning it off left a highlighted selection with no copy key. Ctrl+C always quit or
aborted, and a click on selected text could open the folded header underneath it. Roadmap 0051 requires the drag/selection contract
to take precedence over component actions.

## Decision

- With a selection, **Ctrl+C copies and clears it**. With no selection, Ctrl+C keeps its existing abort/quit meaning. Legacy control
  bytes and protocol-encoded Ctrl+C have the same meaning; no feature depends on Command or Option reporting.
- With a selection, **Escape clears it** before it can abort a running turn. A subsequent Escape has its existing meaning. *(Since ADR-0104 that meaning is nothing: Escape no longer aborts a turn, and Ctrl+C with no selection is a ladder. The selection rules here stand.)*
- A single click inside selected cells clears the selection and never activates the component underneath it. A click outside the
  selection can still activate that component. Double and triple clicks retain word and line selection.
- A pending sandbox approval question retains its existing Ctrl+C abort contract. Copy never answers or bypasses a consent question.
- The status line explains copy/clear while text is selected. Otherwise, while mouse reporting is enabled, it names the measured
  native-selection bypass (Shift, or fn in Terminal.app), or names `ui.mouse` for an unknown terminal.
- Copy feedback says what actually happened: a terminal write was **sent**, host pasteboard work was **queued**, or copying failed or
  was unavailable. No OSC 52 acknowledgement or host-command completion is invented.

## Consequences

Copy-on-select off is usable without changing the terminal's native copy binding, and interrupting a turn remains one key once the
selection is consumed. The status row changes alongside a selection, but unchanged transcript rows still remain untouched.

The host pasteboard command is still asynchronous; its eventual exit is not yet reported. This ADR deliberately distinguishes a
queued request from a confirmed clipboard write. PTY and unit-test evidence is in diary 2026-10-22 (1).
