---
status: not-started
blocked-by: ["the owner's approval for the one large request, only for step 5"]
date: 2026-10-25
---

# 0069 — Antigravity: probe where ask only guesses

`docs/research/antigravity-2026-10.md` registers what is known about Cloud Code and 22 things that are not. Five of them decide whether the connector
behaves well when something goes wrong, and each has a probe that can fail. The first four cost almost nothing; the fifth needs the owner.

## The work, cheapest first

1. **`MAX_TOKENS` (U6).** A request with `maxOutputTokens` of 8: does the stream end with `finishReason: MAX_TOKENS`, and does the loop show a cut answer
   rather than a finished one? Today `MAX_TOKENS` is mapped from Google's documented list and only `STOP` was observed.
2. **A longer tool loop and three parallel calls (U8).** Is the signature only on the first of three? Does a ten-turn Gemini 3 loop need the sentinel on earlier turns,
   or does it accept their omission (Google documents validation for the current turn only)?
3. **The thinking fields (U11).** `thinkingBudget`, `thinkingLevel` and `supportsAdaptiveThinking` are in the model list. Send each in `generationConfig.thinkingConfig`
   on `gemini-3-flash` and read what the usage and the thoughts do. If one works, ADR-0060's levels can extend to Antigravity; if none does, the refusal stays.
4. **The quota fields (U3).** Read `quotaInfo` before and after a measured amount of use on one model, and see which entries move. If the pools are what they look like,
   `ask models agy` can show what is left and when it lifts, and a usage limit can be told apart from a rate limit.
5. **A request longer than the window (U1)**, on `gpt-oss-120b` (about 140,000 tokens), **after the owner says yes**: record the status and the body. Then make the
   recognizer (`ProviderFailure.Kind.describesContextOverflow`) accept the observed wording **with the recorded body as its test**, and show the loop compacting and
   retrying on it. Do not widen the recognizer to a guessed wording first.

## Done when

Each of U1, U3, U6, U8 and U11 has a verdict in a diary with its probe, moves from the "not known" table of the register to the "known" one, and any code it changed has
the recorded body or stream as its fixture and a fault that fails without the change.

## Not claimed

That the refusal wording is the same for Claude and Gemini on Cloud Code: the first probe gives one family's. The others stay open.
