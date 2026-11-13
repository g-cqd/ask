---
status: done
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

## Done (2026-11-13)

`Scripts/sweep.sh` (with `Scripts/sweep_one.py`: a time limit that kills the probe's process group) runs every probe against one
release build, 4 at a time by default, then each failure again alone: passing alone, it is `FLAKY`, said, not failed.
`Scripts/sweep-skip.txt` names the probes it cannot run, with why. pyte and wcwidth are pinned by version and PyPI's hashes
(`--require-hashes`). `probes.yml` runs it nightly; `ci-failure-issue.sh` opens an issue for a failed scheduled run of `probes.yml` or
`mutation.yml` (cancelled counts), and the next green run closes it. First local sweep: 106 passed, 2 flaky, 1 skipped; it found a
real defect (a session switched away from stayed locked while its name was asked for).

Not verified: the workflow on GitHub (the next night), and an issue opened and closed by a real run.
