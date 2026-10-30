---
status: in-progress
blocked-by: []
date: 2026-10-28
---

# 0116 — The picker as a confirmation step

Owner wish (2026-10-28 20:33): extend the selector/picker into a confirmation tool for actions that benefit from the person's consent
before ask continues.

## Still owed

- List the actions that should ask: destructive commands, leaving the sandbox, overwriting configuration, deleting sessions, MCP tools
  marked destructive (ADR-0111 asks today in its own way).
- One shape for all of them: the question, the choices (allow once, always, refuse), the default, and the keys.
- Shared with 0117 (questions from the model), which needs the same picker with more choices.

## Proposal (2026-10-29), for the owner to confirm before it is built

**Today:** a sandbox request and a destructive MCP tool both add a notice ending in `y once · a for this session · n no`, take one letter,
then add a second notice ("Allowed once."). Nothing can be clicked, the choices are only named in the notice, and two blocks stay behind.

**One confirmation, drawn where the command picker is** (above the input, never hiding it; the draft keeps its text):

    Run `rm -rf build` outside the sandbox (writes /tmp/x)?
    › Allow once                      y
      Allow for this session          a
      Refuse                          n
      Refuse, and tell the model why  r

- **Keys:** Up and Down move, Enter chooses; the letters still answer at once; a click chooses a row; Esc refuses; Ctrl+C stops the turn
  (as today, refusing first). Keys go to the confirmation while it is open, as they go to the y/a/n question today.
- **Default row:** proposed **Allow once** for sandbox requests the person can see whole, **Refuse** for anything destructive (an MCP tool
  marked destructive, later 0134's riskier kinds), so a stray Enter never deletes. To confirm.
- **"Refuse, and tell the model why"** opens a one-line note under the rows; the note goes back to the model with the refusal. (0117
  needs the same note.)
- **The conversation keeps one block:** the question, with the answer added to it when chosen (`→ allowed once`), in ask's purple.
- **Later rows by context:** "Always allow (saved to your config)" once 0134 has `approvals.allow`; the picker takes any list of choices,
  so 0117's questions reuse it with their own rows.
- **Who uses it first:** the sandbox requests (ADR-0021) and destructive MCP tools (ADR-0111), which already ask; then 0153's protected
  paths, 0134's per-tool approvals, overwriting configuration and deleting sessions.

**To decide:** the default rows above; whether "Refuse, and tell the model why" belongs in the first version; whether the answered
question should stay in the conversation at all, or only in the session file.

## Owner's decisions (2026-10-29)

"Allow this time, allow for the session, deny", or yes or no when it only needs confirming; a section above the input with checkboxes
built of block characters, checked with Space, rows chosen with the arrows, shortcuts with letters or numbers, Enter to confirm; the
answered question stays in the conversation. (Defaults and the "tell the model why" note were not answered: the defaults below are the
proposal's; the note is left out.)

## Done (2026-10-29)

- `ApprovalKind`: `grant` (Allow this time · Allow for the session · Deny, "this time" checked), `destructive` (same answers, Deny
  checked: MCP tools marked destructive), `confirm` (Yes · No, No checked: a request with nothing to remember, today the reset of the
  session's narrowing).
- The section, where the picker is: the question wrapped in bold, then a row per answer, `› [✓] 1  Allow this time  · y` (`[ ]`
  unchecked, `›` and colour on the row the arrows are on). When rows are short the answers are kept before the question's rows.
- Keys: Up and Down move, Space checks the row (one at a time), a number or the letter checks its row, Enter confirms the checked one;
  Esc denies at once; Ctrl+C stops the turn and the question is kept as denied. In a job lane the status line names the shortcuts.
- One block once answered: `<question> → allowed this time` (or for the session, denied, yes, no); nothing is added while it waits.
- Tests: `ApprovalControllerTests` rewritten for the new behaviour, `RunnerApprovalTests` and a picker test updated; mutations (Space not
  checking, destructive starting on Allow) turn them red. Probes through the release binary: `probe-mcp-screen.py` (12 pass) and
  `probe-interactive.py` (264 checks, sections V, W, Y, Z answering with letter then Enter).
- The interactive probe's own emulator did not skip OSC sequences, so since 0075's links in ask's messages it printed their bytes and most
  of its text checks failed; it skips OSC now. Found only here: the probe had not been run after 0075.

Still owed: clicking a row; using the section for 0153's protected paths, 0134's per-tool approvals, overwriting configuration and
deleting sessions; 0117 on the same section.

Owner (2026-10-29): strokes rather than block characters, and boxes that do not stick together: `[✓]` and `[ ]` (the block-character
`▐█▌` boxes joined into one bar down the rows).

Owner (2026-10-29): more white space where it helps reading. A two-cell margin, a blank row under the question and one above the input,
the shortcut letters in a column of their own, and wider gaps around the box and the number:

      Allow it?

    ›  [✓]  1   Allow this time         y
       [ ]  2   Allow for the session   a
       [ ]  3   Deny                    n

When rows are short, the blank rows go first, then the question's rows; the answers always stay.

