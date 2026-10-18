---
status: accepted
date: 2026-10-18
supersedes:
---

# 0008 — Both layouts are first-class: a pixel layout and a character layout

## Context

Roadmap `0015` set out a fork in the road and deliberately left it open:

> Either the compact layout is the baseline and pixels only refine it, or the layouts diverge and both
> need designing.

The cheaper answer is "baseline plus refinement": design one layout in cells, then let pixel chrome
decorate it where the terminal allows. That halves the design surface and guarantees the two never
disagree, because there is only one.

The cost of that answer is that the compactness is capped by the cell grid. Pixel drawing can place a
rule *between* rows, tint a band without occupying one, and put a scrollbar thumb at a true fractional
offset — none of which a cell layout can express. If the point of pixels is room for content, refinement
of a cell layout gives back exactly the rows the pixel version was supposed to recover.

## The probes

**Probe 1 — how large is the fallback population?** Listed the installed terminals and looked for
Terminal.app in the two places macOS keeps it.

**CONFIRMED that a fallback audience exists, but REFUTED in its stated reason.** Probed: kitty, ghostty
and wezterm speak the kitty protocol; Terminal.app is present at
`/System/Applications/Utilities/Terminal.app` and ships with macOS, so the character layout has an
audience that cannot be deferred.

But `0014`'s measurement then showed **Terminal.app reports real cell pixels** — 560×336 with a 7×14
cell, `drawable: True`. So pixels are *available* there. What Terminal.app lacks is the kitty graphics
**protocol**, and those are two independent axes.

The original probe merged them, which is why it looked like a pixel problem and is actually a protocol
problem. Corrected here: the character layout is required because the graphics protocol is unsupported,
not because cell pixels are unavailable. The conclusion survives; the reason was wrong, and the two
reasons would lead a reader to different designs.

**Probe 2 — is the two-layout cost avoidable?** Read `PixelChrome`'s three primitives and
`ChromeElement`'s placement semantics.

**PARTLY.** `.fill` and `.line` are genuinely decorative — a character layout can approximate both with
cell backgrounds and box-drawing runes. `.bar` is not: a rect placed at a pixel offset inside a cell has
no character-grid equivalent, so the scroll thumb is the one element that must diverge rather than
degrade. So the layouts are *not* fully redundant, which is what makes "baseline plus refinement"
insufficient for the element that motivates the work.

## Decision

**Both layouts are designed and maintained as first-class.** `ask` ships a pixel layout and a character
layout, chosen at runtime by measured capability, and both are held to the same parity contract.

## The parity contract

Because two layouts drift unless something forbids it, and nothing forbids it by default:

- **Identical across both:** information architecture, ordering, what is visible, every action and
  keyboard binding, and the reading order of content.
- **Free to differ:** how structure is drawn, spacing, density, colour use, and the scroll thumb.

The test for a divergence is whether a user would have to *learn* something new. If they would, it
belongs in the parity contract. If they would not, it is presentation and the two may differ freely.

Both layouts are exercised by tests. A layout that only runs on the machine it was written on is not a
layout, it is a screenshot.

## Consequences

- The UI surface roughly doubles, and that cost is accepted rather than avoided. It is the price of a
  compact layout that is actually compact instead of a cell layout with decoration on top.
- Capability detection (`0003`) becomes load-bearing for correctness, not just for polish: it selects
  between two shipped layouts. A wrong answer shows a user the wrong interface, not a missing decoration.
- `0014`'s measurement is a precondition for both, because a layout cannot be selected on a capability
  that has never been measured.
- The character layout is not a degraded mode. It is a design with its own density decisions, and it must
  not look like the pixel layout failing to render.
- A parity test that runs the same scenario against both layouts and asserts the shared contract is
  worth more than either layout's own tests, because drift between them is the failure mode neither can
  detect alone.

## Follow-ups

- The character layout's own density budget is undecided: how compact it can be before it stops being
  legible. That belongs to `0015`, not here.
- Whether Terminal.app can in fact render kitty graphics is **unverified**. The measurement shows it
  reports cell pixels; that is not the same claim as protocol support, and this ADR does not assert it
  either way. `0015` needs it answered rather than assumed.
- Nothing in this decision says which is the default when capability is unknown. That falls to `0003`'s
  degraded-mode policy and should be decided there.