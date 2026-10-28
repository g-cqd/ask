---
status: accepted
date: 2026-10-22
---

# 0057 — The model can narrow the current conversation; only the user can undo it

## Context

ADR-0054 delivered per-call narrowing and ADR-0055 the human approval prompt. Roadmap 0019 also asks for
“sandbox everything from now on”. A policy on one loop instance is not enough: configuration and `/model`
can replace that loop between prompts. Existing child processes cannot adopt another Seatbelt profile.

## Decision

1. **`narrow_sandbox`** accepts the same `sandbox` object as a command or file call. The registry first applies
   it to the current effective policy, asking the user if it requests more. The tool remembers the resulting
   policy, intersected with the run's own ceiling. A later change to one dimension keeps the others.
2. **Every later dispatch** intersects the run's policy with the shared `SessionNarrowing` before applying a
   per-call request. The original run ceiling survives those context copies. Neither an approved individual
   call nor a configuration reload can accidentally turn the stored narrowing into unrestricted authority.
   An explicit per-call approval still works as in ADR-0055.
3. **Reset always asks.** `{"reset":true}` restores the run's own policy only after approval; under `-p` it
   is refused. Reset is an operation, not an empty capability request: unrelated remembered grants cannot cover
   it, and answering `a` does not create a reusable grant to reset future narrowings.
4. **Stop jobs first.** A narrowing is refused while any job runs, with an explanation. Otherwise `job_input`
   could keep commanding a process launched under the old, wider profile. Finished jobs do not prevent it.
5. **Lifetime is explicit.** The narrowing belongs to the current in-memory conversation, not one loop. It
   survives configuration and `/model` changes, but a successful `/new` or `/resume` clears it. It is not
   written as session metadata; quitting, restarting or `/reload` starts without this additional layer. Saved
   user-configured strict policy is separate and still resumes according to ADR-0045. A failed switch keeps
   the current conversation and its narrowing.
6. **The model is told each time.** After the stable system-prefix blocks, every request appends the current
   effective session policy. Compaction cannot erase that information, and reset removes the extra block.
   The tool result reports the effective dimensions actually stored, including a tighter run ceiling.

## Probes

`NarrowSandboxToolTests` exercises dispatch, cumulative dimensions, approvals and refusal, reset, the run ceiling
and live jobs. `SessionNarrowingTests` checks the current prompt without changing the stable prefix. Executable
probe X exercises a headless narrowing and refused reset; PTY Y exercises reset, loop replacement and `/new`;
PTY Z separates an unrelated remembered write grant from permission to undo a network narrowing.

## Consequences

This adds one tool schema, a shared mutex-backed optional policy, and an additional policy/prompt intersection
when narrowed. `Scripts/measure-action.py ... RUNS HISTORY narrow` measures an action after a preceding session
narrowing, rather than timing the narrowing command itself; `warm` supplies a matched second-action control.
Twelve interleaved pairs on the final integrated base measured read-to-screen at 1.64 ms warm versus 2.56 ms
narrowed (about 0.92 ms added), inside the 5 ms median budget. Default shipping budgets, tails and the eleven caught mutations are in diary 56.

This is not a persistent restriction on an archived conversation or an already-running process. File-tool
canonicalization races and ask's own unsandboxed authentication/persistence remain as previously documented.
