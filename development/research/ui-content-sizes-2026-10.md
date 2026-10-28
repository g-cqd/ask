# Research note — how big are the things ask's screen would fold or bound, October 2026

Measured on 2026-10-20 from local agent session logs, to set thresholds for roadmap 0051 and ADR-0045 from data. The probe is
`probe-ui-content-sizes.py` and it keeps **counts only**: no message text is stored or printed.

## Method, and what it cannot tell you

- **Sources:** Claude Code (the 400 largest of 958 session files), Codex (all 204) and Pi (all 40), all of this machine's. That is
  8,248, 6,881 and 24,994 messages. The owner's own use, one person's, on one machine.
- **Code blocks:** fenced blocks in assistant messages, counted in lines. 725 blocks.
- **Prompts:** user messages that do not begin with `<` (to drop injected tags), in hard lines and in display rows at 100 columns.
  3,152 prompts. **This count is contaminated**: the logs include pasted context and prompts written by programs, which are long,
  and nothing here separates them from a person typing. Pi's logs are the cleanest.
- **Images:** messages that carry an image block.
- Not measured: tool output, thinking, or anything from ask's own sessions (too few).

## Code blocks (lines per block)

| Source | n | median | p90 | p95 | share at or under 10 / 15 / 20 / 30 lines |
|---|---|---|---|---|---|
| Claude Code | 460 | 4 | 13 | 18 | 85% / 93% / 95% / 97% |
| Codex | 112 | 16 | 37 | 46 | 39% / 46% / 66% / 85% |
| Pi | 153 | 3 | 13 | 15 | 86% / 95% / 97% / 98% |
| **All** | **725** | **4** | **19** | **26** | **78% / 86% / 91% / 96%** |

A threshold of 20 lines leaves 91% of blocks unfolded and folds the longest 9%; 15 would fold 14%. Codex writes much longer blocks
than the other two (median 16), which is why a single threshold fits some sources better than others.

## Prompts (display rows at 100 columns)

| Source | n | median | p90 | p95 | share that fit in 3 / 6 / 10 rows |
|---|---|---|---|---|---|
| Claude Code | 1,478 | 49 | 164 | 224 | 12% / 17% / 20% |
| Codex | 989 | 2 | 153 | 323 | 61% / 70% / 74% |
| Pi | 685 | 1 | 4 | 7 | 88% / 94% / 96% |

The distribution is **heavy-tailed**: most prompts are one row or two, and a minority are very long. Pi's 94% fit in six rows;
Claude Code's logs are mostly long because of what they contain, not necessarily what a person types. What it supports is that an
input must scroll inside itself, not that six is the right number.

## Images

| Source | messages with an image |
|---|---|
| Claude Code | 5 of 8,248 (0.06%) |
| Codex | 4 of 6,881 (0.06%) |
| Pi | 145 of 24,994 (0.58%) |

## What this suggests, and what it does not

- Code folding at about 20 lines catches the long blocks and leaves the common ones. The data does not say where a reader's
  patience ends; it says where blocks end.
- Images are rare enough that they are the last thing to build, and folding them by default costs almost nothing.
- Nothing here measures how *tall* a block must be to hide what someone is reading. That depends on the screen, which is why the
  proposed threshold is also capped at half the viewport.
