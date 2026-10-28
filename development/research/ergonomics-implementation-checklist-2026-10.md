# Interactive ergonomics implementation checklist

Reviewed against `interactive-ergonomics-and-context-study-2026-10.md` on
2026-10-27, with code baseline `373adf4`. The source study is concurrently authored
and untracked on main; this file does not edit, stage or certify it. Its token
savings and usage percentages are estimates, not measured acceptance criteria.

## Landed in the first batch

- [x] Unified advertised write tool; whole writes, exact-byte replacement, mixed-mode refusal.
- [x] Unified advertised job input/status/stop; process-group teardown preserved.
- [x] Shell output/port readiness and explicit/default shell selection.
- [x] `tool · summary` headers (not yet structured targets/parameters).
- [x] Skill descriptions capped at 80 characters, including ellipsis.
- [x] Alt-arrow / Alt-b/f word movement and Shift+Alt-arrow selection.
- [x] Enter on bare choice-taking slash commands opens choices.
- [x] Accepted and late-restarted queued prompts replace placeholders by ID.
- [x] Clean-quit resume banner with quoted workspace, session path and flags.

## Context discovery batch

- [x] Above 16 eligible skills, replace the initial list with search instructions.
- [x] Skill query/browse mode: bounded metadata results, full-description matching,
  stable ordering, source/scope narrowing, no loading or advertising user-only,
  bundled-by-default, shadowed or untrusted skills accidentally.
- [x] Preserve name-based skill loading and on-demand full instructions.
- [x] Per-server MCP `maxDirectTools`, including zero and exact-threshold behavior.
- [x] Per-server explicit `mode: search|direct`, with documented precedence over
  automatic thresholding and tool allowlists; neither path widens the allowlist.
- [x] Search-result promotion into active tools, bounded and session-scoped;
  withdrawal when a server/tool disappears; preserve approval/sandbox checks.
  Implementation: at most eight most-recent matches per server, replaced on each
  nonempty search; listing changes/disconnects withdraw all of that server's promotions.
- [x] Reuse pinned `AemiText.editDistance` for typo-tolerant skill discovery;
  literal relevance precedes fuzzy scores; source/trust filters run first.
- [ ] Promote any additional reusable algorithms into Aemi subpackages (roadmap 0076),
  keeping ask-specific relevance and permission policy here.

## Shell and tool presentation batch

Execution order selected by the owner: tool presentation → shell lifecycle →
interactive configuration → categorized picker → file-path/link ergonomics (0075).

- [x] Present bash invocations as `shell` without breaking persisted tool identity.
- [x] Tell the model the active shell, using the filtered launch environment and
  any explicit override, so commands do not assume bash syntax under fish.
- [x] Add file readiness and output/completion waits for already-running jobs;
  preserve timeout, cancellation, bounded output and non-consuming UI snapshots.
  Readiness is validated before launch and rechecked by opened object after a file
  event, so a symlink/directory swap cannot satisfy a protected path. Port waits
  require the effective sandbox network policy. Job waits use canonical/display IDs
  but never take ownership; timeouts and cancellation leave the job running.
- [x] Structured `tool · target · compact parameters` headers for read/write/job/shell.
- [x] Carry full input through live events AND replay; unfold full input above output,
  including commands with empty output. Preserve copy offsets and fold ownership.
- [x] Fold heredoc payloads above **40 lines** (the user's explicit threshold takes
  precedence over the study's 50), with delimiter, omitted count, and explicit expansion.
  Common literal cat/tee/interpreter openers use AemiRegex; unsupported/ambiguous
  shell forms remain fully visible rather than guessing. This is not a shell parser.
- [ ] Migrate existing Swift Regex uses repo-wide to AemiRegex, with parity and
  performance evidence (roadmap 0077).

## Configuration batch (done)

- [x] `/config` interactive user/project scope selection and key navigation.
- [x] Up/down keys, left/right enum/boolean/spinner choices; Enter commits.
- [x] JSON/JSON5 via AemiJSON; atomic writes, indentation preservation, unrelated
  settings retained; clear error handling and no writes on cancel/read.
  JSON5 comments do not survive a save: AemiJSON re-encodes strict JSON.
- [x] Reload edited settings through existing validation and safety boundaries.
  Strings, numbers, paths and lists are listed read-only rather than guessed at;
  scope switching inside the editor and a raw-text mode remain follow-ups.

## Picker batch (done)

- [x] Categorize commands into session/model/tools/configuration.
- [x] Render group headings without making them selectable; preserve keyboard,
  click, scroll, search, small-screen and Escape behavior.

## File links and resume banner batch (done, roadmap 0075)

- [x] Clickable terminal file links (OSC 8) on session save with fallback.
- [x] Display `~/…` relative paths for files within user home.
- [x] Clean-exit resume command with unquoted command/flags and shell-safe paths.
- [ ] Verify resume flag fidelity and launch paths with spaces/quotes; define which
  exit paths print the banner. Ctrl+C must retain its existing abort/draft semantics,
  rather than being converted into unconditional process exit by the study example.

## Tool-presentation follow-up requested after the first presentation batch

Roadmap 0078 is queued, not implemented by the shell-lifecycle work:

- [x] Compact read intervals `[x:y]`.
- [x] Remove input/output dividers; full-brightness input and subtly dim output.
- [ ] Semantic, pretty-printed tool payloads without raw argument-object dumps;
  preserve exact commands/source bytes for copying and execution.
- [ ] Configurable default unfolded-output line/byte limits, center collapse,
  head/tail retention, accurate hidden counts and independent expansion.
- [x] Replace write acknowledgement line counts with typed byte/replacement facts.
- [x] Assess IEC byte display; recommended `1 KiB (1,024 B)`, with compact/exact/both
  UI choices if warranted. Keep file-size and changed-byte meanings distinct.

## Cross-cutting acceptance

- [ ] Update real CLI/PTY probes affected by changed tool schemas and headers.
- [ ] Mutation-sensitive behavioral controls: threshold ±1, wrong identity, removed
  scope filters, missing unregister, reversed key movement, lost config fields.
- [ ] Focused red run per coherent batch, implementation, then one broad review/gate;
  avoid repeatedly rebuilding unchanged test executables.
- [ ] Release performance comparisons; label PTY evidence separately from physical
  terminal acceptance. Advisory job names and palette-aware status softness remain
  separate outstanding requests, not implicit outcomes of this study.
