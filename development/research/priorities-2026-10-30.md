# Roadmap and wishes reassessed (2026-10-30)

Supersedes the order in `priorities-2026-10-29.md`. The roadmap holds 157 entries: 78 done, 39 in progress, 40 not started. The wishes
file (107 lines, last added 2026-10-29 17:55) has no new wish; every wish has an entry (the 16:11 "context filling" bug is 0147, done).

## Landed since the last review

Keychain storage (0110, signing step owed to the owner), `ui.timeout` (0126), interruption as a colour (0142), MCP in one block and on
first need (0145, 0143), `keepAwake: "always"` (0148, first half), links that are each their own and open on a click (0075), reconnecting
and waiting for the network (0141), prompt history (0111), approvals as a checkbox section that shows the whole command and leaves no
block (0116, 0157), calls that change things ask first with `--yes`, `--allow`, `--ask-always` and `approvals` (0134, 0156), the security
audit's High findings and the MCP annotation finding (0153), and the workspace as the default write scope (0153).

## What the state of the roadmap says

1. **Many settings arrived quickly**, each named where it was built: `approvals.*`, `credentials`, `ui.timeout`, `ui.timeoutLabel`,
   `sandbox.allowWrite`, `--yes`, `--allow`, `--ask-always`, beside older `ui.escapeInterruptRequiresConfirmation` or
   `ui.jobAutoReturnWhenFocused`. Every week without 0154 adds names to rename later, with compatibility for each.
2. **Three entries are one body of work:** consistent names (0154), strong simple types (0118) and a configuration example generated
   from the code (0096) all need one description of every setting: its key, type, default, choices, layer rules and words. Built once,
   it also feeds `ask config`, the configuration page and the parser's error messages, which are written by hand today.
3. **A lot is unseen in a real terminal.** Today's checkboxes, folded commands, orange interruptions, link ids, the offline and MCP
   marks were verified through pyte only. The showcase from the last review (item 5) was never built.
4. **The in-progress list is long and partly stale.** 20 in-progress entries have no "still owed" section; several (0016, 0025, 0053,
   0062, 0064, 0074) were judged finished at the last review and never closed.

## Next, in order

1. **0154 with 0118 and 0096: the settings schema.** First step, cheap and owner-facing: the table of every setting, flag and command as
   it is and as proposed, with the reason, for the owner to accept row by row. Then one `SettingDescriptor` list in code that the parser,
   `ask config`, the docs page and a generated `config.example.json5` all come from; renames read the old names with a notice.
2. **A showcase for a real terminal** (`Scripts/showcase.py`): every block kind, the approval section, the status marks, links, on a light
   and a dark page. One run by the owner closes the "not seen in a real terminal" lines of 0049, 0051, 0065, 0075, 0108, 0116, 0141, 0142,
   0157.
3. **Close-out pass:** each in-progress entry checked against the code, set done or given a "still owed" list.
4. **0117, the model's questions**, on the approval section: the schema, single and multiple choice, the note, tabs for a series.
5. **0113, commands at the next turn**: `/model` and the like take effect at the next request.
6. **0088 step 3, payloads on disk** (active memory 21.5 MiB against 20), approved if opening, Page Up and unfolding show no lag.
7. **0153's rest:** finding 5 (`ask -p` and control sequences), the hardening notes, the default network; then a `standard` audit run.

Owner steps: sign a build for the Keychain (0110); the shutdown and update investigation for `keepAwake` (0148) needs a restart test.

## Later or parked

As before: 0155 (setup allowances, the owner's "later"), pixel UI (0014, 0015), isolation (0020 to 0022), Aemi promotions without a
waiting consumer (0076, 0087), AskMCP conformance (0123), subagents (0063), Xcode's code model (0073), taking over a session (0115),
distribution (0070), Protobuf, MDM, Linux and Windows, compiled plugins, Mermaid, codemode, AemiHMMML.
