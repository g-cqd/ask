---
status: done
blocked-by: []
date: 2026-11-01
---

# 0185 — Skills picked in the middle of a message, and drawn as such

Owner (2026-11-01): some `/commands` should be pickable in the middle of what is being written, and highlighted. Which: skills, and
commands that bear on the message and the work after it; not the meta ones (`/model`, thinking levels), which stay first-word only.

Today a `/command` is one only as the input's first word (0048); `@` already opens its picker anywhere a word starts.

## Decided (owner, 2026-11-01)

- **Which**: skills, and any later command that changes what the message asks for. Meta settings stay at the start.
- **Look**: a coloured token, the `/skill` (and its argument) in an accent colour, like a link; the rest of the text unchanged.
- **Sent**: text and effect. The `/skill` stays in the text the model reads, and the skill's content is attached as it is for a
  message that starts with it.
- **Later**: `@` also points at ideas and tasks (0179, 0180), and `#` at pull requests, issues or tasks (0186).

## Done (2026-11-01)

- Sending: `SkillInvocation.expand` attaches every `/skill:name` that starts a word, after the line as typed, each skill once, in the
  order named; a line that starts with one keeps its rules (`--from`, an unknown name refused), an unknown name later stays text, and
  a `/` inside a word (a path, an address, `(/skill:x)`) names nothing. `shown` still cuts at the first skill, so every view shows the
  line typed. Print runs and the screen share it.
- The picker: a `/` that starts a later word lists the skills alone (commands stay first-word only); it comes after a command's own
  list, so `/resume /tmp/…` keeps the sessions. Choosing one replaces the word.
- The token: a known `/skill:name` is drawn in the link look in the draft (with Markdown colouring on or off) and in the sent message,
  on its bold look; an unknown name stays plain. The transcript holds the skills' names, set when the list arrives.
- Tests: `SkillInlineTests`, `InlineSkillPickerTests`, `SkillTokenTests`; 6 mutants, all killed; two guards they showed redundant were
  removed (punctuation after a name, which the lookup ignores; the first-word check, which the command picker already takes).
- Not done: the probe through the real binary, and a skill in a queued message, which is still not expanded (0061, task t30).
