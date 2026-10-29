# Roadmap review and priorities for the next session (2026-10-29)

The whole roadmap was read for status and what each entry still owes (143 entries: 67 done, 32 in progress, 44 not started), and `ask-wishes.md` (93 lines) was
reread and matched to entries. The owner's standing constraints apply: no regressions, budgets as written, sandbox always,
system APIs first; deprioritised are the Copilot quota bar, distribution (0070), CI billing and AemiRegex (0059, 0077).

## The wishes, matched

Every wish has an entry. **Done:** the tool header (0080), empty thinking blocks (0081), Command copy and paste (0082), interrupt and queue
settings (0083), wrapping and input Markdown investigated (0085), the image tool (0084), keep awake (0090), the default shell (0091),
`/tree` selector (0093), Option+Backspace (0095), continue (0097), no turn limit (0098), "Compacting…" (0099), job rows with … (0100),
the compaction block (0105), purple ask blocks (0106), colours follow the system (0108), Right twice (0112), the four cells (0124), the
scroll stop (0125), `~` for home (0128), block colours (0129), resize after reload (0132), the `!` click (0133), token counts (0136).

**Open:** the timeout's short form (0126, owner's answer pending), a second account per provider (0092), the tree selector's structure and
model turns (0093, lower priority by the owner), providers limited per repository (0094), a generated config example (0096), system
APIs (0101, in progress), debug mode (0107), AemiHMMML (0109), the keychain (0110), prompt history (0111), commands at the next turn
(0113), MCP (0114, 0123), taking over a session (0115), the picker as confirmation (0116), a question tool (0117), strong setting types
(0118), event-driven exchanges (0121), Protobuf (0122), watched config layers (0127), MDM (0130), approvals (0134), Linux and Windows
(0135), slimmer schemas (0137), AemiHTML (0139), compiled plugins (0140), reconnecting (0141), one interruption block (0142).

## Next session, in order

### 1. Regressions and small bugs (cheap, each under an hour)

1. **Paths in replies are not links (0075, 0079).** Checked: `/tmp/a.swift:12` and `` `~/b.swift` `` in a reply get no link with
   Markdown on or off; Markdown links bare URLs and `[text](path)` only. Run `PathLinks` over prose and code-span runs, the owner's request
   of 10-27 21:28.
2. **`/model` then typing joins the prompt to `/thinking `.** The pre-filled command should be selected, so the first key replaces it, or
   the thinking picker should open instead.
3. **One interruption block (0142, option 1).** "Stopping…" moves to the status bar as "Reconnecting…" did (0120); one block remains.
   The colour-only option waits for the owner.
4. **MCP at idle (0143).** Connect on first need; the owner's three servers take a fresh screen from 14.5 to 27.6 MiB.

### 2. Cheap UI and UX wins

5. **A showcase for a real terminal.** `Scripts/showcase.py` prints a mocked conversation with every block kind, Markdown (headings, lists,
   tables, quotes, code folded and open), links (OSC 8: http, file, misleading), tints and the status line, on a light and a dark page.
   One run in each terminal closes the "not seen in a real terminal" lines of 0049, 0051, 0065, 0075 and 0108, which the 0108 wish asked
   for ("print mocked sessions with various blocks").
6. **Wrapping, the cheap half of 0085:** a token wider than the row starts where it is (no orphaned `see`), and a hanging indent under
   `- `, `* `, `1. `, `> ` and leading spaces in your messages and Markdown-off replies.
7. **`/markdown`** toggles `ui.markdown` for the session (0065 left it open).
8. **The timeout's short form (0126):** propose `ui.timeout: "auto"` (shown when a command was given one) and implement when answered.
9. **Close the finished entries.** 0016, 0025, 0053, 0062, 0064 and 0074 list nothing owed; 0049 and 0075 owe only a real-terminal check
   (item 5). Verify each against the code and set it done, or split what is left into a new entry. A shorter open list is easier to plan.

### 3. Very valuable UX, larger

10. **Reconnect (0141):** carry on an answer after a drop, wait for the network instead of five tries in 15 s. Reported by the owner today.
11. **Prompt history (0111):** Up and Down through earlier prompts and commands; daily value, contained in `PromptEditor`.
12. **Commands at the next turn (0113):** `/model` and the like take effect at the next request, not only when idle.
13. **Confirmation, approvals and questions (0116, then 0134, then 0117):** one picker-based design for consent. More pressing now: the
    configured Xcode and LLDB servers can build, run code snippets and drive the debugger, outside ask's sandbox, with no approval step.
14. **Input word wrap and Markdown colour (0085 proposals 1 and 4):** TerminalKit `InputLayout` option, then colour as proposed.
15. **A second account per provider (0092)**, **taking over a session (0115)**, **debug mode (0107)**.

### 4. Memory, cost and infrastructure

16. **Payloads on disk (0088 step 3, second part):** designed; about 9 MB of a 12 MB session's strings; needs the owner's go-ahead.
17. **Slimmer schemas (0137):** tokens per turn are money; an investigation with a measured table first.
18. **The 0079 leftovers:** a `secure-coding` review of MCP exposure (now in use), and the real-terminal fold check (item 5).
19. **Watched config (0127)**, **keychain (0110)**, **strong setting types (0118)**, **providers per repository (0094)**, **the generated
    config example (0096)**, **system APIs (0101)**.

### Parked

Distribution and release (0070), the Copilot quota bar, CI billing, AemiRegex (0059, 0077), event-driven exchanges (0121), Protobuf
(0122), MDM (0130), Linux and Windows (0135), compiled plugins (0140), Mermaid (0066), codemode (0012, shelved), AemiHMMML (0109, until a
consumer needs it). **Proposed to close:** AemiHTML (0139), which was conditional on AemiMarkdown needing HTML, and it does not (its diary,
2026-10-29: CommonMark recognises HTML by a regular grammar).

## Questions for the owner

- 0126: `ui.timeout` auto, always or never, and `ui.timeoutLabel`.
- 0123: per-server MCP keys, and `ask` as the sampling default.
- 0142: one block, or no block and a colour.
- 0085: which of the five proposals to file.
- 0088 step 3, second part: go ahead?
- 0139: close?
