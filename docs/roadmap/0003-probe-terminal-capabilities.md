---
status: not-started
blocked-by: ["0014"]
date: 2026-10-18
---

# 0003 — Probe the terminal instead of guessing at it

`TerminalCapabilities` decides what the host can do from `KITTY_WINDOW_ID` and `TERM_PROGRAM`. Those
are hints, not proof, and they cannot see whether the terminal supports DEC 2026 or the kitty keyboard
protocol.

**Done when:** capabilities are established by actively querying the terminal, the answer is cached
for the session, and the probe is itself tested against a mock terminal that answers correctly, lies,
and times out.

## A false positive, measured rather than argued

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