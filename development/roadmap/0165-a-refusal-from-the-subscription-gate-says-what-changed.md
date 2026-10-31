---
status: done
blocked-by: []
date: 2026-10-30
---

# 0165 — A refusal from the subscription gate says what changed

From 0010 by way of 0144: ask explains the one refusal it has met (the "out of extra usage" 400, 0144), but any other rejection from the
Claude subscription gate (ADR-0007) still shows the provider's raw message. To do: recognise the gate's refusals as a kind of their own
(status, error type and the `anthropic-ratelimit-unified-*` headers), and say in words what was refused and what to try (another
connection, an API key), red first against recorded responses. Small; no live request needed.

## Done (2026-10-30)

What the recordings hold (`~/.local/share/ask-lab/20261029-144251/`): 97 status-400 and 35 status-403 responses. Every 403 and 80 of
the 400s are the lab proxy's own blocks; the 17 from Anthropic are all the "out of extra usage" 400 (0144). No 429 from the gate was
recorded, so its words rest on ADR-0007's bisection and are kept retryable:

- **A 429 while the subscription's headers say every quota allows requests** (`unified-status`, and the 5h and 7d windows when present,
  all `allowed`) stays `.rateLimited` and is retried, since a genuine burst limit reads the same; its words say the gate may be refusing
  the request's shape, name another connection or an API key, and keep Anthropic's words. A window near its limit (`allowed_warning`),
  or no subscription headers (an API key), keeps the provider's words.
- **"This credential is only authorized for use with Claude Code"** (400), reported publicly and not met here: said as a refusal of the
  request's shape, not retried.
- **The request id** (`request-id`, checked to look like one) is in all three, the out-of-extra-usage one included.

Tests: `AnthropicGateRefusalTests` (red first). Not verified against a live gate refusal.

