---
status: done
blocked-by: []
date: 2026-11-10
---

# 0218 — Reload restores the session workspace

The owner, note n64 (2026-11-10): reload sometimes loses pwd. An empty tool working directory was observed after reload and a
volume interruption. The isolated reproduction uses a removed/recreated directory; a real remount has not been reproduced.

## The plan

1. Reproduce a stale inherited working directory using the actual Reexec helper in an isolated process.
2. Re-enter the captured absolute session workspace before exec, carry it as PWD, and fail if it is unavailable.
3. Test ordinary, stale/recreated and unavailable workspaces, spaces in paths and saved launch environment.

## Done when

The isolated regression fails before the fix and passes after it; the quality/release gate passes. A missing workspace does
not silently become another project. Mutation testing remains CI-only. Real-volume/reload checks are separately unverified.

## Verification

`Scripts/check-reload-workspace.py` passes five isolated cases and runs in the CI script guard. The self-check workspace test
failed first, then passed with the explicit Subprocess directory. Full release/quality verification passed (3,776 tests).
A real-volume remount and live terminal reload remain separately unverified; shipping rebuild follows landing.

## Review (2026-11-11)

- The fix above covers a running ask. A launch from a shell whose directory was replaced had no working directory at all and ran
  on; that is what the reloaded session of 2026-11-10 met. ask now goes back to the shell's `PWD` when it is there, saying so, and
  stops when it is not (`LaunchDirectory`, `enterLaunchDirectory`).
- A reload whose session directory is gone said the new build failed its self-check. It names the directory now.
