---
status: not-started
blocked-by: []
date: 2026-10-30
---

# 0165 — A refusal from the subscription gate says what changed

From 0010 by way of 0144: ask explains the one refusal it has met (the "out of extra usage" 400, 0144), but any other rejection from the
Claude subscription gate (ADR-0007) still shows the provider's raw message. To do: recognise the gate's refusals as a kind of their own
(status, error type and the `anthropic-ratelimit-unified-*` headers), and say in words what was refused and what to try (another
connection, an API key), red first against recorded responses. Small; no live request needed.
