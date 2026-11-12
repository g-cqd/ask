---
status: done
blocked-by: []
date: 2026-11-12
---

# 0225 — The Antigravity connection names the newest `agy`, read from its update service

Owner (2026-11-12), after the Copilot version check (0193): fetch the information the Antigravity connector sends and update it
regularly, on use.

## What was found

- Cloud Code grows the model list with the `antigravity/cli/<version>` prefix of the `User-Agent`, and no longer ignores it
  (`fetchAvailableModels`, one account, 2026-11-12): 0.0.1 and 1.0.0 give 20 entries, 1.2.0 gives 23, 1.3.0, 1.3.9, 1.4.0, 1.4.7,
  1.5.6 and 9.9.9 give 27 (the same ids), no prefix or a non-version gives 20. A version frozen at build time (`1.4.0`) would lose
  models whenever the floor moves.
- The installed `agy` is 1.5.6. Its binary names `https://antigravity-cli-auto-updater-974169037036.us-central1.run.app`; a plain GET of
  its root answers 200 `text/html` in about 230 ms: `Antigravity CLI auto updater is running! Stable Version: 1.5.6. Rolled out to 100%`.
  Every other path tried (`/latest`, `/version`, `/update`) is 404. It is a status page, not a documented interface.

## What was built

`AgyVersions`, as `CopilotVersions` is: the stable version read from that page at most once an hour, kept in `agy-cli-version.json`
beside the credentials; a failed check keeps the last version read, or `AgyVersions.known` (1.5.6), and is retried after five minutes.
Unlike Copilot's, a check holds a request for two seconds at most. Only a plain version (two to four numbers of up to six digits) is
used or read back from the file. It names the version in the `User-Agent` of onboarding, the model list and streaming, and in the
envelope's `userAgent`.

## Not known

- Whether the service's wording stays; a change makes the check fail closed, to the last version read.
- A cold start of the service (Cloud Run) was not seen; the two-second bound is what covers it.
- Whether a version that is not the newest, or one `agy` never shipped, can be restricted later (U22 is still the owner's).
