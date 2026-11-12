# Background compaction and a compaction advisor: what the sessions say (roadmap 0032)

2026-11-12. The owner's proposal of 2026-10-19 (0032), measured on the 30 largest local sessions with
`Scripts/measure-compactions.py 30`. Sizes come from each response's recorded usage (input + cache read + cache creation); the
share of the window is by bytes of the session's entries, which counts thinking signatures, so it is an upper bound for thinking.

## What happens now

| | Measured |
|---|---|
| Compactions | 240 in the 30 sessions (70 in the largest alone) |
| Context at the last request before one | median 151,936 tokens (p10 149,523; p90 749,830, sessions with a larger threshold) |
| Context at the first request after | median 46,300 tokens (p10 40,469; p90 57,033) |
| Requests between two compactions | median 102 (p10 62; p90 501) |
| The summary written | median 12,432 characters, about 3,100 tokens (p10 8,808; p90 17,893 characters) |
| The window before one, by bytes | tool results 40 %, thinking 37 %, tool calls 21 %, text 2 % |

What a compaction costs the person is the wait: the run stops while a model reads about 150k tokens and writes about 3,100. The
sessions do not record its duration; the output alone is 40 to 80 s at 40 to 80 tokens a second. Over these 240 compactions that is
roughly 3 to 5 hours spent waiting. A summary kept ready removes that wait; the advisor would change when it happens.

## What each proposed piece can do

1. **Light edits, without a model.** Old tool results and thinking are three quarters of the window's bytes. Dropping the output of
   tool calls older than some turns (keeping the call and a one-line note), and earlier thinking, would push compactions further
   apart. Anthropic offers these as `context_management` edits (`clear_tool_uses_20250919`, `clear_thinking_20251015`); other
   providers would need ask to do it in the request it builds. Unmeasured: how many tokens the provider really counts for old
   thinking (bytes over-count it), and what dropping old output costs the answers.
2. **A summary kept up to date in the background.** A cheap model amends the summary after each turn, so compaction swaps it in at
   once. A hosted cheap model of the same provider sees nothing the provider does not already see. **Apple's on-device model cannot
   do it:** its context is 4,096 tokens a session (TN3193), and the median summary alone is about 3,100. A local model through MLX
   or llama.cpp could, at a memory cost ask's budgets do not allow in process; it would have to run out of process.
3. **The advisor.** Compacting at a natural break (a turn's end, no tool sequence half done) instead of at a fixed share needs the
   threshold to become a range: compact at the first break after the lower bound, and at the upper bound whatever happens.

## Decisions for the owner

1. Which first: the light edits (no new model, no new data path), the background summary (a second model, which reads the whole
   conversation), or both.
2. For the background summary: a cheap model of the same provider, a local one out of process, or a choice of both.
3. A replay to measure quality: N real compactions summarised one-shot (today) and incrementally by the cheap model, each graded by
   questions on early details. It costs real requests; the owner sets the budget.

## Not measured

The wait itself (no timestamps in sessions), the provider-side token count of old thinking, summary quality, and any local model.

## Replay (2026-11-12, the owner's budget of about 30)

`Scripts/replay-compactions.py --windows 30` (results in `replay-compactions-2026-11-12.json`): 30 compaction windows of the 30
largest sessions, Claude sessions only. `claude-haiku-5-5` amended a summary chunk by chunk (60 KB each, tool output clipped to
1,500 characters); `claude-sonnet-5-5` wrote five questions on specific facts from each window's first 40 % and graded whether each
summary held the answer. 29 windows graded (one grader reply was not JSON).

| | Early facts kept | Summary length (median) |
|---|---|---|
| ask's one-shot summary (today) | 35 % (median 20 %) | 12,549 characters |
| Incremental, `claude-haiku-5-5` | 24 % (median 20 %) | 4,525 characters |

- Incremental was worse in 14 windows, better in 4, equal in 11. On long windows (four chunks or more, 8 windows) the two were close:
  30 % against 28 %.
- Confound: the incremental summaries came out a third as long; the prompt set no length. The gap may be the prompt more than the
  method. A second run with a length target and "keep what still matters from the current summary" would settle it, with the
  questions kept so both runs are graded alike.
- Whatever the summariser, today's compaction keeps about a third of the early facts a later turn might need.
