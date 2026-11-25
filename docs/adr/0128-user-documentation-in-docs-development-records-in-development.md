---
status: accepted
date: 2026-10-28
---

# 0128 — User documentation in `docs/`, development records in `development/`

## Context

`docs/` held the ADRs, the roadmap, the diary, the research notes, the formal models, the prototypes and the white paper: well over a
thousand files written for the people building ask. A user looking for how to configure ask found those first, and the README carried the
whole user guide alone, with duplicated paragraphs and statements that had stopped being true (Esc never interrupting, a 24 MiB budget).
The owner asked for a lean README, consumer documentation in `docs/`, and development records that cannot be mistaken for it (roadmap 0102).

## Decision

1. The development records move, unchanged, to a top-level `development/`: `adr/`, `diary/`, `roadmap/`, `research/`, `formal/`,
   `protocol/`, `prototypes/` and `WHITE-PAPER.md`. Links between records are relative and still hold; every repository path to them (tests,
   scripts, skills, `AGENTS.md`, `CONTRIBUTING.md`, the issue template) now names `development/`.
2. `docs/` is the user guide only, written against the code and against what the program prints, easy cases first.
3. A test keeps the user guide true to the code: every configuration key ask reads appears in `docs/configuration.md`, and `docs/` does not
   send a user into `development/` for anything they need.

## Consequences

- `git log --follow` traces a record across the move; history before this ADR names `docs/` paths that are now `development/`.
- The documentation law in the white paper names `development/`; the record-numbering and roadmap scripts read it.
- Paths that look like `docs/` in tests of the file picker are synthetic fixtures and stay as they are.
