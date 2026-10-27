# Ask and Pi session audit — 2026-10-27 (Europe/Paris)

## Scope and correction

The later full local inventory contains 74 user messages across 16 sessions:
26 Pi messages in two sessions, 48 ask messages in fourteen sessions. Includes other
projects, duplicates, confirmations and smoke prompts. Pi is filtered by message date;
ask user entries lack timestamps, so their date is inferred from today's session names.
No earlier-start ask session was modified that day at audit time. Deleted/remote logs
are outside this inventory. Verbatim inventory and detailed assessment were written to
`/tmp/ask-audit-2026-10-27/` during the audit; those temporary files are not a durable archive.

Earlier blanket claims that everything was fulfilled were wrong. The initial version
of this report also became stale as work landed. Source/tests, a PTY emulator, an actual
terminal, service authorization and billing acceptance are different evidence levels.

## Ask requests delivered before the lifecycle batch

- Character input rules above/below; ruled input untinted, no extra blank rows;
  warning separator and padded notices (`b02653e`). Pixel rules are a separate item.
- Compact help and grouped command reports (`2854eba`, `51fab3c`).
- Whole-block fold ownership and thinking placeholder/content swap (`140c131`).
  This implementation did not discharge the later reported folding regression.
- Measured context occupancy/capacity (`df9df07`), not continuous tokenization.
- Selectable slash/bare CLI resume (`3479f5c`), with PTY coverage.
- External kitty.conf opacity and transparent tint colors, parsed by Kitty.
- Experimental Copilot connection port (`c4a6834`) and trailing Claude SSE sentinel
  fix (`e0660ab`), with recorded live Claude acceptance. Not exact billing parity.
- Antigravity catalog identity fix (`8789023`): 15 to 21 selected models in same-account
  comparison. Argon generation was quota-limited, not verified as a successful answer.
- Focused job output (`deb025b`); first-line metadata and full-width continuations
  (`29deb99`); localized conditional durations (`1375d52`); Unicode spinners (`c875d69`).
- Specific job auto-return and turn-abort settings (`1a1b4ba`), Escape navigation-only.
- Tool body alignment and `[code] ✗` formatting (`0e11cbc`). The header/body separator
  remains conditional on padded style.
- Blank job-strip separation and idle-model job timing/spinners (`42cfd4a`), with
  real-job PTY regression and bounded small-screen/click geometry.

## Lifecycle batch accompanying this report

- Typed yielding-job metadata and retained tool invocation IDs route snapshots to
  their original foldable block, independent of the focused lane (`dfb33d8`).
- One faint italic completion item, leading identity/outcome and trailing frozen
  duration/count/status. Snapshots do not consume the output wait will read.
- Collision-safe four-digit hexadecimal display identities, UUID fallback on namespace
  exhaustion; native job-N references remain compatible and short aliases are accepted
  by job tools (`0bf42b9`). No silent migration of model/session references.
- A reproduced rapid-click fold failure is fixed: click-count two no longer turns a
  fold control into word selection (`0e9afde`). Stable-padding tests fail before the fix
  for both thinking and tools. Ordinary transcript text selection remains unchanged.
- New lifecycle PTY probe passes nine checks; updated job-progress probe passes eight.
  These use the real binary and processes through a PTY/pyte, not a physical terminal.
- Batch review found duplicated foreground-tool lookup and noisy output allocation;
  the lookup is shared and snapshot emission is coalesced. See diary 13 for commands,
  counterfactuals, actual gate results and performance uncertainty.

## Still owed for ask

1. Finish semantic job-name investigation, explicitly comparing Foundation Models'
   ordinary and content-tagging use cases. No naming implementation is claimed.
2. Port sibling Copilot pricing refresh and usage/quota UI where intended; independently
   validate live units/headers/visuals. Headers do not establish VS Code billing parity.
3. Compare native wait with harness semantics rather than calling existing process,
   output, file and port waits exhaustive parity or a multi-job wait-all API.
4. Integrate conditional pixel rules/palette support through TerminalKit.
5. Migrate remaining obsolete ready/ask> historical probes, replace the misleading
   unit-test-only Copilot flow probe with real CLI integration, and establish budgets.
   Recent baseline/candidate startup cohorts both exceed 25 ms with high spread.
6. A PTY rapid-click fix is not universal real-terminal acceptance; verify any remaining
   reported thinking-fold symptom rather than assuming all variants have one cause.

## Other projects found in the same sessions

- pi-integrations Copilot: experimental connection, errors, official list-price refresh,
  quota footer and curated mutation script exist locally; fresh audit run had 55 tests
  passing. Copilot files remained untracked/modified. Live quota/billing reconciliation
  was unverified. Do not overwrite that sibling work or equate it with the ask port.
- localization and Xcode clone cleanup: recorded work and local merge commits
  are present; the two requested temporary clone directories are absent. Linguistic
  acceptance and experimental format conversion were not independently established.
- Deep-link location: RFC removal was committed/pushed after approval; external scanner
  acceptance criteria had not been reconciled.
- MAIN-24753 price/currency: substantial implementation and per-commit testing underway
  in another active checkout. Reorder quantity/its tooltip and final history completion
  were not established at audit time. No full simulator/backend acceptance claim.

Keep unrelated repository work separate. Completion is assessed requirement by
requirement; approvals and 'continue' messages do not turn partial features into done.
