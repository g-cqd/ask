---
status: not-started
blocked-by: []
date: 2026-11-08
---

# 0211 — The PTY sweep runs in the repository and in CI, nightly

From the rationalisation pass (research/rationalisation-2026-11.md §2.4; note n53, task t241).

## Today

There are 92 PTY probes (`Scripts/probe-*.py`). They found two defects in ask this week that the unit tests missed. But nothing runs them
except a script in a temporary directory on one machine. No workflow runs them, and a probe that rots is found only when someone
runs it.

The mutation gate had a related problem: it failed from 3 to 8 November and nobody saw it.

## The plan

1. **`Scripts/sweep.sh`** in the repository. It builds the release binary once and runs every probe with a timeout. It writes one
   line per probe (`exit`, failures, seconds) and exits non-zero on any failure. Probes that need a terminal feature pyte lacks
   say so and are marked skipped, not failed.
2. **The pinned emulator.** Today the probes import pyte from `ASK_PYTE`, a directory outside the repository. Instead it is
   installed from a pinned, hashed archive, the same way `mutate-changed.sh` pins its tool, and the probes read it from the
   build directory.
3. **A `probes.yml` workflow**, nightly and on demand. It uploads the summary, and its job summary lists any failing probe with that
   probe's last screen.
4. **Failures are seen.** A failed scheduled run of `probes.yml` or `mutation.yml` opens or updates one issue per workflow, which
   the next green run closes.
5. **The rule.** A new interactive behaviour comes with a probe that fails on the build before it. This already happens; it becomes
   a line in the white paper's Red TDD section.

## Done when

`Scripts/sweep.sh` passes locally and in CI. The nightly run is green. A probe broken on purpose fails the workflow and opens the
issue, and the next green run closes it.

## Not in scope

Real-terminal tests (kitty, Ghostty), which stay manual and are listed as unverified where they apply. Speeding up individual probes.
