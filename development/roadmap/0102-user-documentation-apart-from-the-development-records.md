---
status: not-started
blocked-by: []
date: 2026-10-28
---

# 0102 — User documentation apart from the development records

Owner request (2026-10-28): prioritise the README and the documentation for people who use ask. Make it approachable, keep it accurate to how
ask actually behaves, and present things from the point of view of using it, without overdoing it. Configuration in particular must be
approachable. The README is lean; `docs/` holds the user documentation; the development records must not be mistaken for it.

## Plan

1. Move the development records out of `docs/`, to `development/`: ADRs, roadmap, diary, research, formal models, prototypes, the extension
   protocol draft, and the white paper. Update the layout tests, the scripts (`roadmap.sh`, `record_numbers.py`, `test-workflow.py`),
   `AGENTS.md`, `CONTRIBUTING.md` and the issue template. Links between records keep their relative form, since they move together.
2. `docs/` becomes the user guide: getting started, the screen and its keys, sessions, configuration, providers and accounts, the sandbox,
   skills and MCP servers. Each page is written against the code and the program's own output, not copied from the old README.
3. The README: what ask is, how to install and start it, three or four things worth knowing, and links into `docs/` and to `development/`.
4. Accuracy that holds: a test that every configuration key the code knows appears in `docs/configuration.md`, and that `docs/` does not
   link into `development/` for anything a user needs.

## Done when

The four steps are in, the gate is clean, and the README is short enough to read in a minute.
