# AemiMarkdown and TerminalKit challenged, and the schedule, 2026-10-29

The owner asked for both packages' roadmaps to be challenged for what they would unblock in ask, and for a final schedule. Read and run on
2026-10-29: AemiMarkdown at `31af2f2` (tests run), TerminalKit at `c3382bd` (tests run, all green).

## 1. AemiMarkdown

What it is: a streaming CommonMark 0.31.2 + GFM parser writing two tapes over UTF-8, 5,800 lines, one ADR, one diary entry, no roadmap file.

What is true when run:

- The allocation tests, the package's headline claim ("allocates nothing per node"), pass in a release build and fail 31 checks in the
  debug build `swift test` uses by default, because a debug build allocates. The default gate is red for a known reason.
- The differential tests against the AemiRegex engine are behind `AEMIMARKDOWN_DEV`, so they are not in the default run.
- The README says "under construction"; the 652 CommonMark and 30 GFM examples pass per its own record (not re-run here beyond the suite
  above), so the status understates it, and nothing says what remains.

Challenge: what unblocks ask is not more parsing, it is what stands between the tapes and a screen.

1. **A tape reading API with stable block identity.** A streaming answer reparses; "closed blocks are final" is already true. The consumer
   needs that said as an API: each closed block has an identity and a byte range that never changes, so a renderer lays it out once and
   caches the rows, and re-lays-out only the open block. That is what makes markdown in a transcript cost the delta, and it is the same
   property the memory work in ask 0088 wants (rows kept per closed block, droppable and rebuildable).
2. **A walker over the tapes**, so a renderer is not written against raw tape layout: events (enter block, text span, enter inline, leave)
   with source slices.
3. **The gate**: release-mode allocation tests (or skipped in debug with the reason), the differential tests in the default run, DocC,
   a fresh benchmark record against swift-markdown on the current revision.
4. **Decisions owed by the owner**: the licence of the spec fixtures (CC BY-SA 4.0: keep attributed copies, or generate expected output
   from cmark at test time); and the honest status line.

Size: about two sessions. It is on the critical path for 0065, 0085 and 0066, and for rendering a compaction summary or a model answer
well.

## 2. TerminalKit

State: 15 of 20 roadmap entries done; 0016 to 0019 in progress; 0020 ("what ask needs from the kit") not started. The tests pass. macOS only
by declaration.

Challenge, in the order ask's roadmap needs it:

1. **Palette and theme (0020 item 2) were built in ask instead.** ask now has the OSC 10/11 query and reply handling (`TerminalColours`),
   the page model with WCAG contrast and tint mixing (`ScreenTheme`), the derived secondary-text grey, and the macOS appearance
   notification. All of it is terminal knowledge with no ask in it. Move it into the kit (`TerminalKitStyle` for the colour mathematics,
   the session for the query), so Atelier gets it and ask drops 300 lines. Mark item 2 done by that.
2. **A markdown renderer: `TerminalKitMarkdown`**, tapes in, styled rows out at a width: headings, lists, quotes, thematic breaks, tables
   with column layout, links as OSC 8 cells, wrapped paragraphs, and a hook for a highlighter in fenced code. It needs the walker from
   AemiMarkdown. It is the missing piece of ask 0065 and 0086, and it belongs in the kit because Atelier renders markdown too. Not in the
   roadmap today.
3. **Row virtualization.** ask lays out the whole conversation and keeps every wrapped `Line` (3 MB and many strings for a 1,930-response
   session, ask 0088). The kit's layout (0012) and foldable content (0018) are the right home for a row source that keeps per-item line
   counts and builds the visible slice on demand. Not in the roadmap today; it is the owner's idea for the memory budget, done once.
4. **Close 0016 to 0019 against what ask now uses.** Selection across folds, mouse regions and click actions, folding of code and images,
   the bounded input are all in daily use in ask; the "still owed" lists should shrink to what ask has not exercised, with the rest marked
   done.
5. **Scroll as one state.** ask had two scroll paths (wheel clamped, Page Up not: 0125). A `ScrollState` that owns the bounds belongs in
   the kit.
6. **Linux (ask 0135).** `platforms: [.macOS(.v26)]` only. First step: a Linux container build of each target to list what is Darwin-only
   (the terminal I/O is POSIX and should port). Windows: ConPTY, separate.
7. **Event-driven (ask 0121).** The input thread, the render loop and the signal handling are where exchanges wait; the investigation
   starts there.

Size: items 1, 4, 5 are small (a session together); 2 is medium (after AemiMarkdown's walker); 3 is medium; 6 is a small investigation.

## 3. Other Aemi work that gates ask

- **AemiMCP**: ask's `AskMCP` becomes its own package on the Aemi packages (0123); conformance suite, HTTP+SSE, resumable streams, resources,
  granular per-server permissions; head-to-head with the official Swift SDK. Large.
- **AemiRegex everywhere in ask (0077)**: medium, parallel to the others.
- **AtelierLexers promoted (0087)**: needed for highlighting inside markdown fences; medium.
- **AemiHMMML (0109)**: TOML and YAML; then 0130 (MDM). Large, last in the family.

## 4. The schedule

Ordered by what unblocks what; sizes are rough (S: under a session, M: about a session, L: several).

**Phase 0, now: bugs and finishing touches**
1. 0132 resize after `/reload` garbles the screen (a PTY reproduction first). S–M.
2. 0136 token counts: done, a display fix (below). 0133 click `!` to name the missing sandbox. 0106 purple blocks for ask's own messages
   (all questions answered). S each.
3. 0131 `probe-interactive.py`: 49 stale checks, scenario by scenario, split into one probe per scenario. M, can interleave.

**Phase 1: memory and the shared foundations**
4. 0088 steps 1 and 2: free the opening updates; decide RSS or footprint for the budget (owner); add the long-session figure. S.
5. TerminalKit: move palette/theme out of ask (item 1), `ScrollState` (5), close 0016–0019 against ask (4). M.
6. AemiMarkdown: walker, stable block identity, gate green, DocC, benchmarks (decisions: licence, status). M.

**Phase 2: markdown and the transcript**
7. TerminalKit `TerminalKitMarkdown` renderer. M.
8. 0087 AtelierLexers promoted. M.
9. ask 0065 and 0086: markdown in the transcript behind `ui.markdown`, with the three ADRs. Then 0085 (input colouring). M.
10. 0088 step 3, row virtualization in the kit and ask (the owner's idea), with the markdown row cache. M.

**Phase 3: MCP**
11. AemiMCP extraction, conformance harness, HTTP+SSE, resumable streams; REA and apple-docs as real checks (0114, 0123). L.
12. 0077 AemiRegex in ask (parallel).

**Phase 4: configuration and commands**
13. 0118 typed settings with 0126's `ui.timeout`/`ui.timeoutLabel` and 0123's per-server keys. M.
14. 0127 watch and layer config files; 0113 assessment table for the owner; 0096 generated example; 0094 model scopes. M.
15. 0110 keychain. M.

**Phase 5: consent and interaction**
16. 0116 picker as confirmation, then 0134 the approval system, then 0117 the question tool. L.
17. 0111 prompt history. S.

**Phase 6: large features and investigations**
18. 0115 take over a running session; 0107 debug mode; 0063 subagents; 0066 Mermaid.
19. 0135 Linux and Windows; 0137 slimmer schemas; 0121 event-driven; 0122 Protobuf (after AemiProtobuf); 0109 AemiHMMML then 0130 MDM.

Parked as before: provider items needing accounts, distribution (0070), codemode (0012), the extension host (0033), the pixel UI.

One placement the owner may want changed: 0134 (approvals, on by default) is a security feature; it sits after the Aemi work because you
asked for that order and it depends on the picker (0116), but it could move to the front of Phase 5's predecessors if you prefer it before
markdown.

## 5. Decisions the owner owes

1. RSS or physical footprint for the 15 and 20 MiB budgets (ask 0088).
2. AemiMarkdown: the fixture licence approach, and the honest status line.
3. 0126: `ui.timeout` as `auto`/`always`/`never` plus a bounded `ui.timeoutLabel`.
4. 0123 permissions: confirm the proposed per-server keys and `ask` as the default for sampling.
5. 0133: should a click on `!` when sandboxed say `sandboxed`?
6. 0134: are read-only tools exempt from approval by default?
7. Double-Right while a turn runs (0112): ignored today.

## 6. Owner's answers (2026-10-29)

1. The budget is resident size: 15 MiB idle, 20 MiB active. It stands; improvements are studied and built when they do not worsen another
   metric significantly (ask 0088).
2. AemiMarkdown is MIT; fixtures stay attributed under their licence, with a README notice for differently licensed distributed files.
3. TerminalKit's consolidation comes before AemiMarkdown's finishing: Phase 1 item 5 moves ahead of item 6, and the renderer's design is
   settled in the kit first.
4. The schedule is otherwise accepted.
5. `!` becomes a green `✓` when the sandbox is on, expanding on click to a green `sandboxed`, and stays `!` (warning colour, "not
   sandboxed" on click) when it is off (ask 0133).
6. Read-only tools are exempt from approval by default; a setting can require approval (0134).
7. Double Right during a turn stays ignored.
