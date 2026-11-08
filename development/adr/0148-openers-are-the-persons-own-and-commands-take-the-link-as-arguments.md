---
status: accepted
date: 2026-11-08
---

# 0148 — Openers are the person's own, and a command takes the link as arguments, never through a shell

## Context

The owner (notes n32 and n33, task t215) wants a clicked link to open in an app chosen per kind of link (file, folder,
web) or per rule matching the link, or to run a command the person wrote. Such a command runs outside the sandbox and cannot be checked.
The owner also asked for safeguards against prompt injection, because the link a person clicks is often text the model wrote.

Today `LinkOpener` follows only web, mail and file links, through `NSWorkspace`, and shows a file that would run in the Finder instead
of opening it (roadmap 0075).

## Decision

The owner chose these on 2026-11-08:

1. **Only the person's own configuration defines openers.** That is the user configuration file (`~/.config/ask`). A project's file
   cannot add, change or remove an opener, trusted or not. An `openers` section in a project file is refused with a notice naming the
   file, and ask goes on without it. Nothing the model writes, or a tool returns, reaches the opener table.
2. **A command is a list of arguments, run without a shell.** Placeholders (`{path}`, `{line}`, `{column}`, `{url}`) are replaced
   inside the one argument they stand in, and are never parsed again. A link whose substituted value starts with `-` is refused, so
   it cannot become an option. The link's text is never an argument, only its target, decoded from the URI.
3. **A command asks before it runs**, showing the exact argument list and the rule that matched. The choices are *allow once*,
   *allow always* and *deny*.
   - *Allow always* lasts until the person revokes it. It is kept in ask's state (`~/.local/state/ask/openers.json`), keyed by a
     hash of the command's arguments as written and the rule's match, so editing either asks again. `/config openers` lists and
     revokes these grants.
4. **Under `--yolo` or approvals `allow-all`, a command runs without asking**, as the owner's note said.
5. **A link opens only on the person's click**, as today. Hovering, rendering or the model's own tools never open one.

An app opener uses `NSWorkspace` with that app, and asks nothing. It is the person's choice of app for the person's click. A link
that no rule matches keeps today's behaviour, including revealing a file that would run instead of opening it.

## Consequences

- A cloned repository cannot turn a link into a command. The risk left is the person's own commands, run on targets the model may
  have written. Refusing leading dashes, using no shell, and the confirmation in normal modes bound it.
- `--yolo` users accept command openers running on any clicked link that matches.
- The process inventory (`SubprocessInventoryTests`) gains one entry: the opener's launch.
