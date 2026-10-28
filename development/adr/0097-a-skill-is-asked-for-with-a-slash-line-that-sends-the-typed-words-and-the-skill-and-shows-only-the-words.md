---
status: accepted
date: 2026-10-25
---

# 0097 — A skill is asked for with a slash line that sends the typed words and the skill, and shows only the words

## Context

ADR-0095 let the model load a skill. Phase 3 of roadmap 0061 lets the person ask for one: `/skill:name request`, and skills in the `/` picker.

## Decision

- **`/skill:name [--from harnesses] request` is a prompt, not a command.** `SlashInput` already reads a first word with a colon as a prompt, so nothing about command
  parsing changed and a skill can never collide with a built-in command: its name always starts `skill:`. The conversation expands it before the loop runs
  (`SkillInvocation`); print mode (`ask -p "/skill:x …"`) does the same, and exits 64 with the reason when the skill cannot be loaded.
- **What the model gets is one user message:** the line as typed, a marker line (`--- skill NAME (SOURCE, SCOPE) ---`), the skill as the tool would return it,
  and `--- end of skill ---`. Nothing is added when the skill is missing; the person is told and no turn starts. A bare `/skill:name` carries a sentence saying
  to begin the work the skill describes.
- **The session records that message**, so a resumed session replays what the model saw and the cache prefix is the same bytes. `SessionPayload` is unchanged.
  **Every place that shows a prompt to a person cuts it at the marker** (`SkillInvocation.shown`): the replay on resume, `/tree`, and the session listing. A person
  therefore sees what they typed, and `/tree N` puts the typed line back in the editor, which expands again when sent. The transcript already showed the typed
  line, because it adds it before the conversation sees it.
- **The user may invoke what the model may not:** a skill with `disable-model-invocation` loads here, because the user asked by name. The same limits hold
  otherwise: the user's and bundled skills only (a project's wait for phase 4), no path (punctuation does not count in a name, so `../x` is the skill `x`),
  and `--from` only narrows.
- **The `/` picker lists skills after the commands**, as `/skill:name` with `skill · description`. They are asked for **once, when a command picker first
  could open (the first `/`), never at launch** (`Effect.listSkills`, `ConversationUpdate.skills`), off the input path, as the `@` listing is. The user's own and
  bundled skills are listed as the tool offers them, except bundled ones (they need `--from bundled`). Typing `skill` narrows to them. Because commands rank first,
  a person with many skills sees the commands before them until they type; that is a choice, not an accident, and revisited if it proves hard to find them.
- Steering and queued messages sent during a run are **not** expanded: a `/skill:` line typed while a turn runs is sent as text. Recorded as a gap.

## Consequences

Phase 3 is built without a model-visible change to the protocol or the session format. Costs: the line a person typed is the first part of a longer recorded message,
so a tool that reads the session file raw sees the whole skill in that message. Not done: `/skills` interactive listing, expansion for queued messages, `ask --skills-from`.
