---
status: in-progress
blocked-by:
date: 2026-10-18
---

> **Partially landed, in TerminalKit (ADR-0014), with a measured constraint that changes how `ask` must
> use it.** The probe exists and is tested. What remains is the integration, and the measurement below
> decides its shape.

# 0003 — Probe the terminal instead of guessing at it

`TerminalCapabilities` decides what the host can do from `KITTY_WINDOW_ID` and `TERM_PROGRAM`. Those
are hints, not proof, and they cannot see whether the terminal supports DEC 2026 or the kitty keyboard
protocol.

**Done when:** capabilities are established by actively querying the terminal, the answer is cached
for the session, and the probe is itself tested against a mock terminal that answers correctly, lies,
and times out.

## Done — the probe, in TerminalKit

`TerminalProbe` asks rather than guesses: cell size from the window, synchronised output via DECRQM,
keyboard protocol via `CSI ? u`. Every field is **optional, and nil means unknown** — a terminal that
ignores a query has not said it lacks the feature. Graphics support is not queryable and stays a hint,
kept out of the measured result entirely.

Eleven tests cover the three cases this entry names — answers correctly, lies, and times out.

## Measured: a blocking probe costs 520 ms

Two queries on a PTY whose far end never replies: **518.5 / 519.8 / 520.1 ms**. A terminal that does
answer costs microseconds, so the whole cost is refusal — and Terminal.app is exactly such a terminal.

**Against a 25 ms cold-start budget that is twenty times the budget.** So `ask` must not gate its first
frame on a probe. Either run it off the startup path and keep conservative defaults until answers arrive,
or shorten the deadline and accept false negatives under load. The first is right; the second trades a
correctness bug for latency.

That is a design decision this entry now owns, and it is the reason the status is `in-progress` rather
than `done`.

## The false positive that motivated it

`0014`'s harness reported `supportsKittyGraphics: True` for **Terminal.app**, which does not speak the
kitty graphics protocol. The cause was environment inheritance, not the terminal: the agent session runs
inside kitty, so `KITTY_WINDOW_ID=4` was set in its environment and inherited by every terminal the
launcher started. TerminalKit's check is `KITTY_WINDOW_ID != nil || …`, so one inherited variable was
enough to return `True` for a terminal that cannot render the protocol.

That is not an edge case. It fires whenever the launching process was inside kitty and then spawned or
exec'd another terminal — a normal shape for a launcher script, a task runner, or a multiplexer.

With the launcher's own detection variables unset, so each terminal reports **its own** values:

| Terminal | `KITTY_WINDOW_ID` | `TERM_PROGRAM` | guess | real cell pixels |
|---|---|---|---|---|
| kitty | 1 (own) | — | True | yes, 14×25 |
| ghostty | — | `ghostty` | True | yes, 16×34 |
| wezterm | — | `WezTerm` | True | yes, 7×16 |
| Terminal.app | — | — | **False** | **yes, 7×14** |

So the entry's central claim is now supported by a measurement: the env-var guess is not merely
unproven, it returned the **wrong** answer in ordinary use.

## Two axes, not one

Every terminal measured — **including Terminal.app** — reports real, drawable cell pixel dimensions. So
pixels are not the axis that separates them. What Terminal.app lacks is the kitty graphics **protocol**.

`TerminalCapabilities` currently conflates the two into one boolean, and `supportsPixelChrome` requires
both. A probe that only measured pixel dimensions would wrongly conclude Terminal.app can draw chrome.
This entry must therefore establish them separately.

## Notes

The keyboard-protocol question is not only about capability. Enabling the kitty keyboard protocol is the
fix for ESC-ambiguity latency, which is one of the four performance budgets. The measurement comes after
this entry lands, not before.

`blocked-by` was `0001` and is now `0014`: `0001`'s remaining work is Atelier's consumer switch, which
`ask` does not depend on — see roadmap `0005` for why that dependency was recorded in the first place.