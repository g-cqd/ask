---
status: done
blocked-by: []
date: 2026-11-11
---

# 0223 — The folder ask works in, on the status line

The owner, note n6 (2026-11-03, task t195): "(configurable: on/off, full path/last path component, leading/trailing/order) show path
in the status bar"; note n63 (2026-11-10): "it'd be interesting to provide in the status bar the path at which ask is running". Note
n7, "provide ways to configure the status bar", is left for later (the owner, 2026-11-11).

## The owner's answers (2026-11-11)

1. **Scope:** the path only, configurable. A configurable status bar (n7) later.
2. **Default:** on, as the last folder.
3. **Where:** right after the mark.
4. **Narrow:** it shortens to the last folder, then goes, before the context's use and the model's name.
5. **Git:** not now; it has its place later in the roadmap (0186).

## The plan, as built

- `ui.statusPath`: `"folder"` (default), `"home"` (`~/src/shop`), `"full"`, `"off"`; `ui.statusPathSide`: `"leading"` (default),
  `"trailing"`. The names are mine.
- The mark becomes a piece of its own, attached to the model's name: never dropped alone, dropped with it, as when the two were one
  piece. Its colour follows it, not the line's first cell. The folder sits between them, with a priority below the context's use.

## Done when

`StatusPathTests` (5 issues red on stubs) and `StatusPathConfigurationTests` (red on a stub) pass; `Scripts/probe-status-path.py`,
6 checks through the release binary, passes, and the build before fails it.

## Not done

- n7's configurable bar: which pieces show and in what order.
- Not checked in a real terminal.
