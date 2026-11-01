---
status: not-started
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

## Still owed

- The picker opening at a `/` that starts a word anywhere in the draft, offering skills only (and the commands this entry admits).
- The draft's colouring of a recognised inline `/skill` (0151's draft colouring), and the same in the person's sent message.
- Expansion: each inline skill attached once, in order, whether it starts the message or not; an unknown name stays text.
- Tests: the picker's word rule mid-text, a path or address with a `/` inside a word never opening it, the sent text and attachment.
