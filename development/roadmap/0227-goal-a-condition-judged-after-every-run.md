---
status: in-progress
blocked-by: []
date: 2026-11-13
---

# 0227 — `/goal`: a condition judged after every run, and the run goes on until it holds

The owner (note n34, t216; research `development/research/goal-and-loop-2026-11.md`, answers of 2026-11-12): a goal is checked when a
run ends, by a small model of the session's provider; at a bound the person is asked when present, else the goal stops. `/loop` is a
later step.

## Design

- **The state** (`GoalState`, one per conversation): the condition, when it was set, the turns judged, the last reason, the bounds
  (`maxTurns` 10, `maxDuration` 1 hour), and how it ended (met, impossible, stopped at a bound, cleared).
- **The hook** (`GoalHook`, at `run.stop`, ADR-0143): with a goal active, it asks the judge and answers `continue` with what is
  missing, or `stop` when the goal is met or impossible. A goal has its own bound, so it is asked even when `hooks.maxContinues` stops
  the other hooks; `maxTurns` (the run's request limit) still holds.
- **The judge**: one request to the provider's cheap model (`ModelResolution.cheapModel`; the session's model when it has none), given
  the condition and the run's recent entries (text, calls, results clipped), answering `MET`, `NOT YET: …` or `IMPOSSIBLE: …`. It
  runs nothing; it reads what the run showed. An unclear answer counts as not yet.
- **At a bound**: the person is asked whether to go on for another `maxTurns` (or hour); no answer within two minutes, or `ask -p`,
  stops the goal.
- **The person's side**: `/goal CONDITION` sets it (replacing one) and sends it as the next message, so a run starts; `/goal` shows
  it (condition, time, turns, last reason); `/goal clear` drops it. Each verdict is shown as the hook's message; met, impossible and a
  bound as notices. A goal never widens approvals.

## Not in this step

`/loop`, a status-bar segment for the goal, settings for the bounds (constants for now), goals restored on resume.
