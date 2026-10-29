---
status: in-progress
blocked-by: []
date: 2026-10-25
---

# 0065 — Markdown in the transcript: parsed once, drawn with colour, links and code blocks, and switchable

The owner wants the assistant's answer drawn as Markdown: colour, clickable links, richer code blocks. The parser must be fast, safe and
reliable, on by default, and switchable off. Atelier is a source of ideas. Nothing below is built; every number is a target, and every
claim marked *unprobed* is an open question until phase 0 has run it.

**Decided by the owner, 2026-10-25:**
- The placement table below is right.
- **ask writes its own parser**, `AemiMarkdown`. swift-markdown stays as the baseline in the benchmarks and as the test oracle, not as a dependency of the product.
- Highlighted code comes from Atelier's lexers.
- **A selection copies the Markdown source.**
- All formatting adapts when the terminal is resized (section below).
- Mermaid diagrams are their own entry, 0066.

## What exists today (read 2026-10-25)

- `.assistant(text)` is wrapped by `TextWrap.rows` into `Line`s of **one style each** (`ScreenComposer.lines(for:)`, `.default`). No inline style
  runs exist, so bold inside a row cannot be drawn yet.
- `CodeFence.scan` finds fenced blocks line by line, for folding long ones (`ShownCode`, `ui.codeFoldLines`). It is a Markdown block parser's
  one rule, and the new parser replaces it.
- A selection copies `Transcript.contentText`, "the item's own text, not what is drawn" (`TranscriptContent`); every drawn row carries a
  `Source` (block, line, offset, col) back to it.
- TerminalKit has **no hyperlink support**: no OSC 8 in any source or document of TerminalKit, ask or Aemi (grep, 2026-10-25). A `PackedCell`
  is 16 bytes; bytes 2 and 3 of `high` are unused (length byte 0, width byte 1, style id bytes 4 to 7), so a 16-bit link id fits without
  growing the cell. *Read from the source, not yet exercised.*
- `ask -p` writes the model's text to standard output as it arrives (`PrintRenderer`). It is not a terminal and stays raw.
- Atelier (`~/Developer/g-cqd/Atelier`):
  - Its Markdown is a port of tree-sitter-markdown's C external scanner (1,054 lines) plus a grammar: built to **highlight source**, with
    positions and no rendering model. Not an engine for this; possibly an oracle for block structure (*unprobed*).
  - `AtelierLexers` is the part worth taking: 1,888 lines of hand-written scanners over borrowed UTF-8, scanning a line at a time from an
    entry state (`LexState`), for the 20 languages of `Language`, plus plain text. A line-resumable lexer is what a streaming code block needs. It depends on
    `AtelierSyntaxModel`, `AtelierHighlighting` and `TerminalKitText`, so it is not yet usable from ask.

## Where each part lives (decided 2026-10-25)

| Part | Home | Why |
|---|---|---|
| Markdown parser: bytes in, flat block and span records out; streaming; bounded | **its own package, `AemiMarkdown`**, like AemiJSON and aemiregex, on AemiKernel | Generic, with a plausible second consumer (Atelier hovers, KittyCode docs); "generic tools belong in Aemi" |
| Hyperlink cell attribute, OSC 8 encoding, link regions | **TerminalKit** (`TerminalKitRender`, `TerminalKitCodecs`) | Terminal mechanism; it needs its own TerminalKit roadmap entry and ADR |
| Records to styled, wrapped rows: theme, code-block chrome, tables | **TerminalKit `TerminalKitMarkdown`** if a second terminal app wants it, else `AskTUI` first | Depends on `Style`, `TextWrap` and `UnicodeWidth`, not on ask |
| Line-resumable highlighting for fenced code | a promoted `AtelierLexers` (target of Aemi or its own package, then Atelier depends on it) | ask cannot depend on an app repository |
| The `ui.markdown` key, selection policy, folds, wiring | ask (`AskAgentCore/Configuration`, `AskTUI`) | Policy |

**swift-markdown (swiftlang, on cmark-gfm)** is the baseline, not the parser (owner, 2026-10-25: "it seems that we need to write our own"). Its tree is allocated nodes, it is not incremental, and it has no limit on nesting that ask controls (*unprobed*).
Phase 0 measures it on the real corpus as the number to beat, and the differential tests use it as the oracle; phase 1 is not blocked on it.

## Phases, each independently shippable

0. **Evidence, in the diary; no product code.**
   - *Corpus: done 2026-10-25* (`development/research/probe-markdown-constructs.py`, results in `markdown-constructs-2026-10-25.json`): 19,840 assistant
     messages (7.5, 2.5 and 2.4 MB) from 1,227 Claude Code, Codex and Pi session logs, parsed with markdown-it-py. Counts only; no text kept.
     - **Occurs a lot:** inline code (95,791 spans), strong (24,496), bullet lists (9,128), headings (h2 3,031, h3 1,220, h4 100; h1 46; none below),
       fences (1,485; median 2 to 16 lines, p95 14 to 46, max 875), links (inline 2,553, bare 1,397), tables (906), rules (528), ordered lists (1,121).
     - **Occurs a little:** emphasis (567), hard breaks (427), blockquotes (34, never nested), inline HTML (91), HTML blocks (9), math (10).
     - **Never occurs:** images, task lists, strikethrough, footnotes, control bytes or ESC (0 of 19,840), Mermaid (0 of 1,485 fences).
     - **Shapes that set limits:** list depth at most 4; token depth at most 9; a line up to 2,329 bytes; a message up to 58 KB; tables of 3 columns
       (median), 4 to 6 (p95), 10 (max), and 5 to 7 rows with the header (median), 9 to 16 (p95), 38 (max): at 80 columns a 6-column table is the
       ordinary hard case.
     - **Fence languages:** 53 % have none (794 of 1,485); then rust 201, c 91, bash 87, swift 81, xml 57, sh 45, markdown 22, js 18, python 18.
     - **Links are mostly not web links:** 2,227 of 3,959 targets are paths with no scheme (Codex writes `[file](/abs/path:42)`), 1,242 `http`,
       476 `https`, 14 `mailto`. So the link rule must say what a path with a line number does (open in the editor, or copy), and `file:` is the
       common case, not the exception.
     - **Scope cut:** the first parser and renderer cover paragraphs, inline code, strong, emphasis, links (inline, bare, path), headings, lists
       to depth 4, fences, tables, rules, blockquotes, hard breaks; HTML shows as literal text. Images, task lists, strikethrough, footnotes and
       math parse without error and draw as plain text until a corpus says otherwise. Mermaid has no occurrence in this corpus (see 0066).
   - *Links:* kitty is done (below). Still owed: Ghostty, WezTerm (its `cli get-text` needs the new instance's socket), iTerm2 and
     Terminal.app, with mouse reporting on and off, in a PTY probe as in TerminalKit ADR-0028 (Terminal.app ignored OSC 52, so it may ignore
     this too). Does a terminal that ignores OSC 8 still print the text?
   - *Parser baseline: done 2026-10-25* (`development/research/probes/MarkdownBaselineProbe.swift.txt`): swift-markdown `392b73b` on swift-cmark `a7ecfef`
     (gfm), release, the 19,846 assistant messages (12.4 MB), load average 7 to 10, M2 Pro. These are the numbers `AemiMarkdown` has to beat:
     - **Throughput:** 10.3 MB/s parsing (p10 to p90 of five rounds: 1.19 to 1.47 s for the corpus), 8.5 MB/s with a walk over its 513,045 nodes.
     - **Allocations:** 270 per KB of input (per message: p50 46, p95 570, max 6,563).
     - **One message:** p50 8.8 µs, p95 243 µs, p99 796 µs, max 3.1 ms.
     - **A 100 KB answer streamed in 40-byte deltas, reparsed in full each time** (a parser that is not incremental): 4.94 s of parsing in all; a
       delta takes p50 1.7 ms, p95 4.3 ms, p99 4.5 ms, max 7.7 ms, growing with the prefix. That is a frame's budget gone to parsing, by the
       end of a long answer, on every token.
     - *Not measured:* linked size.
     - **Goals for `AemiMarkdown`, to be met and measured, not assumed:** streaming cost per delta independent of the answer's length; no
       allocation per node (a flat tape, reused buffers, a ceiling of a few per message that does not grow with the input); and a parse an order
       of magnitude faster than the above.
   - *Glow:* done (above). Repeat the nested-quote and delimiter inputs against whichever parser is chosen.
   - *Atelier, decided not to run:* its Markdown is a tree-sitter scanner for highlighting and `AemiMarkdown` is not built on it, so it is
     not the oracle. The oracle is cmark-gfm (swift-cmark's `test/spec.txt` holds the GFM spec 0.29's 672 examples) and markdown-it-py. The part of
     Atelier worth taking is `AtelierLexers` (phase 5); whether it needs `AtelierSyntaxModel` for more than `Language` is read then.
   - *Owed, needs the owner at a terminal:* a click-and-hover check of OSC 8 in Ghostty, WezTerm, iTerm2 and Terminal.app (kitty shows a link to a script and the others were not tried), from a script that prints one link of each form. And a licence question for phase 1: the spec's examples are
     CC BY-SA 4.0 (its own header); fixtures copied from them carry the attribution and the share-alike, and the alternative is to generate expected output from
     cmark at test time instead of storing it.
1. **The parser: built, in `g-cqd/AemiMarkdown` (now on GitHub; see 0086), ADR-0001 there.** What is true now, from its diary
   (`development/diary/2026-10-25-01.md`), release, the 19,897 messages of phase 0, load average 6.9:
   - **Conformance:** CommonMark 0.31.2, 652 of 652 examples; the GitHub extensions the corpus uses (tables, strikethrough, extended autolinks), 20 of 20;
     a **ratchet** (a list of failing examples that can only shrink; it is empty) makes a regression or a stale list fail the suite. Footnotes, task
     lists and the tag filter are not built.
   - **Against swift-markdown (phase 0 baseline):**
     - throughput **110 to 113 MB/s** against 10.3 (11x);
     - one message p50 1.9 µs, p99 73 µs, against 8.8 µs and 796 µs;
     - **43 allocations per KB** against 270;
     - 100 KB of real answers streamed in 40-byte deltas, a snapshot after each: **0.010 s** against 4.94 s, per delta p50 3.2 µs and p99 11.9 µs
       against 1.7 ms and 4.5 ms, **10 allocations per delta, not growing with the answer**;
     - the worst shapes: one 100 KB paragraph costs p50 261 µs per delta (the open paragraph is parsed again, O(paragraph)), and one 100 KB code block
       0.7 µs and 4 allocations (O(delta)).
   - **Safety:** 2,000 random inputs, whole and in pieces, give well-formed tapes; nested quotes and lists 5,000 and 2,000 deep stay within the container
     limit and say so (`diagnostics`); 16 pathological shapes stay within 3x work when the input doubles; control bytes and invalid UTF-8 are
     reported; the hand-written HTML-tag and autolink scanners agree with the spec's grammars run by AemiRegex. Each of these tests was seen to fail under a mutation.
   - **Still owed in this phase:** a remote for AemiMarkdown (and for AemiRegex) so ask can pin it; the set-scan kernel and SIMD skipping of plain text
     (the scan is a byte table today, so the throughput is not the ceiling); a profile of the remaining allocations; incremental parsing of the open
     leaf; DocC; the static analysers.
   - **API as built:** `MarkdownParser` (`append`, `snapshot`, `finish`, `parse`), `MarkdownDocument` (`events`, `decode`, `diagnostics`),
     `MarkdownExtensions` (tables, strikethrough, autolinks; all on by default, so `ui.markdown` can pass none), `MarkdownLimits`, `MarkdownEvent`.
2. **Hyperlinks in TerminalKit** (its roadmap, its ADR). A link id in the cell, a process-wide link table like `StyleTable`, OSC 8 emitted by
   the diff only where the link changes, a reset on every exit path of the reset ladder, and a rule for what happens when the table is full.
   Byte-exact tests, an oracle model, and the emulators of phase 0.
3. **Rows with style runs, and the renderer**, laid out for any width, tables included (section above). `Line` gains runs (text plus style) while keeping `Source`; `TextWrap` wraps across runs;
   the composer writes runs and highlights a selection across them; `Shown` compares runs. Then the renderer: headings, emphasis, inline
   code, lists with hanging indent, quotes, rules, tables (column widths from `UnicodeWidth`, wrapping or truncating by width), links, and
   code blocks with a language label, a gutter, and the existing fold. Colours come from the terminal's palette (`.indexed`), so the user's
   theme applies, as the tool lines do today.
4. **Wire it into ask.** Assistant items only: not tool output, not the user's prompt, thinking text decided in phase 0's table.
   - *Switch:* `ui.markdown`, default `true`, joining `ui.tools`, `ui.thinking` and `ui.code`; a command-line and `/` toggle if the owner
     wants one. Off draws what ask draws today, byte for byte (a characterisation test written **before** the change, red against any drift).
   - *Non-terminals:* `ask -p` and a pipe stay raw.
   - *Streaming:* the open block is drawn as plain text until it closes, or its tail is styled, whichever phase 0's measurements show does not flicker.
   - *As built (2026-10-29, ADR-0129):* on by default, `ui.markdown` switches it; off is byte for byte the old drawing. Streaming re-parses
     the whole reply per delta (0.75 ms at 9 KB) rather than drawing the open block plain. No command-line or `/` toggle yet. Copy is the
     source through TerminalKit's row segments. Not checked in a real terminal yet: the look, and OSC 8 click and hover.
5. **Highlighted code.** Atelier's lexers, promoted out of the app repository, colour a fenced block by its info string, resuming per line, with a plain fallback for an
   unknown or absent language.

## Adapts to the terminal's size

Every drawn row is a function of the parsed records and the current width, never of an earlier width. Parsing happens once and knows no width.

- **Layout is pure and cached by width.** The composer already re-lays-out when `columns` changes (`transcriptLines.update(width:revisions:)`);
  the Markdown layout is what it calls. A resize costs O(rows laid out) and is bounded to the rows near the viewport first, the rest lazily.
- **Tables** are the hard case. Each table record keeps its columns' minimum width (longest word) and natural width (longest cell), computed
  once at parse time from `UnicodeWidth`. At layout time:
  - if the natural widths fit, draw them exactly;
  - if only the minimum widths fit, share the spare columns in proportion to natural width and wrap cells inside their columns;
  - if even the minimums do not fit, fall back to one block per row (`header: value` lines), never a truncated grid that hides data.
  - Wide characters never split across a column edge. Row separators and borders use box-drawing only if the terminal's widths for them are
    known (`UnicodeWidth`; ambiguous-width characters are the risk, TerminalKit roadmap 0013).
- **Code blocks** do not reflow: a line wider than the viewport is cut with a visible continuation mark, or wrapped with a hanging indent;
  the choice is a phase 0 question, but the full text is always what copy returns.
- **Lists, quotes, headings and rules** recompute indents and rule length from the width. A nesting deeper than the width allows stops
  indenting and keeps a depth marker, so text never reaches zero columns.
- **A resize does not move the reader.** `BlockHeights` and `ScrollAnchor` (TerminalKitText) keep the row at the top of the screen through a
  change of heights; a width change is the same event as a fold, and a test drives it.
- **Streaming and resizing meet**: a resize in the middle of a streamed answer lays out the parsed prefix and goes on.
- **Tests:** one parameterized suite lays the same records out at every width from 1 to 200 and checks that no row is wider than the width,
  no text is lost (the visible characters, in order, equal the source's), and the layout at width *w* does not depend on the widths before it.
  A PTY probe resizes a live terminal during a stream.

## Faster than what exists: what the first probes found

Run on 2026-10-25 against glow 3.0.0 (diary 2026-10-25-01, `development/research/markdown-renderers-2026-10.md`), not read from its source:

- It is linear on ordinary text but slow: about 100 KB/s, with 16 ms of start-up (158 KB took 1.6 s).
- Its output is **48 times the input** (a style reset around every space), where ask's cell diff writes only what changed.
- A hundred bytes of nested quotes (`>` repeated 100 times) **did not finish in 30 seconds**: the time doubles with about every 8 levels
  from depth 48. A model answer or a tool result can carry that. The parser's depth limit is not optional.
- It writes a raw `ESC ] 52` (set the clipboard) from the Markdown through to the terminal. The sanitizer below is not optional either.
- It draws a link as its text and then, again, its target underlined: a visible target is a known mitigation, and the one to adopt.

## Faster kernels first (done in Aemi, branch `perf/small-input-kernels`, ADR-0014, not yet pinned by ask)

Read, in `adf_scan.c` and `adf_cpu.c`: every dispatched call ran `pthread_once`; the NEON kernels found a hit with a scalar rescan of 16 bytes
and finished a length that is not a multiple of 16 with a scalar loop of up to 15 bytes. Measured with the new `scripts/bench-c-kernels.sh --small`
(ns per call, previous revision in the same binary, interleaved, median and p10 to p90; M2 Pro, `-Os`):

- **At 80 bytes** the five scanners take 1.5 to 2.6 times less time with no hit and 2.4 to 3.2 times less with a hit: about 3 to 6 ns a scan.
- **At 79 bytes** 3.4 to 4.8 times less with no hit: the scalar tail is gone.
- **At 255 bytes** 1.9 to 2.8 times less; `index_of_nonascii` at 64 KiB rose from 25.7 to 86.8 GB/s.
- A control with no code change moved `fold_ascii` at 64 bytes by 20 %, so effects under about 25 % at small sizes are not claimed.
- Not measured: x86-64 (untouched, and it still pays `pthread_once` per call), Linux arm64, `index_of_byte` (`memchr`).
- A defect the first version had was caught by Aemi's Swift tests and not by the new harness; the harness now draws random parameters, and was
  seen to fail without the fix.

Still owed: ask pins the Aemi revision that contains it, and a **set scan** (a byte table in two NEON lookups, any set of up to eight classes) for
the inline scanner, because Markdown has about eleven special bytes and `indexOfAny5` takes five.

## Leaning on Aemi (pinned revision `afc1be3` contains each of these)

| Aemi tool | Use in the parser |
|---|---|
| `AemiKernels` SIMD (`indexOfAny5`, `indexOfControlOrAny5`, `indexOfNonASCII`, `firstInvalidUTF8`, `firstDisallowedText`, runtime-dispatched NEON/AVX2) | One validation pass at the boundary; one pass that finds ESC and other controls to neutralise; a jump to the next inline special character (there are about eleven; the kernel takes five, so the set scan above is owed) |
| `TapeSlot` (tag 4 bits, aux 28, offset 32; O(1) subtree skip) | The record format: a flat preorder tape with no node objects. Limits to design for: 16 tags (blocks and inlines need more kinds, so a second tape or an aux field), 28-bit aux, 4 GiB offsets |
| `ByteBufferPool` | Reused input and output buffers across deltas |
| `AemiUnicode` (case folding) | Link reference labels compare case-folded, as CommonMark requires |
| `PercentCoding` | Normalising link destinations |
| `InternedStrings` | Info strings (`swift`, `json`) and language names |
| `ASCII`, `SWAR`, `CheckedMath` | Classification tables, word-at-a-time scans, checked offsets |
| `AemiKernelsFuzz`, AemiJSON's fuzz target, `AemiTestKit` (`CAemiTestKitMalloc`) | The fuzz target and the allocation ceilings |
| `Benchmarks/CKernels` method (ADR-0011) | The benchmark method: interleaved, median and p10 to p90, a control that can fail |

ADR-0011 measured that Aemi's dispatcher lost about half its speed at 64 bytes; ADR-0014 removes most of that. Even so, a scan costs 3 to 6 ns before it
reads a byte, so the parser still scans a whole block per call where it can, and a per-line call is measured, not assumed.

## Links: what a terminal does with OSC 8 (probed 2026-10-25)

- **kitty** (installed, driven through its remote control: `kitten @ get-text --ansi`, a window printing three lines): it parses OSC 8, with
  the ST terminator and with BEL, and keeps the `id=` parameter. The plain-text read drops the sequences; the line printed without OSC 8
  has none in the ANSI read, so the probe could fail and did not. Hover and click are not observable this way: still owed.
- **pi** (this harness, `pi-tui` 1.4.0, read and run): a link is `ESC ] 8 ; ; URL ESC \ text ESC ] 8 ; ; ESC \`, the text only (the target
  is hidden), when its capability table says the terminal supports it; otherwise `text (url)`. The table is keyed on environment variables
  and, for tmux, on `client_features` containing `hyperlinks`. It re-opens a link on each wrapped row and closes it at the end of each row,
  so a link that wraps stays clickable on both rows. Three things to take: re-open and close per row; ask tmux rather than guess; and
  not to copy its two weaknesses (an environment-variable table, and a raw `href` written into the sequence).
- White paper §6 says capabilities are probed, not read from environment variables. OSC 8 has no query: silence is unknown, and a terminal
  that does not know it prints the text and ignores the rest. So the proposal is to **always emit it** (nothing is lost where it is
  unsupported), and to print `text (url)` only when the user turns `ui.links` to `"visible"` or when the target's host differs from a
  host written in the link's own text (the spoofing case), never by guessing the terminal.

## Decided and still owed

- **Copy: decided, the Markdown source.** What it costs: a drawn column no longer equals a source column once markers (`**`, `[](...)`) are
  hidden, and `Source` (TerminalKit ADR-0030) assumes it does. The renderer must carry, per row, a map from drawn columns to source offsets,
  and a selection must copy the source range it covers (a half-selected `**bold**` copies the whole marked span, or only the text; an ADR
  chooses before phase 3). `TranscriptContent` stays the item's own text, which is now exactly right.
- **Link safety.** A model answer is untrusted text, and so are its links. Candidate rules, all to be probed:
  - a scheme allowlist (`https`, `http`, `mailto`, and `file` only if the owner asks);
  - control characters and spaces refused in a target (an OSC 8 target containing ESC or BEL can end the sequence early and inject another);
  - the target shown when it differs from the text, so `[docs](https://evil)` cannot pass for a safe link;
  - ESC, CSI and OSC sequences in any answer text made inert before the parser sees them (`TextSanitizer` exists in TerminalKitText; its
    coverage is unprobed);
  - a click opens a link only through a user action, never on render.
- **Package boundary**: the table above is decided; the ADR that records it, and the Aemi pin change, come with phase 1.
- **Images** stay alt text plus link until the graphics work of 0051 lands.

## Budgets and safety rails

- The four budgets in `AskCore.Budget` hold: `Scripts/measure-budgets.py` and `Scripts/measure-action.py` run before and after, interleaved,
  median and spread. Markdown parsing is **off the main actor** and must not move input delay.
- Idle memory: the link table and style table are bounded and counted; the 500-turn run of `measure-action.py` shows no growth beyond a
  stated ceiling.
- The parser is a leaf with no I/O, so a fuzz crash is always a parser bug, and `unsafe` (if any) sits behind a safe interface with its
  invariant written and tested.

## Not in scope

Diagrams (0066), math, footnotes, front matter, HTML rendering, and a Markdown editor for the prompt (the composer's "highlighting, markdown" in diary
2026-10-19-23 is a separate unit).
