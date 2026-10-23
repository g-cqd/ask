---
status: accepted
date: 2026-10-23
---

# 0063 — An alias may carry a thinking level, and the file version says so

## Context

Roadmap 0047 owed "a reasoning level per alias". An alias (ADR-0049) already means a model plus the limits the user stated; the
thinking setting (ADR-0060) is chosen by configuration, environment and flag. A user who keeps `deep` for hard problems wants
`work/deep` to mean the model and how hard it thinks. Two risks were named before writing code: an older build reading a file it
does not understand, and an option name the parser might route to the wrong command.

## The probes

- **Does an older build lose a level it does not know?** By construction, yes: `aliases.json` is replaced whole on every change, and
  a version-1 reader that decodes without the field writes it back without it. So the format must change when a level is present.
- **Does the new option reach the alias command?** First attempt, `--thinking`: **REFUTED**. The probe printed `work/think is
  gpt-6-sol.` with no level and the file held none: the root `ask` command owns `--thinking` and ArgumentParser gave it to the root,
  silently. The option is `--thinking-level`; the probe now checks the level is stored. (A manual test also created a real alias
  `x` on the real `work` connection before this was understood; it was removed at once and the real file checked byte for byte.)
- **Does each rule fail without its test?** 14 deliberate faults (11 in the library, 3 in the command wiring), each killed against
  a baseline proven green first; one first attempt did not compile and was redone (diary 2026-10-23-12).

## Decision

1. **A level belongs to the alias**, stored beside its stated limits, never to a model typed directly. A catalog refresh does not
   touch it. Allowed values are the thinking levels, including `default` and `off`.
2. **Rank.** The built-in default < `config.json` (including an explicit `default`) < the alias level < `ASK_THINKING` < `--thinking`
   (< a `/model` choice for the model itself). The alias is the more specific choice, so it replaces the files; the environment and
   the flag are this run's own say. `ask config` and the reload report name the source as `alias connection/alias`.
3. **The file version is derived.** It is written as 2 only while some alias has a level, and as 1 otherwise. An older build keeps
   reading a file with no level, and refuses one with a level (`newerFormat`) instead of damaging it. This build reads both, and a
   version 3 is still refused. Equality ignores the version, so deriving it never counts as a change.
4. **A hand-edited unknown level makes the file damaged**, reported and never overwritten, like any other malformed field.
5. **`--thinking-level`** on `ask connections alias`, validated before anything is written.

## Consequences

- Removing the last level returns the file to a format older builds read.
- An alias level is applied at load, before the thinking control is chosen, so the model's own capabilities still decide whether
  it is allowed (ADR-0060): an alias can name a level the model refuses, and the run then says so.
- Not covered: aliases for the default `codex` and `anthropic` connections (they have none), a picker, and a unit test for the
  load-time application, which lives in the executable target and is covered by the connection probe (36 checks).
