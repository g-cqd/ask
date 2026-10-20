---
status: accepted
date: 2026-10-20
---

# 0052 — A usage limit is not retried, and says when it lifts

## Context

On the user's real ChatGPT account, every request ended in HTTP 429 "The usage limit has been reached". ask treated that as a rate
limit: it retried four times over about 15 seconds (1, 2, 4 and 8 s), then gave up with the server's sentence. A usage limit lifts at a
set time, hours away, so the retries only delayed the answer, and the sentence did not say when to come back.

## The probes

Ledger in `docs/diary/2026-10-20-45.md`.

- **What does the server actually send?** Captured live, with a minimal request refused before any generation: a JSON body with
  `type: usage_limit_reached`, `limit_window_minutes: 300`, `plan_type`, `resets_at` and **`resets_in_seconds`** (1181 at the time).
  It is now the fixture `Tests/Fixtures/Codex/usage-limit-429.json`.
- **Does the real binary stop retrying and say when?** Against a fake server returning that body: one request, immediately, and "it
  resets in about 20 minutes"; an ordinary `rate_limit_exceeded` control is still retried (5 requests). **CONFIRMED.** On the real
  account: 2 seconds instead of about 16, one request, "it resets in about 9 minutes", consistent with the 1181 s captured earlier.
- **Does each rule fail without its test?** 9 mutations, 9 killed.

## Decision

1. **A new failure kind, `usageLimit`**, which is never retried, whatever the status. A rate limit is unchanged.
2. **Two named error types mean it:** `usage_limit_reached` (ChatGPT's backend) and `insufficient_quota` (OpenAI's own). Both are matched
   before the generic "rate_limit" and "quota" fragments, because `insufficient_quota` contains "quota". Any other "quota" type stays a
   rate limit: other servers use the word for a per-minute limit, which was not probed.
3. **The server's own seconds are used, not a clock:** `resets_in_seconds`, accepted only as a whole number from 0 to 30 days, and only for
   a usage limit. Anything else (negative, huge, a string, a float, a list) is ignored, not trusted, and costs nothing else in the error.
   `resets_at` is not used: converting it needs a clock the decoder does not have, and the relative figure says the same.
4. **The sentence keeps the provider's words and adds the time**, to the nearest minute, hour or day: "The usage limit has been reached; it
   resets in about 20 minutes". The plan type is not shown; it is account detail the user did not ask for.
5. The same sentence is what the screen and `ask -p` print, because both go through the one description.

## Consequences

- ask does not wait for the limit to lift and retry by itself; the user decides.
- **Not covered:** Anthropic's own usage limits. Their error shape was not probed, so they are still classified as before.
- Rounding means "about 1 hour" covers 59.5 minutes to 90 minutes. That is deliberate and tested at each boundary.
