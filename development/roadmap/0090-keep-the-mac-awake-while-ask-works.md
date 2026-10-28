---
status: not-started
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
