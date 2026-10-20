---
status: accepted
date: 2026-10-20
---

# 0053 — The action budget is a tool call to its result on screen: 5 ms

## Context

ADR-0004's fourth budget measured Enter redrawing a prompt in a program with no agent: 0.05 ms against 2 ms. Roadmap 0007
required re-deriving it against a real action once the loop existed, and removing the old figure.

## Decision

- **The action** is ask's own work between the model asking and the user seeing: from the last byte of a response that
  calls a tool to the end of the frame showing that tool finished, for a tool that runs in process (`read` of a small
  file). It covers parsing the stream, recording the response, running the tool, recording the result, and drawing.
- **The budget is 5 ms**, checked on the median like every budget, about twice what the shipping binary measures.
- **Reported beside it, not budgeted:** the next request leaving (the time to the model's next turn) and a sandboxed
  `bash` command, which adds a process spawn and the sandbox (ADR-0035) the user also waits through.
- `Scripts/measure-action.py` measures it against a fake model server on the same monotonic clock, with isolated
  configuration and no credentials; `Scripts/measure-budgets.py` uses it for the fourth budget.

## Measurements (release, 10 runs each, p50 [p25–p75])

| | Fresh session | After 500 turns |
|---|---|---|
| `read`: result on screen | 2.53 [2.45–2.73] ms | 2.62 [2.41–2.78] ms |
| `read`: next request sent | 3.99 [3.66–4.04] ms | 4.49 [4.21–4.75] ms |
| `bash echo`: result on screen | 15.83 [15.55–16.24] ms | 16.07 [15.44–18.38] ms |
| `bash echo`: next request sent | 17.90 [17.70–18.46] ms | 18.77 [17.86–20.83] ms |

The result on screen does not grow with history; the next request grows by about 0.5 ms over 500 turns (encoding a
longer request). Counterfactual: a 20 ms sleep in `read` made the harness report 28.4 ms and "OVER BUDGET".

## Consequences

The old 0.05 ms figure and its caveat are gone from `Budget`, the harness, AGENTS.md and the README. Roadmaps 0007 and
0009 close. The `bash` path is where a user waits: about 9 ms of it is `sandbox-exec`'s start (ADR-0035) and is the place
to look first if a command-heavy session feels slow. The 0.5 ms growth of the next request is the encoding the loop
notes (roadmap 0007's history) predicted; at 500 turns it is still far inside any perceptible delay.
