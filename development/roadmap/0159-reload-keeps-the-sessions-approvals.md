---
status: not-started
blocked-by: []
date: 2026-10-30
---

# 0159 — `/reload` keeps the session's approval answers

Owner wish (2026-10-30 14:43): "/reload command does not necessarily reload ask with the same commands (regarding allowing tools)".

What a reload carries today: the flags (`--yes`, `--allow`, `--ask-always`, `--no-sandbox`, `--network`, `--write`, `--read`, model,
provider). What it loses: every "allow for the session" answer (the command grants of `CallGrants` and the sandbox allowances), which
live only in the process. An ask built before `--allow` existed also cannot pass `--allow` on. To do, red first: write the session's
grants where the new process reads them (the session file, as an entry the loop ignores, or a file handed over with the reload
arguments), and a probe that answers "for the session", reloads and runs the same command without a question.
