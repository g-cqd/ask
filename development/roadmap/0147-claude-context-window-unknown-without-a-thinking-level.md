---
status: done
blocked-by: []
date: 2026-10-29
---

# 0147 — A Claude model's context window was unknown unless a thinking level was set

Owner wish (2026-10-29 16:11): "Bug: Context filling information is not shown anymore". The owner suspected the session's forks and tree
navigation.

## Cause

Not the session. Probed in pyte at 120 columns with the owner's configuration: every Anthropic screen showed `—%/?` — resumed sessions and
fresh screens alike, for `claude-opus-5-5` and `claude-haiku-4-5-20251001` — while Codex showed `—%/500k` fresh and `40%/500k` resumed, and
Anthropic with `--thinking high` showed `—%/1.0M`.

`ModelDiscovery.resolveAll` returned early for Anthropic (`1048552`, 2026-10-21, "Keep Anthropic out of key-based catalog setup"), so the
window and reply limit in the cached `models-anthropic.json` were never read at startup. Only `ThinkingDiscovery.withNativeLimits` read them,
and only for an explicit thinking level. With no `thinking` in the configuration the window stayed nil: the status line showed `?`
(`UsageTotals.contextStatus` needs a limit), and `ContextBudget` sized compaction and replies without the real window.

## Fix

`ModelDiscovery.withAnthropicLimits`: for Anthropic, the run's own entry of a fresh cached list for the current sign-in, through
`AnthropicModelCatalog.cachedModel` (no network, no refresh, one entry decoded), merged by the same `withNativeLimits` the thinking path
uses, so an alias's own limits still win and a listed output maximum only lowers the reply budget.

## Verified

- pyte, fresh: `claude-opus-5-5` `—%/1.0M`, `claude-haiku-4-5-20251001` `—%/200k`, with `--thinking high` unchanged, Codex unchanged.
  Resumed: the long-session copy `8%/1.0M`, this session `6%/1.0M`. The previous build, same probe: `—%/?`.
- Cold start to the first prompt frame with the real configuration, 30 alternating runs per build on a loaded machine: median 40.3 ms
  before, 40.6 ms after (p90 46.3 and 42.9); no difference within the noise, under the 50 ms budget.
- Not covered by a unit test: the `ask` executable target has none, and nothing drives the binary from the test suite. The probe above is
  the check.

## Limits

No window is known when the cached list is missing, older than its freshness, or written for another sign-in, or when the stored
subscription token needs a refresh (the read never refreshes). Then the status line shows `?` until a list is fetched (`ask models
anthropic`, the model picker, or a thinking level that looks the model up).
