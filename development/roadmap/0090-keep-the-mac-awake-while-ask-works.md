---
status: done
blocked-by: []
date: 2026-10-28
---

# 0090 — Keep the Mac awake while ask works

Owner wish (`ask-wishes.md`): a config option and feature that does what `caffeinate` does while ask runs. It can be disabled
completely; the config exposes only safe settings, never `caffeinate`'s arguments. Investigate system APIs first: they would be
better than a subprocess.

## Investigation first (not done)

- **IOKit power assertions**: `IOPMAssertionCreateWithName` with `kIOPMAssertionTypePreventUserIdleSystemSleep` (the system stays
  awake; the display may sleep) or `PreventUserIdleDisplaySleep`, released with `IOPMAssertionRelease`. In-process, no child to
  orphan, the reason string shows in `pmset -g assertions`. The assertion dies with the process, which `caffeinate` started by ask
  does not guarantee on a crash.
- **`ProcessInfo.beginActivity(options:reason:)`** (Foundation): `.idleSystemSleepDisabled`, `.idleDisplaySleepDisabled`,
  `.userInitiated`. Cheaper to adopt; it also helps App Nap, which does not matter for a terminal tool but is harmless.
- `caffeinate` itself only as a fallback if neither works; it would be `-i` or `-d` with `-w <pid>`, built by ask, never from config.
- Check: the lid-closed case (neither API prevents clamshell sleep without power and a display), the sandboxed `bash` tool (a
  profile that denies IOKit mach services would break an assertion made from a child, not from ask itself), and the cost against the
  budgets in ADR-0122 (linking IOKit adds to idle memory; measure it).

## Setting (proposed)

`power.keepAwake`: `off` | `system` | `display`. Default: `off` (to be confirmed: the owner has not said). Held only while a turn
or a tool is running, not while ask waits at an idle prompt; released at once on interrupt, error and exit.

## Done when

The investigation is a diary entry with the verdict, the setting exists with tests (assertion taken at turn start, released at turn
end and on interrupt, never taken when `off`), and `pmset -g assertions` shows it during a real turn (verified by hand).

## Result (2026-10-28)

**Verdict: `ProcessInfo.beginActivity`.** A probe program held each option set while `pmset -g assertions` was read:
`.idleSystemSleepDisabled` takes `PreventUserIdleSystemSleep`; adding `.idleDisplaySleepDisabled` takes `PreventUserIdleDisplaySleep` as well;
`endActivity` drops them at once; after `kill -9` the system drops them too, which a `caffeinate` child cannot promise. It is the same
assertion IOKit's `IOPMAssertionCreateWithName` makes, through Foundation, which ask already links: no extra framework, so nothing added
to cold start or idle memory. `caffeinate` is not used. The lid-closed case is unchanged: neither API prevents clamshell sleep.

**Setting:** a top-level `keepAwake`: `"off"`, `"system"` (default) or `"display"`, instead of the proposed `power.keepAwake`: one typed
key, like `maxTurns`, rather than a section with one key in it. Default `system`: the wish said the feature "can be disabled completely",
read as on unless turned off; the owner may still choose `off` as the default. Never `caffeinate`'s arguments.

**Behaviour:** `KeepAwake` (AskAgentCore) holds one activity from the start of a turn, a `/compact`, or a background job, to the end of the
last of them, in the screen and in print mode; a reload applies a new mode at once, even mid-turn; `off` never holds anything.

**Evidence:** `KeepAwakeTests` (bracketing, overlap, jobs after the turn, off, mode changes, unmatched ends, the real activity, the config
key). `Scripts/probe-keep-awake.py` runs the release binary in a PTY against a scripted provider and reads the real assertions from `pmset`
under ask's own pid: none at the idle prompt; `PreventUserIdleSystemSleep` while a `sleep 3` tool runs; gone when the turn ends; both
assertions in display mode; held past the turn by a background job and let go when it ends; never with `off`. All 7 checks pass. This
replaces the "verified by hand" step: the assertion was read from the system during real turns, in a PTY rather than a terminal window.

