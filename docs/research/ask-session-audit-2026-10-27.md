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

- Semantic naming evaluation: empirical comparison of `.general` vs `.contentTagging`
  FoundationModels on large commands up to 17.8 KB recorded in
  `docs/research/apple-semantic-job-naming-2026-10.md`. Established that semantic names
  are strictly advisory visual hints; all core job lifecycle and identification strictly
  uses canonical and display IDs (`75d8ccc`).

## Still owed for ask

1. UI spacing edge case: tool header gap row between command and body is currently
   conditional on `style.padded` (`ScreenComposer+Lines.swift:74`); should apply cleanly
   whenever a block is unfolded with output.
2. Status line and rule styling: rule character lines above and below the input should
   adopt the status line text style/color, and status line text opacity/contrast can be
   further dimmed/softened.
3. Thinking block folding: ensure thinking blocks fold and unfold reliably across all
   rendering states, mouse drag, and click event variants.
4. Tool harness parity: investigate and align `WaitTool` multi-target and timeout semantics
   with harness standards.
5. TerminalKit integration: true terminal palette negotiation (`OSCPalette`) and pixel
   separators when available from TerminalKit.
6. Copilot list pricing refresh and usage/quota footer display.
