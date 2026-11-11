---
status: done
blocked-by: []
date: 2026-11-11
---

# 0219 — `!` and `!!`: run your own shell command from the input

The owner, note n56 (2026-11-09, task t248): "a `!` command that would passthrough the following arguments to the terminal and output
in ask the resulting output and returned value; a `!!` that would automatically send the result to the model verbatim as a code
block". Roadmap 0048 had left `!` undecided.

## The owner's answers (2026-11-11)

1. **Sandbox:** the session's, as the model's commands get.
2. **Asking:** never; the person typed it.
3. **Shell:** their login shell, `$SHELL`.
4. **`!` and the model:** the result goes with the person's next message.
5. **`!!`:** sent at once, starting a turn; during a turn it waits behind it, like a typed message.
6. **Long commands:** run at once, even during a turn; still running after a few seconds, a background job.

## The plan, as built

- `SlashInput`: `!command`, `!!command`; `\!` sends a message that starts with `!`. An empty command is said, and runs nothing.
- The screen sends it to the conversation beside any turn (`Effect.runShell`); the command's block shows it, open from the start.
- `BashTool.runForPerson`: the bash tool's own start and wait, under the session's sandbox (with the model's narrowing), the person's
  shell, no shellcheck refusal, and a job after 5 seconds.
- `ShellReport`: the command and its output in a code block whose fence nothing in them can close. `!` keeps it for the next message,
  as a finished thread's answer is kept; `!!` submits it (`ConversationUpdate.submitPrompt`).

## Done when

The tests and the probe below fail on the build before and pass. They do: `ShellLineTests`, `PersonCommandTests`, `ShellReportTests`,
and `Scripts/probe-shell-line.py` (5 checks through the release binary).

## Not done

- The `!` block is not kept in the session file, so a resumed session does not show it; its result is kept, in the message it went
  with.
- Not checked in a real terminal.
