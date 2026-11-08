---
status: not-started
blocked-by: []
date: 2026-11-08
---

# 0212 — Roadmap hygiene: one template, a triage, and a generated index

From the rationalisation pass (research/rationalisation-2026-11.md §3; note n53, task t241).

## Today

- 208 entries: 133 done, 45 in progress, 30 not started.
- 20 in-progress entries have no section saying what is still owed.
- About thirteen entries track other repositories' code.
- Section headings vary entry to entry (`Done when`, `Still owed`, `The plan`, `Plan`, `The work`, `What is built`, `What lands`).
- Features have landed with no entry, such as `ui.dim`.
- The diary stopped on 4 November, while 22 commits touched `Sources` after it.

## The plan

1. **A template**, in the white paper's §4 and enforced by `RoadmapGranularityTests`. Every entry has:
   - the front matter;
   - the heading;
   - a first paragraph saying where it came from (the owner's words, or the note, task or finding);
   - `## The plan`;
   - `## Done when`.

   An in-progress entry also has `## Still owed`. Other sections stay free. Existing entries are brought to the template when they
   are next touched, and the test checks only entries dated from 2026-11-09.
2. **A triage of the 45 in-progress entries**, each with one of three outcomes:
   - done, with what is left moved to a new entry;
   - still in progress, with a `Still owed` section;
   - not started again, because nothing landed.
3. **Other repositories' entries** become pointers in ask's roadmap, once the owner agrees (research note §5.2). Their tracking
   moves to the repository that holds their code.
4. **A generated index:** `development/roadmap/README.md`, listing number, title, status and date, grouped by status. A test fails
   when it is stale, the way `docs/config.example.jsonc` is regenerated.
5. **No feature without an entry.** A user-visible change, meaning a new setting, command or tool, cites an entry or an ADR in its
   commit message. This is a white paper rule, not a hook.
6. **The diary**, as the owner decides (research note §5.3): either it resumes, or §4 says commit messages and `Still owed`
   sections replace it.

## Done when

The template test passes. Every in-progress entry says what it still owes. The index is generated and guarded. The owner has
answered §5.2 and §5.3, and the white paper says so.

## Not in scope

Rewriting done entries; renumbering.
