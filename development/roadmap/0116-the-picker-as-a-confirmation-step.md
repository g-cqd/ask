---
status: not-started
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

