---
status: not-started
blocked-by: []
date: 2026-10-28
---

# 0079 — Findings from the review of what reached main on 2026-10-26 to 2026-10-28

Two reviews of the 75 unpushed commits (`origin/main..main`, after `49dec69`), on the reconciled tree in
`Github/g-cqd/ask`: a code review (what the gates do not see) and a comparison of the owner's requests
with what shipped. The requests come from the merged ask and pi session stores (`Github/sessions/`,
extracted by `Scripts/requests.py` into `Github/notes/requests/`). Work that the sessions show was done for
another project is out of scope and was not read.

Gates run: `Scripts/quality.sh --check` (swift-format, SwiftLint, deadwood 0.11.1, dolly 0.11.0, arcleak 0.12.0,
measurement guards, release build, 878 tests) was **green**. It ran before the reauthor, which changes no
tree content except one diary line. Not re-run since. Labels follow the code-review skill. Nothing here was fixed
by the review.

**Reviewed in depth:** `ConfigEditor+Write`, `PathDisplay` and its use in the resume banner, the shell
readiness and job-wait tools, the analyzers' output. **Skimmed:** the Copilot connection (origin pinned to
`*.githubcopilot.com`, redirects refused, the GitHub grant only used for the token exchange — sound), the Apple
provider's tool bridge (capture only; the loop runs the call under the sandbox — sound).
**Not reviewed:** the Mistral decoder, the screen redesign (`ScreenComposer*`, `StatusLine`), the picker and
input changes, MCP exposure control, `memory-safety` on `ConfigEditor.run` and `JobWatchdog`.

## Resolved locally, not yet pushed

- [x] **The 75 unpushed commits carried the work address.** Rewritten to the g-cqd no-reply identity with
  `git filter-branch` on `origin/main..main` only (published hashes unchanged); commit hashes quoted in the
  diary before this entry may not match. Unsigned: the signing key has a passphrase. Push only after
  deciding whether to re-sign. A diary line naming an unrelated project was reworded.
- [ ] Add the guard so it cannot recur: `Scripts/land.py` refuses an author other than the configured no-reply
  address, and the machine gets the `includeIf "gitdir:~/Developer/g-cqd/"` identity rule.
  Done: `land.py` refuses commits whose author or committer is not the no-reply address (guard only; the `includeIf` rule is still owed and touches the live `~/.gitconfig`).
  Also done: roadmap 0063 front matter fixed, 0059 marked superseded, the two backup branches deleted (their four commits are on main under the same subjects).
  Finding: `--write`/`--read` take one value by design, so `prefix(1)` is the CLI limit; printing every path needs the flags to repeat, which is a feature, not a fix.

## Blocking

- [x] **Terminal-escape injection through `PathDisplay`.** `link(to:display:)` puts the label inside an OSC 8
  sequence without removing control characters, and `shellArgument` backslash-escapes an ESC byte instead of
  removing or quoting it, so the raw byte still reaches the terminal. The workspace path and the session path
  are printed by `printResumeCommand` after exit. A workspace directory named `x<ESC>]52;c;…<BEL>` (a cloned
  repository chooses its directory names) writes the clipboard or retitles the window when the user quits. A
  newline in a path cannot be pasted with a backslash either (`\<newline>` is a line continuation). Fix: reject
  or percent-encode C0/C1 controls in `link`; quote any path holding a control or newline with `'…'` and
  `'\''`. Tests for ESC, BEL, newline and a quote in `PathDisplayTests`. This matters more once item
  "links in the transcript" below puts paths into every block.
  Done: `PathDisplay.link` prints a path or label with a control character as plain sanitized text, `printResumeCommand` prints no command for such a path, and `PathDisplayTests` covers ESC, BEL, newline, DEL and C1.
- [ ] **A roadmap entry is marked done while its request is open.** 0075 has `status: done` but its own
  "Still owed" section holds the owner's request of 2026-10-27 21:28 (paths in blocks are links). Set it to
  `in-progress` until that ships. (Done in this commit.)

## Drift from the owner's requests

Each line: request (date, time) → what main has → what is owed.

- [ ] **Links on paths shown in blocks** (10-27 21:28) → only the exit banner is linked. Owed: tool headers, tool
  bodies and diagnostics (0075), after the escape fix above. TerminalKit needs OSC 8 support in its cell model
  for rows that wrap; confirm before starting.
- [ ] **Replace Swift Regex by AemiRegex everywhere** (10-27 21:51, 21:52) → roadmap 0077 is `not-started`; the
  package is a dependency and `ShownToolInput` uses it, `ProviderFailure+Overflow` still uses Swift Regex.
  Inventory not yet written. The ergonomics checklist keeps the item open.
- [ ] **Semantic tool payloads, no `--- input ---` / `--- output ---`, configurable output limit with a centre
  collapse, byte formatting** (10-27 22:27) → 0078 `not-started`; only compact `[x:y]` intervals, divider removal and
  typed write facts landed. Owed: pretty-printed payloads, `ui` output-limit setting, the byte-format setting.
- [ ] **Copilot pricing snapshot** (10-27 after the port) → ask has the connection and the catalog, not the pricing
  snapshot with its daily refresh. **The quota bar (used / left, colour-coded, in the status line) is not a priority
  at all** (owner, 2026-10-28): leave it out until asked again.
- [ ] **Pixel rule above and below the input, terminal-palette tint** (10-26 13:52, 10-27 08:48) → character rules
  only; `OSCPalette` is waiting for TerminalKit (0074 stays in progress). The TerminalKit handover report exists.
- [ ] **Asynchronous semantic job naming** (10-27 18:22) → investigated, constrained to UX only, not implemented.
- [ ] **Promote reusable algorithms to Aemi subpackages** (10-27 21:37) → 0076 `not-started`. The skill search uses
  the existing `AemiText.editDistance`, so nothing new was owed for it; nothing else has been inventoried.
- [ ] **Real-terminal fold behaviour** (10-27 15:12 and later) → synthetic PTY/pyte checks pass; no physical
  terminal run is recorded. The startup cohorts (30–45 ms) exceed the 25 ms target under host load; the budget
  and its measurement conditions should be restated.
- [ ] **Ergonomics checklist leftovers** (`ergonomics-implementation-checklist-2026-10.md`): update the PTY probes to
  the new tool schemas and headers; mutation-sensitive controls (threshold ±1, wrong identity); verify resume flag
  fidelity for paths with spaces and quotes; release performance comparisons.
- [ ] **The study deliverable is not committed.** The 10-27 request for studies "documented in the repo" produced
  `docs/research/interactive-ergonomics-and-context-study-2026-10.md`, which is untracked on this machine and was
  never part of a commit. Commit it, or fold it into the checklist and delete it.
- [ ] **"Strip anything about pi-integrations or the work project"** (10-27 18:32) → ADR-0116, diary
  2026-10-27-03 and older research name `g-cqd/pi-integrations` (a public sibling repository, cited as
  provenance). Nothing about the other project remains. Decide whether the citation stays; if it goes, the
  provenance is lost.
- [ ] **Tool surface** (10-27 19:07) → delivered: `read`, `write` (replace+create), `bash` (shell, readiness, waits)
  and `job` (input/status/stop). Left over: `WaitTool`, `JobInputTool`, `JobStopTool` and `EditTool` are no longer
  registered; they stay as code reachable from tests only (see the deadwood item) — delete them or keep them
  behind the new tools.
- [x] Delivered as asked, no drift found: login/logout and account/model/effort choice in the conversation
  (ADR-0117), provider follows the model (0118), `--verbose` and what the status says (0119), the least sandbox
  information to the model (0115), the Apple on-device model with every tool (0116, 0120), the status line below the
  input, block padding and tints, whole-block folding, resume picker, context occupancy, spinners, job lanes
  and ids, duration formatting, word movement, the interactive `/config`, categorised slash commands, the
  skill and MCP exposure controls, the Mistral content-parts decoder and the `[DONE]` frame fix.

## Suggestion

- [x] **`ConfigEditor.writeAtomically` replaces a symlinked config with a regular file.** `rename(2)` over a
  `settings.json` that links into a dotfiles repository swaps the link for a file and leaves the real one stale.
  Resolve with `realpath` before choosing the temporary directory. Test with a symlinked target.
  Done: the target path is resolved first; `ConfigEditorSymlinkTests`.
- [ ] **Read–modify–write without a lock.** Two `ask` processes editing at once can lose an edit. Take a short lock
  like the credentials transaction (ADR-0039), or write in the ADR that last-writer-wins is accepted.
- [ ] **The resume command prints only the first `--write`/`--read` path** (`paths.prefix(1)` in
  `Flags.arguments`). The resumed run is narrower than the original unless the session file decides. Say which, or
  print every path.
- [x] **`shell` argument of the bash tool accepts any absolute executable** (`JobTable.isShell` checks existence
  and the execute bit). The model can name `/usr/bin/python3` as the shell. Restrict to `/etc/shells` plus the
  configured shell.
  Done: a named shell must be in `/etc/shells` or be the configured `SHELL`; otherwise the configured shell is used. Test added.
- [ ] **`wait_for_port` is allowed whenever the network is not `.none`**, including a domain-limited policy.
  State in ADR-0043 which hosts it may touch (loopback only?), and route a host argument through the connection check.
- [ ] **Copilot impersonates VS Code** (client id `01ab8ac9400c4e429b23`, `editor-version vscode/…`,
  `copilot-integration-id vscode-chat`), as requested ("as if it was vscode"). The code says "not a claim of official
  parity", but the terms of service of the service are the owner's decision; record that decision in an ADR.
- [ ] **`PathDisplay.tilde` resolves symlinks** for paths outside `home`. Fine at exit; one syscall per row per frame
  if moved into the render path. Compute once per block, with a benchmark (ADR-0016).
- [ ] **Code reachable only from tests (deadwood, 16 notes).** `JobInputTool` (not registered since `eb3d3f1`'s
  subject, "smaller tool surface"), `SandboxRequestError`, `CredentialFile.remove{Agy,Codex,Claude,Key}`,
  `rotationIsUnsaved` (×3), `Budget.isWithinBudget`, `MCPToolName.isMCP`, `JobWatchdog.simulateDeath` /
  `openDescriptorForTesting`, `MCPHost.waitUntilListed`, `StdioTransport.waitUntilRunning`, `MCPConnection.ping`.
  Move helpers to the test target or behind `package` access.
- [ ] **Duplicated code (dolly, 669 notes, 86 suppressed).** Mostly tests. Triage the `Sources/` ones and record
  the count as a budget.

## Nit

- `ConfigEditor+Write.swift` repeats the same `cannotWrite(path:reason: strerror)` guard four times; one helper
  removes it. The ignored directory `fsync` needs a comment saying why.
- `.ask-config-<uuid>.tmp` files stay behind if the process dies between `open` and `rename`; sweep stale ones
  at the next editor open.
- "Record …" commits double most feature commits; one commit per feature with its diary entry is the
  engineering-practices unit.

## Process

- [ ] Review the unreviewed areas above with `secure-coding` (MCP per-server exposure), `memory-safety`
  (descriptors in `ConfigEditor.run`, `JobWatchdog`) and the screen redesign with `code-review`.
- [ ] Re-run `Scripts/quality.sh --check` on the reauthored tree before any push.
- [ ] The migration kept two local backup branches (`backup/local-main-b3c0699`, `backup/local-main-db6510f`) from the
  other machine. Compare them with `origin/main` (the first one's patch differs from `6d55977` in 22 files) and
  delete or merge.
