# Mermaid in AemiMarkdown's world: a terminal renderer, a SwiftUI renderer and a Quick Look extension (2026-11-04)

Asked by the owner: find the open-source packages that draw Markdown or Mermaid on macOS and iOS, with performance as the lens; then design, on
our standards (white paper, AemiMarkdown's ADRs), Mermaid support that works in ask (terminal), in SwiftUI, and in a Quick Look extension for
Markdown that also draws Mermaid, and that is as current as possible. **Nothing is built.** Probe history is in the diary entries of 2026-11-04 ("D1" below cites claims 1 to 15 of the first, "D2" those of the second). Statuses: *probed* (run, in the diary), *read* (source or documentation, not run), *unprobed* (an open question, named as one).
Files filed: roadmap 0196 to 0207; 0066 gets a pointer.

## 1. The short answer

- **No existing package meets our bar, and none is safe to link.** The six Mermaid renderers I ran all pass control bytes from a label to their output, none
  bounds its nesting, none fits a width, and four of six are worse than linear in node count (*probed*, D1 claims 1 and 2). The best native one,
  mermaid-swift (nessielabs), draws like Mermaid and stays near linear, but is weeks old, one star, written with Foundation strings and recursion we cannot audit
  against our rules (*read*).
- **Build our own engine, `AemiMermaid`, the way AemiMarkdown was built, and use the existing tools as baselines and oracles, not dependencies**: the decision
  0065 already made for the parser (swift-markdown stays the oracle). One headless engine (syntax, layout, a scene), three backends: cells (ask), CoreGraphics and
  SwiftUI, and the Quick Look extension. Text and pixels share the front half of layout and differ in metrics and routing.
- **Quick Look is a view-based extension over the same packages, with no web view and no JavaScript** (the API is unchanged since macOS 12, *probed* D1 claim 7),
  built the way MacFS is built (XcodeGen over SwiftPM; built with Xcode 27.2, **macOS 26 floor**). Diagrams are laid out in the background and replace their source when ready.

**Decided by the owner, 2026-11-04 (after the first version of this note):**
- The app lives in the AemiMarkdown or AemiMermaid repository for now, and may move into something bigger later. **Chosen: an app sub-package named MarkdownLook inside the AemiMarkdown repository**, with its own
  manifest like AemiMarkdown's benchmark sub-package, so the parser's manifest, ask's link weight and the family pins do not move (section 10).
- **No third-party package; the family and the platform's own are fine** (2026-11-04, second answer): packages from `g-cqd`, `Aemi-Studio`, `apple` and `swiftlang` may be used (so `aemi` and its kernel tapes, SIMD scans and hashing stay), anything else may not,
  in a library, in the app or in a test target. The existing renderers are oracles run from scripts, outside every manifest (the parser decision of 0065 stands: our own parser, swift-markdown as the oracle). XcodeGen is a generator on the developer's machine, as in MacFS.
- **Selection copies Markdown source**, in the viewers as in ask (the owner: "markdown"). Each run of the viewer's text names the source bytes it shows (ADR-0033), and copy writes those bytes.
- **macOS 26 is the floor** for the Quick Look app and its extensions (the same floor as ask).
- **The reading default is what Apple recommends**: the body text style, 13 pt on macOS, with looser leading for long passages (section 6).
- **The system font for Markdown and for Mermaid**, with monospace only where it matters, and real typographic care in type, spacing and white space (section 6).
- **Nesting is handled without recursion and in linear time**, and every phase states its bound (section 4).
- **Settled in the third and fourth answers:** prose leading 1.4 em; smart punctuation on in the viewers and off in the terminal; text-mode pie and Gantt are wanted but not first.
- **Editing at typing speed** (the owner: a user edits a Markdown file and sees the render at once, sub-10 ms, by block, in SwiftUI and in the terminal): section 7. Today's code already does it under 10 ms up to about 400 KB (*probed*, D1 claim 10); the design makes it independent of the document's size.
- **Vector through everything** (lossless scaling and zooming, raster avoided): section 8. Probed: text, paths, `Canvas`, scale transforms and SVG images stay vector; `.drawingGroup()` is treated as raster and banned.

## 2. What exists

### Mermaid renderers (stars and dates from `gh`, 2026-11-04; "ran" means D1)

| Package | Lang, licence | Draws | What I found |
|---|---|---|---|
| mermaid.js in a `WKWebView` (GMarkdown, Mermaid-iOS, flux-markdown, quickmd, MarkdownDisplayView's example) | JS, MIT | everything | 2.3 to 2.7 MB of JS per app (*probed*, sizes); a web process per view; flux-markdown is GPL-3.0 and needs the JIT entitlement for its web view (*read*, its entitlements file) |
| mermaid-swift (nessielabs) (1 star) | Swift 6, MIT, no dependency | all kinds, SVG, PNG, SwiftUI | ran: 106 ms for 200 nodes, 206 ms for 1000, errors with line and column, looks like Mermaid; 3000 nested subgraphs hang it; ESC reaches the SVG |
| MermaidKit (2389-research) (14) | Swift 6.2, MIT, no dependency | 30 kinds raster, SVG; text for flowcharts | ran: text of a 6-node flowchart in 0.93 ms; has the architecture we want (platform-free layout to a `RenderScene`, backends on top, a layout linter); 28k lines of layout; text mode flowchart only; a cold release build took 413 s |
| beautiful-mermaid-swift (lukilabs) (365) | Swift, MIT, ELK port (EPL-2.0, 56k lines) | 6 kinds; text, SVG, image | ran: 200 nodes in 11 to 17 s, hangs on deep input; a mechanical port of the TypeScript original (files are named `src_*.swift`) |
| mermaid-rs-renderer (1jehuang) (1802) | Rust, MIT | all kinds, SVG, PNG | ran: 11 to 18 ms per process for small diagrams, over 60 s for 200 nodes; its README claims 4.5 ms and 400 times mermaid-cli on other hardware, not reproduced |
| mmdflux (kevinswiber) (76) | Rust, MIT | text, SVG, JSON (MMDS) | ran: the best text layout I saw (network simplex, orthogonal routing on a grid, subgraphs, class and state), 336 ms for 200 nodes, 2.9 s for 1000; MMDS is a layout interchange format worth reading |
| mermaid-ascii (AlexanderGrooff) (1621) | Go, MIT | flowchart, sequence as text | ran: 5.8 s for 200 nodes; the reference for how text diagrams look |
| merman (Latias94) (653), `sebastien…/sebastian`, `frankenmermaid`, `termaid` (Python, 570), `mmaid-go`, `graphs-tui` | various | Mermaid.js ports and terminal renderers | read the descriptions only; not run |
| md-quicklook (armamut) (10) | Rust + Swift, MIT | Markdown and Mermaid in Quick Look | the closest to our goal: Rust core to a binary layout, TextKit drawing, mermaid-rs-renderer and resvg for diagrams in the background, "about 30 ms" for a README by its own figure (*read*, not reproduced) |

Not found anywhere: a Mermaid text renderer for pie, Gantt or journey (D1 claim 3); a renderer that takes a width and fits it; one with a documented bound on
every loop. These are our openings.

### Markdown viewers for Apple platforms (read: architecture from sources and READMEs; none measured by me)

| Package | Parser | Draws with | Streaming | Note |
|---|---|---|---|---|
| textual (gonzalezreal) (916), successor of swift-markdown-ui (3936, maintenance mode) | Foundation `AttributedString(markdown:)` | SwiftUI `Text` per block, own selection | full reparse | keeps SwiftUI's text pipeline; no Mermaid |
| MarkdownView (LiYanan2004) (844) | swift-markdown | SwiftUI views, a web view for part | no | |
| SwiftStreamingMarkdown (microsoft) (390) | swift-markdown | SwiftUI, `LazyVStack`, TextKit pieces | built for streaming; profiled on an iPhone XS, no numbers | |
| wuhu-markdown-ui (wuhu-labs) (1) | swift-markdown | a flat block IR into an `NSCollectionView` or `UICollectionView`, Core Text per block | yes | the same shape as our tapes and our per-block cache |
| swift-markdown-engine (nodes-app) (1255) | own | AppKit, TextKit 2, an editor | | the TextKit 2 route |
| swift-markdownkit (objecthub) (213) | own | AppKit text, PDF, web view for Mermaid | | |
| AemiMarkdown + TerminalKitMarkdown (ours) | own, 200 to 278 MB/s | cells | O(delta), stable block ids | measured in its README against swift-markdown (14.8 MB/s) |

Reading: the parsers behind the SwiftUI viewers are swift-markdown or Foundation's, which AemiMarkdown beats by an order of magnitude and which reparse
everything per delta; the only viewer whose architecture matches ours (flat IR, one cached unit per block) is wuhu-markdown-ui. Whether SwiftUI `Text` per
block or Core Text per block or one TextKit 2 view is fastest here is **unprobed**: it is the first probe of 0199.

### Quick Look extensions for Markdown (read)

QLMarkdown (sbarex) (3729, GPL-3.0: cmark-gfm to HTML in WebKit), flux-markdown (xykong) (1300, GPL-3.0 plus a commercial licence: markdown-it, Mermaid.js and KaTeX in a
web view, bundled), md-quicklook (armamut) above, QLMarkdown (relikd) (MIT), `jzone3`, `MDLook`, quickmd (b451c), and **Obsidian's own extension**, the only one installed
here (*probed*: it declares `net.daringfireball.markdown`, `public.markdown` and `net.ia.markdown`). GPL code cannot be copied into an MIT family; read, never lifted.

## 3. Rules that bind the design

From the white paper and the AemiMarkdown and TerminalKit ADRs: a lightweight runtime (link only what is used); fewest allocations (zero per node, buffers
reused, an allocation ceiling in every suite); close to zero copy (copy once at the edge); safe (no `-Ounchecked`, `unsafe` justified, **no recursion, every loop bounded, any
bytes give a document**); `Mutex` and `Atomic`, not locks or queues; deterministic tests (no sleeps); every performance-affecting change benchmarked, median and
spread, release; generic tools in Aemi; system APIs before subprocesses; one top-level type per file, 250 lines; the evidence rule. Two consequences for this work:
layout must be a **pure function** (so its result is cached by content and width, and tested at every width), and any number below is a **hypothesis until phase 0 measures it**.

## 4. Architecture

```
bytes ──AemiMermaidSyntax──▶ diagram tapes ──AemiMermaidLayout(metrics, width)──▶ DiagramScene ──▶ AemiMermaidText     ──▶ rows of cells (ask)
 (UTF-8)   sanitise, limits     per kind        pure, deterministic     (display list,    ├▶ AemiMermaidGraphics ──▶ CGContext, PDF (Apple)
                                                                         roles not RGB)    └▶ AemiMermaidUI       ──▶ SwiftUI view (Apple)
```

- **A new repository, `AemiMermaid`, beside AemiJSON and AemiMarkdown** (a second consumer is plausible, in fact three exist). Targets, fine-grained and none re-exporting another:
  `AemiMermaidSyntax`, `AemiMermaidLayout`, `AemiMermaidScene`, `AemiMermaidText`, `AemiMermaidGraphics`, `AemiMermaidUI`, and a dev-only CLI, `aemi-mermaid`, that prints a
  scene, its cells or an SVG (for goldens and probes). The first four compile on Linux; the last two are Apple-only (consistent with the Linux and Windows wish).
  Same manifest discipline as AemiMarkdown: Swift 6 mode, strict memory safety on the parser and layout, warnings as errors, one Aemi pin.
- **AemiMarkdown does not learn Mermaid.** ADR-0001 decision 1 (it owns no rendering) stands. It already reports a fence's info string and code lines (`codeBlock`, `infoString`,
  `codeLine`, *read*), and three consumers would each collect them (TerminalKitMarkdown's `CodeBlock` does today). So one small addition, **a zero-copy fence reader**
  (`MarkdownFence`: language range, line ranges, fenced or indented) (0202). Anything else Mermaid is outside the parser.
- **Syntax.** Same method as the Markdown parser: UTF-8 in, tapes out, offsets not copies, a `Limits` value (source bytes, nodes, edges, label bytes, subgraph depth, messages
  per sequence), `Diagnostics` that name the limit or the line and column, never a throw, never a crash. A diagram is parsed **once, when its fence closes** (0066: source while
  streaming), so no incremental parser: not doing the work comes first. Labels are sanitised here: control scalars, bidi overrides and unpaired surrogates never enter the
  tape, and the text backend filters again at the cell (two layers, because D1 claim 1 failed everywhere). Kinds in this order, which follows the weak GitHub signal and
  how much of the engine each reuses: flowchart (graph), sequence, state, class, ER; then pie, Gantt, mindmap, journey, timeline, git graph; others only on demand.
  Mermaid's own grammar is the spec; its test suite and `mermaid.js` are oracles to run, never a dependency (*unprobed*: how much of its syntax a model actually writes).
- **Metrics, the one idea that lets one engine serve text and pixels.** A `Metrics` value says what a unit is and how text is measured. *Cell metrics*: a unit is a cell, widths come from the
  host's width function (ask passes TerminalKit's `UnicodeWidth`, so there is no dependency on it), node padding is 1, edges route on integer channels. *Continuous metrics*: units are
  fixed-point (a sixty-fourth of a point, an integer type), text widths come from an injected measurer: CoreText with the system font in the Apple backends (section 6), a fixed table elsewhere.
  **Integer arithmetic throughout**, so for a given measurer the layout is identical on every platform. Exact goldens therefore use the table measurer, as MermaidKit's linter does with a fake one
  (*read*); with the real system font the tests are properties (no overlap, every label inside its shape), because the font's metrics depend on the OS and on the point size (D1 claim 8).
- **Layout, with the bound of every phase.** Nothing recurses; nesting is parent-index arrays and explicit stacks, walked in preorder and, bottom-up, in reverse preorder. The target is **linear,
  O(K·(n + e + v))** with K a small constant and v the virtual nodes, and every phase that is not plainly linear says why it is bounded:

  | Phase (flowchart, state, class, ER) | Method | Bound |
  |---|---|---|
  | parse | one pass over lines; subgraph and fragment nesting on an explicit stack with a depth limit | O(bytes) |
  | subgraph tree | parent indices; sizes bottom-up by reverse preorder | O(n) |
  | cycle removal | greedy feedback-arc heuristic (Eades, Lin and Smyth: degree buckets), not DFS search | O(n + e) |
  | ranking | longest path, then at most K tightening sweeps; **network simplex only if a probe shows it earns its cost**, because its iteration count is not linear (mmdflux offers both and defaults to it, *probed* `--help`) | O(K·(n + e)) |
  | virtual nodes for long edges | one per rank an edge crosses; **the sum of spans is a limit** (the classic Sugiyama trap: a star or a long chain with back edges makes v grow like n times e); over it, the diagram is refused with the figure | v ≤ limit |
  | ordering | K sweeps of weighted median and a transpose pass, fixed count, no convergence test (deterministic) | O(K·(e + v)) |
  | coordinates | Brandes and Köpf; for cells, compaction to integer columns | O(n + v) |
  | routing | orthogonal, in the channel between two ranks, lanes by interval colouring after a counting sort of endpoints; **no per-edge path search** | O(e + v), plus a sort per channel |
  | sequence | columns from label widths, one row per message, fragments on an explicit stack | O(participants + messages) |
  | Gantt, journey, timeline | dependencies resolved with Kahn's algorithm | O(tasks + dependencies) |
  | emit | scene to cells or paths; the grid is capped at width times a row limit | O(scene) |

  The tools that went superlinear in D1 are the ones with a per-edge search or an unbounded dummy-node count (*inferred*, not profiled); the limits above are what a probe in 0197 must confirm or correct.
  Subgraphs are a compound graph, laid out as boxes by the same passes. Pie and Gantt in text become bars (nobody draws them there).
- **Fuel, not clocks.** Every phase counts its inner-loop steps against a **deterministic budget** (`MermaidLimits.fuel`, a count of steps). Running out stops the phase, reports it in the diagnostics and
  yields "source with a reason"; the same input runs out at the same step on every machine, so a test can pin it and **no test asserts a wall-clock time** (white paper). A wall-clock guard exists only in
  the host (ask), as a second line, with cooperative cancellation checked at phase boundaries. Memory is bounded the same way: arenas are sized from the limits (a stated worst case in bytes, asserted by a test), reused, never grown unbounded.
- **Never fails, never half-draws.** Every phase returns its result or a diagnostic; there is no throwing path and no partial scene, so a failure anywhere is the source fallback, not a broken picture. Hostile and degenerate inputs are permanent tests with step ceilings:
  the D1 corpus (3000 nested subgraphs, 2 MB label, 20000 brackets), a star, a long chain with back edges, complete bipartite graphs over the edge limit, and a fuzz target on the syntax (Aemi has a fuzz harness for its kernels, `AemiKernelsFuzz`, *read*).
- **Fitting a width, for text** (0066 phase 2, made precise): the layout takes the available columns and applies, in order, flip the direction (left-right to top-down when too wide), wrap labels
  at balanced points, drop optional padding, then give up with a reason and show source. The flip is decided from the rank widths before routing, and at most three layouts run per width, a constant factor. A test lays each fixture out at every width from 1 to 200: no row wider than the width, every label present, no
  dependence on earlier widths. Nothing in the prior art does this (D1 claim 2).
- **Scene.** A flat display list, structure of arrays in `ContiguousArray`s that the engine reuses: shapes (kind, rectangle), paths (points, end markers, dash), text runs (anchor, label range), groups, in draw order.
  **Roles, not colours** (node, edge, label, cluster, note, and a small numbered accent set): the backend maps roles to its palette, so a change of theme, or of light and dark in Quick Look and
  in ask's follow-the-system colour work, redraws without a new layout. The layout cache key is (content hash by XXH64, metrics, width), never a colour.
- **Budgets, proposed, to be set by phase 0 and then enforced by tests**: parse and layout of a 30-node flowchart at p50 within 1 ms in process (MermaidKit's text mode does 0.93 ms for 6 nodes with Foundation strings,
  D1); 200 nodes within 25 ms (nessielabs: 106 ms for the whole process, SVG included); zero allocations per diagram once the engine is warm, counted with `CAemiTestKitMalloc`; limits chosen where the step count
  reaches the budget, confirmed by p99 time, not by guess. A growth test fits cost against n at 100, 200, 400, 800 and 1600 nodes and fails when the ratio of successive costs leaves linear by a stated margin.
  Layout is always off the main actor, so ask's input-delay budget is untouched.

## 5. Terminal (ask)

- **TerminalKitMarkdown gets one more host-implemented protocol**, `MarkdownFenceRenderer`, next to `MarkdownCodeHighlighter` (ADR-0033: the kit links no lexer; it will link no diagram engine). Given a fence's language,
  its source and the width, it returns drawn rows or nil. `BlockWriter.emitCode` asks it before drawing code; nil is today's code block, so every failure path is the existing one.
- **Rows must stay a pure function of the block**, but layout is slow enough to be asynchronous. So the protocol is a **cache lookup**: the host (ask) answers from a cache keyed by (block id, width, theme, mode)
  and on a miss answers nil, starts the layout off the main actor, and invalidates the block when it finishes. The kit's property tests keep holding because the function it calls is still pure for a given cache state.
- **The adapter lives in ask**, a few files in `AskTUI`: scene to `AemiMermaidText` cells, roles to TerminalKit `Style` through ask's theme (which is also where the follow-the-system colour wish lands), widths from `UnicodeWidth`.
  AemiMermaid never imports TerminalKit.
- **Toggle, copy, fold** as 0066 already specifies: a header row is a click target (TerminalKit ADR-0027 and 0031: a fold leaves a placeholder and never moves the reader), the state is per block and not in the session
  file, a selection copies the Mermaid source whichever side shows. How a drawn row names its source (TerminalKit ADR-0030) for a drawing is open: the first row names the whole fence range, the others name nothing (chrome).
- **No graphics tier.** 0066 kept Kitty graphics as a later option (B and C); the owner now prefers no raster where it can be avoided (section 8), and a terminal image is a bitmap by protocol. Cells re-lay out at every width, which is the lossless zoom of a terminal. So 0066's options B and C are dropped, and TerminalKit's graphics probe (ADR-0028, 520 ms against a silent terminal) is not needed for diagrams.

## 6. Typography and space

The rule: **the system font, at its real size, with every distance derived from the font and counted in em or in lines, and monospace only where the content is code or must align.** What the system font does is
*probed* (D1 claim 8); the typesetting practice below is conventional and **unprobed**: phase 0 of 0199 renders sample documents at 1x and 2x, light and dark, and the owner judges by eye before any value is fixed.

**Fonts.** Only system APIs: `NSFont` and `UIFont` (`systemFont`, `monospacedSystemFont`, `monospacedDigitSystemFont`), `Font.system` in SwiftUI, `CTFontCreateUIFontForLanguage` for measuring. No named font, no bundled font file
(no bytes, no licence, no package). Text is **drawn at its final point size** (a transform would keep the 11 pt shapes), **never given manual tracking** (the system font already tightens by 11% from 11 to 48 pt, which is the
"negative spacing" of display sizes), **keeps kerning on** (7% on a test string), and is **measured at its real weight** (bold is up to 10% wider, so a heading wraps at semibold, not at regular). A serif reading style
(New York, same API with a design) is a setting, off by default. iOS follows Dynamic Type through `preferredFont`; macOS has no system size, so the viewer has one reading-size setting.

**Reading default: what Apple recommends (probed, D1 claim 9).** The HIG says to follow the recommended default and minimum sizes of each platform and to use the built-in text styles, loosening the leading for "wide columns or long passages"; macOS has no Dynamic Type. AppKit's own values: default
`systemFontSize` **13 pt** (the body style; its TextKit line is 16 pt, 1.23 em), `smallSystemFontSize` 11, `labelFontSize` 10 (the smallest built-in style). So the default is **13 pt body, drawn from `preferredFont(forTextStyle: .body)`**, and a reading-size setting steps it (13, 15, 17) for people who want more; iOS takes the size from Dynamic Type at run time. (The HIG's size tables did not survive the documentation mirror, so the minimum of 10 pt is the smallest built-in style, probed, not a quoted table.)

**Scale and measure.** Headings take Apple's own text styles (26, 22, 17, 15 over a 13 pt body: 2.0, 1.69,
1.31, 1.15, which at the default size are exactly the large title, title1, title2 and title3 sizes) for h1 to h4, semibold; h5 and h6 are body size, semibold, h6 in the secondary colour. **Line height** is set by the viewer, because the font's own is 1.178 em with no leading (too tight for prose): Apple's body line is 1.23 em and its guidance for long passages is looser, so the **decided value is 1.4 em for prose** (18 pt at 13; the owner, 2026-11-04); headings 1.2, code 1.35, table cells 1.3. **Measure**: 66 to 75 characters, which at the measured 0.448 em per character is 30 to 34 em, default 32 em (416 pt at the 13 pt default, 480 at 15), centred; a wider window adds margin, never line length. Code
blocks and tables may use the container's width (code never wraps, it scrolls; tables follow ADR-0033's fit rule), diagrams too, since a figure is not prose.

**Vertical rhythm and white space.** One unit, **u = half the body line height**; every space between blocks is a multiple of it, so baselines of text in different blocks fall on one grid. Adjacent margins collapse to the larger
(computed in the same linear pass as layout), and the first block of a document or container has no space above.
- Paragraph to paragraph 0.6 line (no first-line indent, no full blank line). A heading has more space **above** than below, at least twice: h1 2 lines above, h2 1.5, h3 to h6 1.25, and 0.5 below, so it belongs to what it introduces (proximity).
- Lists: tight lists (AemiMarkdown reports `ListFlags.tight`, *read*) 0.2 line between items, loose lists 0.6; markers **hang** in the margin (marker column as wide as the widest marker, numerals in tabular figures, text flush after it), 1.5 em indent per level.
- Block quote: a 2 pt rule and a 1 em indent, text stays in the primary colour and upright (no wall of italics). Thematic break: a hairline with 1 line either side. Code block: 0.75 em vertical and 1 em horizontal padding, a role tint without a border, radius 0.4 em,
  0.5 line outside. Tables: cell padding 0.5 em by 0.35 em, header semibold, **horizontal hairlines only** (less ink), columns aligned as GFM says, numbers right-aligned in tabular figures.
- A diagram has one line of white space above and below and no frame; the page keeps at least 2 em of side margin in a narrow window. Hairlines are 1 device pixel, snapped to the pixel grid at 1x and 2x.

**Text details.** Left-aligned, ragged right, never justified. Headings and diagram labels are wrapped **balanced** by our own linear-time balancer (a binary search on the width, O(words·log width), bounded) with no one-word last line; prose line breaking is
TextKit's (`lineBreakStrategy`, hyphenation: *unprobed* on long headings). Links are colour **and** underline, never colour alone. Italic is the system's; where a script has none, weight or underline stands in, never a synthetic slant.
**Smart punctuation** (curly quotes, en and em dashes, ellipsis) is a display substitution inside prose runs only, never in code, links or URLs, and each substitution stays inside its source range so selection and copy map exactly as ADR-0033 says; on in the viewers (the owner agreed, 2026-11-04), off in the terminal.

**Monospace, where it matters.**
- *Markdown*: inline code, code blocks (fenced and indented) and their info label, HTML blocks, math source until a typesetter exists, front matter. A path or a URL is text unless the author backticked it: nothing is guessed. **Size 1.0 times the body**, not the folk 85 to 90%: the system monospaced font has the same x-height (probed), no ligatures (probed) and a 0.618 em advance.
- *Mermaid*: class diagram members and method signatures, ER attribute columns (type, name, key aligned), git graph commit ids and tags, and any label the author wrote in backticks or a Mermaid markdown string. Everything else, node and edge labels, participants, messages, is proportional. Dates, percentages and axis numbers (Gantt, pie, charts) use **tabular figures**, not monospace.
- *Terminal*: the font is the terminal's, and typography is cells (below).

**Mermaid in pixels, in em of the same base font.** Node padding 1 em by 0.6 em, node gap 1.5 em, rank gap 2.25 em, cluster padding 1 em with its title in semibold at 0.85 (the subheadline to body ratio, probed), stroke 1 pt, arrowhead 0.6 em, edge labels at 0.85 with a 0.25 em
background knock-out, node text at 1.0. **A legibility floor of 10 pt** (Apple's smallest text style; edge labels at 0.85 of 13 pt are 11): a diagram wider than its container first re-lays out with tighter gaps, then keeps its size and scrolls or zooms, and is never shrunk into small print.
Colours are **roles resolved to system semantic colours** (label, secondary label, separator, the accent and the system hues) so dark mode and Increase Contrast follow; a node's fill is a low-alpha tint of its accent over the page, which works in both appearances; strokes keep at least 3:1 against
the page and text at least 4.5:1 (WCAG AA); no meaning rests on colour alone (dashed against solid, shapes).

**Terminal: spacing in cells.** One blank row between blocks (as TerminalKit does), a diagram with one above and below. Cells are about twice as tall as wide, so a box has 1 to 2 columns of padding and none vertically (three rows: border, text, border). Single light box-drawing, rounded corners for
rounded shapes, heavy lines for emphasis, arrowheads from characters `UnicodeWidth` agrees on (ambiguous widths are TerminalKit roadmap 0013) with an ASCII mode. An optional cap on the width of prose (a `measure`, say 100 columns) is a TerminalKit idea, not designed here.

**One set of tokens.** The values above are one `Typography` value (em-based tokens and role names) in the viewer kit, from which the Mermaid graphics backend builds its smaller `DiagramStyle`; a diagram in a document is set in the same type as the text around it. No package is shared for it.

**How it is checked.** Rendered samples reviewed by eye (the way I looked at nessielabs' output in D1). Property tests: block tops fall on the grid; heading space above is at least twice the space below; no line exceeds 34 em outside code, tables and figures; no text under 10 pt;
contrast ratios of every role pair, resolved in both appearances, meet the thresholds; a heading's wrap is computed at its own weight. Layout is a pure function of (document, base size, width, appearance-independent), so appearance changes redraw without a new layout.

## 7. Editing at typing speed

**The requirement, and how I read it.** A person types in a Markdown file and the render changes at the same time, in under 10 ms, by block, in SwiftUI and in the terminal. A screen adds up to one refresh after our work (8.3 ms at 120 Hz, 16.7 at 60), which we do not control, so the number we can own is
**the work from the edit to the frame handed to the display: at most 4 ms at p99** (ask's input-delay budget is also 4 ms), measured with signposts. If "sub-10 ms" meant glass to glass, say so: it cannot be promised from inside the process.

**What exists, measured (D1 claims 10 to 12).** Reparsing the whole document and laying out only the changed block reaches rows in 0.35 ms at 23 KB, 1.4 ms at 103 KB, **16 ms at 1 MB**, 64 to 78 ms at 5 MB; parse runs at about 100 MB/s on documents. Laying out one block is 0.02 ms in the terminal and 0.16 ms (p99 0.37)
in CoreText; laying out every block is 400 times that. A single TextKit 2 view costs 1.7 ms at 51 K characters and 5.4 ms (p99 39) at 2.5 M for one changed paragraph. So: **cache by block, never by document**, and make an edit cost O(the edit) once documents pass a few hundred kilobytes.

**1. A block is cached by what it is, not by where it is (content-addressed).** Today a block's identity is its index on the tape (ADR-0002), which is right while text only grows, and wrong when a block appears above: every id after it shifts and an id-keyed cache loses everything
(edit B in D1 inserts a paragraph at the top: every later block gets a new id). The parser records, as each top-level block closes, its **source range** (the thing ADR-0002 deferred until a consumer asked: the viewer's copy, the editor's scroll sync and this diff are three) and a **content hash**:
XXH64 of its bytes mixed with everything else its drawing depends on, namely what its reference links resolved to (a hash of each destination, and a marker for an unresolved label) and, for footnotes, nothing positional (the number is the renderer's, from a count in reading order, and part of its cache key). Cache key of rows or of a laid-out frame: (content hash, width or measure,
typography key, theme key). Identical blocks share one entry, a moved block hits, and **no identity bookkeeping exists**. Streaming keeps working: the open block's hash changes with each delta and every closed block's does not.

**2. The edit API, in AemiMarkdown (a new ADR, 0003).** `replace(_ range: Range<Int>, with: [UInt8])` on the parser returns a `MarkdownChange`: the first block that differs, how many old blocks were replaced by how many new ones, and the unchanged suffix, found by comparing hashes from both ends (O(blocks), a pass over two arrays of integers, *estimated* at microseconds per thousand blocks, to be measured in 0203). Two phases, the second only if the first is not enough:
- *Phase A, reparse and reconcile* (simple, correct by construction, the oracle for B): parse again from the changed block's restart point to the end of the document and reconcile by hash. It is what D1 measured, with the hash taken inside the parser rather than by a consumer walking every block (half the parse again), so about 1 ms at 100 KB. **Enough up to roughly 400 KB**, which is every document people write.
- *Phase B, restart and resync:* restart the block parser at the start of the top-level block that holds the edit (or the one before it, when a lazy continuation, a setext underline or a list can reach back), with the container stack empty, and parse forward **until the parser reaches a top-level block start that coincides, shifted by the edit's length, with an old block start, with nothing open**: from there the rest of the old tapes are exactly right. Then splice the new slots into the tapes
  (a move of the tail, 320 KB for a megabyte, tens of microseconds, *estimated*) and add the length difference to the offsets after it (a loop over integers). Cost O(edit region + the distance to resync + the tail move): one or two blocks, independent of the document, except where the edit really does change everything below it: an opened code fence, or an unclosed HTML block, resyncs at the closing fence or never, O(the tail), which is the same bound as a full parse and no worse.
- *Dependencies across blocks:* reference definitions and footnotes are global. The parser keeps, per label, the blocks that used it (resolved or not); changing a definition re-runs the inline phase of those blocks only, O(uses), and their hashes change, so their cache entries are replaced and nobody else's. (ADR-0001 decision 4: a streamed document applies a definition only to blocks that close after it; an edit applies it to every use, as a whole parse does. Phase B is tested against the whole parse, not against streaming.)
- *The test that makes B safe:* for every CommonMark and GFM example (682) and for the corpus of D1, every single-byte insertion, deletion and replacement at every position, plus random multi-byte edits, the incrementally edited document equals a fresh parse (tapes and hashes). A bound test counts the work of an edit against the size of the edit. Allocation ceiling per edit once warm.
- *Limits and failure:* the limits of `MarkdownLimits` apply unchanged; an edit never fails; any edit the incremental path cannot place falls back to phase A, which falls back to nothing because it is a full parse.

**3. The renderers take the change, not the document.**
- *Terminal:* TerminalKitMarkdown already draws per block (ADR-0033). Rows are cached by (content hash, width, theme), the host's row windows (TerminalKit roadmap 0023) take the replaced range, and the screen flush is already proportional to the change (ADR-0008). Measured: 0.02 to 0.2 ms to render the changed block. ask's input editor (0085) uses the same API on a few kilobytes, where a full parse is microseconds.
- *Pixels:* the layout of a block is a CoreText frame, 0.16 ms, cached by the same key, bounded by bytes (least recently used out). Block heights live in a **prefix-sum tree** (Fenwick), so the offset of a block and the block at an offset are O(log n) and a height change is O(log n); unmeasured blocks use an estimate per kind and the **scroll anchor** (the first visible block and its offset in it) is
  kept across a change above the viewport, so text never jumps under the reader (the rule of TerminalKit ADR-0031). Only blocks that meet the visible rectangle are drawn. This is host (c) of section 9; whether it beats (a) and (b) is the probe of 0199, with edit latency, not only first screen, as the number.
- *Coalescing:* an edit is an event, the screen draws the newest state (TerminalKit ADR-0026): a burst of keystrokes yields one frame each at most, and the parse of a large document runs off the main actor with the newest edit winning. Up to a quarter of a megabyte the parse runs inline: it costs less than the hop.
- *Mermaid in the loop:* an unchanged fence is the same content hash, so typing elsewhere never lays a diagram out again. An edited fence keeps its last drawing until the new layout is ready (never a flash of source), and a layout past its fuel leaves the source with the reason. Diagram layout is O(n) per edit, not incremental; 30 nodes cost well under a millisecond by the budget of section 4.
- *Source and preview together (the app):* the source pane is a plain-text editor, coloured from the inline tape; a caret offset finds its block by binary search on source ranges and scrolls the preview to it, a click in the preview finds its offset from the run's source range (ADR-0033). The file is also watched and reloaded when another program saves it, with a system file-watch API, not a subprocess.

**Targets, proposed, set for real by 0203 and 0199:** an edit at 23 KB, 103 KB, 1 MB and 5 MB reaches rows within 4 ms p99 in release, in the terminal and in the pixel host; phase A is accepted up to the size where it stops meeting that, phase B beyond it, and the numbers go in the diary with median and spread on a quiet machine.

**Instant, not just fast (the owner's third answer: an edit or a stream should land the render instantaneously, the earlier the better).** The 4 ms above is a ceiling that fails a build, not the aim; the aim is the earliest frame, and the work is done when the profile is flat (the stop rule of the optimization program), not when a number is met. Measured (D1 claim 15): a 40-byte delta of ordinary text lands in 35 µs in the terminal path; a full redraw of the pixel viewport costs 6.4 ms in software CoreGraphics, a repaint of one changed block 0.18 ms.
The pipeline principles that follow, each an experiment in the plan's latency catalogue: handle the event the moment it arrives, with no timer, debounce or hop on the path; for small documents do parse, reconcile, layout of the changed block and drawing in the same run-loop turn; **repaint only the dirty rectangle of the changed block** (a redraw of everything pays the 6.4 ms), which is a reason for a drawing view with dirty rectangles over a canvas that redraws whole; warm the fonts, attribute dictionaries and framesetters so the first keystroke is not the slow one;
**lay out again only what the edit can change, wherever it is** (below); **start the walk of blocks at the first non-final block** (it costs O(blocks) per delta today, 84 µs at 3.6 thousand), which the block index of 0203 gives with random access by ordinal; in the terminal, write the frame the moment the delta is handled. Measured from the input event's own timestamp (or the moment a socket read returns, for a stream) to the end of drawing, with signposts; what the display does after is not claimed.

**An edit is anywhere, not only at the end (the owner's reminder).** A stream appends; a person edits at the start, in the middle, inside a table or a fence, splits and joins paragraphs, pastes ten kilobytes, cuts a block, and an external editor saves a change in two places. Everything in this section holds for any position, and four things were made explicit because the end of the text is the easy case:
- *What moves.* An edit at the start moves every offset in the document; the cost of that is small and measured (D2 claim 16, the second diary entry: about 0.18 ms per megabyte at the start, nothing at the end, with the per-slot shift driven by a class table, five times faster than a `switch`), and a cache keyed by content hash is not affected by position at all. Heights go through a prefix-sum tree whose update is O(log n) at any index. A selection or a caret anchored to a block ordinal is carried through the change set (the ordinals after an edit shift by the blocks inserted minus removed; a block that was replaced snaps its anchor to the nearest new block).
- *Layout is local to the edit, with a resync like the parser's.* Inside a block, lines before the edit's line (one earlier when text is removed, because a word may move up) are kept; the block is typeset again from there, line by line, **until a line break falls where an old one did, shifted by the edit's length, and the styles after it are unchanged**; the rest of the old lines are kept and only their position moves. Typing in a paragraph costs about the lines that reflow, usually one to three. A stream at the end is the case where nothing follows. An edit that changes an inline delimiter (a `*` typed) restyles up to the matching delimiter, found by comparing the new inline tape with the old.
- *Long paragraphs need windows.* CoreText's line breaking costs O(the paragraph) per call and so a paragraph is quadratic to lay out: 1.6 ms at 3,000 characters, 71 ms at 10,000, 0.58 s at 30,000, 6.6 s at 100,000 (D2 claim 17), where a bounded window costs a fraction. So paragraphs are typeset in windows of a few hundred to a thousand characters, which also makes a local relayout possible; a paragraph over a stated length stays a window-by-window layout with its own fuel, never one call. This is a correctness matter for the viewers and the Quick Look preview, not only an optimisation: a one-line 30 KB file would otherwise hang a preview.
- *Streams and edits interleave.* The lab lets a person edit while ask streams. A stream's insertion point is a **mark that follows edits** (it moves when text before it changes), so deltas land at the stream's own end wherever the text has moved; a stream's `replace` frame is relative to the stream's own bytes and, if the person edited inside the stream's region, the lab reports the stream as diverged and keeps both.
- *External changes* come as a diff of old and new bytes split into hunks (Aemi has a diff), applied from the last hunk to the first so earlier offsets stay valid, each a `replace`.
The measurements, tests and benchmarks carry a **position series** (start, first block, quarter, middle, three quarters, last block, end, a block boundary, inside a fence, a table and a list; and the operations insert, delete, replace, split, join, paste ten kilobytes, cut a block), so a cost that depends on position shows up as a slope and not as one number.

**The lab (the owner's second answer).** A debug utility with two panes: the source, editable, and the render, updated on the fly, side by side so that what is typed or streamed and what is drawn can be compared. **ask streams its content through it**: a debug tap in ask sends the assistant text deltas it already receives to the lab over a local socket; the lab appends them to the source pane and renders them live, and a person can edit the same text while it streams, which exercises the stream and edit paths together. The lab shows, per event, the time from arrival to parse, to layout, to drawing, with a histogram; it checks the incremental result against a fresh parse after every event and says where they differ (the live form of the differential test, at any position); it records and replays streams and edit traces with their original timing, which gives deterministic latency tests and a corpus of real streams;
and it hosts the three viewer hosts of 0199 so the host probe runs in a real window with real input. It is a development tool, built beside the app, never shipped. Filed as roadmap 0207. ask's side is off by default and costs one flag check when off; it never blocks and never changes what ask draws (section 14).

## 8. Vector all the way

The rule: **nothing we draw is rasterised by us.** Text is CoreText or SwiftUI `Text`, shapes are paths, diagrams are the scene drawn as paths and glyph runs, and the drawing is redone at the scale it is shown at.
- **Evidence (D1 claim 12).** CoreText, `CGPath`, SwiftUI `Text`, `Canvas` (with and without `rendersAsynchronously`), a scale transform and a local SVG in `NSImage` all reached a PDF with zero image objects, and the detector fires on a bitmap, so the test can fail. `.drawingGroup()` was inconclusive in that probe; Apple documents it as an offscreen image, so it is banned,
  and so are the other offscreen paths in SwiftUI (`.blur`, `.shadow`, `.compositingGroup`, materials as content): by a source test in the viewer and graphics targets, as `SourceStandards` bans locks, each rule checked by breaking it once. Hairlines and tints are drawn, not blurred.
- **Zoom is a transform of laid-out content, and it is lossless**: magnifying scales the geometry and the glyphs together (the view's scale on an `NSScrollView`, or a scale transform in SwiftUI), so every level is crisp and nothing reflows. **The reading-size setting is a different thing**: it re-lays the text out at the new point size (13, 15, 17 and so on), because only then are the system font's optical size, tracking and wrapping right (D1 claim 8).
  Both are persisted separately. A diagram under a zoom is the scene redrawn at the scale; culling by the scene's bounds keeps a 1000-node diagram at the cost of what is visible.
- **Where a raster is unavoidable, and nowhere else:** bitmap images inside a document (PNG, JPEG: local only, drawn with high-quality interpolation; an SVG stays vector), colour emoji (bitmap glyphs in the system font), Finder thumbnails (a thumbnail reply is an image by contract; the content is drawn into its context at its own size), and the compositor that puts pixels on the screen.
- **Quick Look.** The view-based extension draws live and so is vector at any panel size. The data-based route (`QLPreviewReply` drawn with `isBitmap: false`, or a `PDFDocument`) is vector too and is the fallback to probe; it fixes the width. A bitmap context is never used for a preview.
- **Export and print** come from the same drawing: a PDF context instead of the screen's.
- **Terminal.** No raster tier (section 5). A diagram re-lays out at each width, which is the terminal's lossless resizing; the terminal's own font size is the terminal's.

## 9. SwiftUI

- **The viewer kit, `MarkdownLookKit`**, a library in the app's sub-package (section 10) that consumes AemiMarkdown's blocks, and can be extracted into a package of its own later. Unit of work and cache: the top-level block, keyed by its stable id, as in TerminalKit (ADR-0033). Per block it makes one attributed string (the one copy at the
  edge) and chrome descriptors (quote bar, list marker, code gutter, table). Only the open block is rebuilt per streamed delta: O(delta), the property no listed viewer has except wuhu-markdown-ui by design.
- **Three hosts over one block model, chosen by measurement (0199, phase 0):** (a) per-block SwiftUI views in a lazy stack with `Equatable` identity (chat and streaming); (b) one TextKit 2 text view with attachments (cross-block selection, find, accessibility for free; armamut and swift-markdown-engine take it);
  (c) **an own windowed layout**: a CoreText frame per block cached by content hash, a prefix-sum tree of heights, only the visible blocks drawn, in a SwiftUI view whose body is one `Canvas` or a thin AppKit drawing view behind a representable. The evidence so far leans away from (b) for large documents (one changed paragraph costs 1.7 to 5.4 ms with a 31 to 39 ms tail, D1 claim 11) and toward (c)
  (0.16 ms per block, claim 12), at the price of building selection, find and accessibility ourselves, which (b) gives for free. The probe builds a skeleton of each and measures **edit latency (p50 and p99) at 100 KB, 1 MB and 5 MB**, first screen, scroll hitches, resident memory and a stream of 40-byte deltas, release, median and spread. The public API is SwiftUI whichever host wins. Whichever host wins, paragraphs are typeset in bounded windows (D2 claim 17: CoreText's line breaking is O(the paragraph) per call).
- **Mermaid in SwiftUI** (0200): `MermaidView` draws the scene with `Canvas` (one view, immediate mode, so a 1000-node diagram is not 1000 views); layout in a task off the main actor, cached by content; theme from the
  environment's colour scheme. In (b) the same drawing sits in an attachment view. Selection copies source. This is a different consumer from 0066's "not in scope: exporting to image files"; PDF export falls out of the CoreGraphics backend.
- **Selection copies Markdown source**, as in ask (decided 2026-11-04): every run of the viewer's text carries the source range it shows (ADR-0033's rule), and the copy command writes those bytes; for a diagram, the fence's source. In the TextKit host this is an override of copy over a source attribute; in the per-block host, a copy action over the same ranges.

## 10. Quick Look: built with Xcode 27.2, deployed from macOS 26

**What is current (*probed*, D1 claim 7).** One extension point, `com.apple.quicklook.preview`. View-based: an `NSViewController` that conforms to `QLPreviewingController`, `preparePreviewOfFile(at:completionHandler:)` called once on the main
thread, handler as soon as possible, no file held open. Data-based: `QLPreviewProvider` returning a `QLPreviewReply` built from a `CGContext` (bitmap or vector), a `PDFDocument`, data of a supported type (image, PDF, HTML with `cid:` attachments,
text, RTF, XML) or a file URL. Thumbnails are a separate extension (`QLThumbnailProvider`). Nothing newer exists in the SDK on this machine; Apple's own extensions use both styles. **The system shows Markdown as plain text**, so a good extension
is a real improvement, and the content types are `net.daringfireball.markdown` (`.md`, `.markdown`) and `public.markdown`; `.mdown .mkd .mkdn .mdwn .mmd .mermaid .mdx` are unclaimed.

**Design.**
- **View-based**, hosting the TextKit 2 view of 0199 (live reflow when the panel is resized, native selection, find and accessibility, light and dark switching without a new layout, links). The data-based PDF route is simpler and runs in a lighter host, but
  fixes the width, so it is the fallback to probe, not the first choice (*unprobed*: both are skeletons in phase 0 of 0201, measured request to first pixel and resident memory).
- **No web view, no JavaScript, no network.** Sandboxed, hardened runtime, no JIT entitlement (flux-markdown needs one for its web view), no network entitlement; remote images become their alt text. Whether a sandboxed extension can read images beside the
  previewed file is **unprobed**; the fallback is the same placeholder.
- **Latency by construction.** Read the file bounded (a stated cap with a visible "truncated" line, never silent), parse (AemiMarkdown: about 5 ms for 1 MB at its measured 200 MB/s, *to be re-measured in the extension*), lay out only the first screen, call the handler, lay out the rest
  lazily. Diagrams show their source, are laid out in the background (as armamut does) and replace it. Cap and budget are numbers for phase 0.
- **Structure.** XcodeGen over SwiftPM, as MacFS: `project.yml` (deployment target macOS 26.0, built with Xcode 27.2, `projectFormat: xcode16_3`, strict-concurrency, `ExistentialAny` and warnings-as-errors as build settings), logic in the app's own sub-package, `MarkdownLookKit` (viewer, typography, extension logic) over AemiMarkdown (by path) and AemiMermaid (by pinned revision), thin targets: a container app (settings,
  how to enable the extension), the preview extension, the thumbnail extension (drawn with the CoreGraphics backend: first screenful as an image). **Where it lives (the owner's decision): the AemiMarkdown repository, as an app sub-package named MarkdownLook**, with its own manifest and XcodeGen spec, outside the library's manifest like the benchmark sub-package, so ask, TerminalKit and the family pins see no change and a later move into something bigger is a directory move. It is the Markdown repository rather than AemiMermaid's because previewing Markdown is its purpose; signing and release scripts stay inside the MarkdownLook sub-package.
- **Identifiers.** The prefix is `studio.aemi`: the app `studio.aemi.MarkdownLook`, its extensions `studio.aemi.MarkdownLook.Preview` and `studio.aemi.MarkdownLook.Thumbnail`, the lab `studio.aemi.MarkdownLab`, the exported Mermaid type `studio.aemi.mermaid`. Tested on the current machine (macOS 27.0.1); the 26 floor is a deployment target the compiler checks for API availability, not something run.
- **Types.** Support `net.daringfireball.markdown` and `public.markdown`; export one type for `.mmd` and `.mermaid` conforming to `public.plain-text`, so a Mermaid file previews too. Whether to import the unclaimed Markdown extensions is a conflict question for other apps (*unprobed*).
- **Code highlighting** from `AemiLexers` (already in Aemi, *read*) through roles; **math** (`$x$`) is parsed by AemiMarkdown and shown as styled source until a typesetter is decided (not in this scope).
- **Verification.** Logic is tested in the packages (attributed string and scene goldens, allocation ceilings). The extension is probed with `qlmanage -p` and `-t`, `pluginkit`, signposts around request, handler and first draw, and a script that repeats it and reports median and
  spread. Limits of an extension's memory and time are not documented by Apple (*unprobed*; measured in phase 0). Whether the user must switch the extension on by hand is claimed by MDLook's README for recent macOS and **not run here**.
- **Distribution** (notarised build, a Homebrew cask) is the owner's decision and not designed here.

## 11. Order of work (roadmap entries, each a claimable unit)

1. **0202** the fence reader in AemiMarkdown, **0203** its edit API (block source ranges, content hashes, `replace`, phase A then phase B), and **0205** its performance program (complete parse, streaming and edits); **0206** the terminal renderer's rows without String churn. Foundational; they unblock every consumer, and their baselines are the ones of D1 claims 10 to 14.
2. **0196** AemiMermaid: syntax, limits, sanitiser, tapes, the CLI, and **phase 0 evidence** (a corpus, the oracles wired as differential tests, the budget numbers) for flowcharts, then sequence.
3. **0197** layout and scene: cell and continuous metrics, flowcharts first, then sequence, state, class, ER; pie and Gantt, then more kinds, later.
4. **0198** the terminal: cell backend, the fence-renderer hook in TerminalKit, ask's adapter, rows cached by content hash; this is where 0066's behaviour lands.
5. **0207** the lab (two panes, ask's stream tap, latency HUD, differential check), early because it is where the host probe and the latency measurements run; **0199** the viewer kit (`MarkdownLookKit`), starting with the host probe in the lab, the typography samples and the edit-latency measurement; **0200** the vector backend and `MermaidView`; **0204** the app's edit mode (source pane, live preview, file watch); **0201** the Quick Look extension, on proven pieces.

Ask gets value after step 4 without waiting for the Apple UI work; the Quick Look extension can ship Markdown without diagrams after 0199 and add them with 0200.

## 12. Decisions

**Settled by the owner on 2026-11-04**: our own engine, with packages only from `g-cqd`, `Aemi-Studio`, `apple` and `swiftlang`; the app in AemiMarkdown for now; system fonts; no recursion, linear time; **selection copies Markdown source**; **macOS 26 floor**; **reading default as Apple recommends** (13 pt body, looser leading).
**Settled in the fifth answer:** an edit or a stream lands instantly, the earlier the better (the 4 ms is a ceiling, not the aim); a two-pane lab, fed by ask's streams; Quick Look is tested on the current machine (macOS 27.0.1: the 26 floor is a deployment target, its runtime is not verified); the bundle identifier prefix is `studio.aemi`.
**Settled in later answers:** every optimization technique is tried, by measurement, whatever the file sizes (section 13); prose leading **1.4 em**; **smart punctuation on** in the viewers, off in the terminal; **pie and Gantt** are wanted, after the first five kinds; **edit and see** at typing speed, by block, in SwiftUI and the terminal; **vector through everything**, raster only where unavoidable.
**Still open:** the distribution of the app (notarised build, a cask); whether private documents may enter the corpus; whether ask's screen composer may change to take byte runs (0206).

## 13. Every optimization, by measurement

The owner's rule, whatever the file sizes: the least resources and the fastest parse and render, **complete or incremental**. The white paper's order stands (do not do the work, do less, do it elsewhere, do it in parallel, then micro-optimise), and so does its test: a change that moves no number is reverted,
each one is an experiment with a hypothesis, a probe that can fail, a before and after (median and spread, release, quiet machine) and its own commit. "All of them" means every technique below gets its experiment; it does not mean all of them stay. The baselines are measured (D1 claims 10 to 14): the parser is at
about 100 MB/s on documents with 83% of its time in our own code and a fifth of it avoidable (table cells, copy-on-write checks, moves); the terminal renderer spends 53% of its time in the Swift runtime and malloc; a tape costs 0.47 bytes per source byte; CoreText lays a block out in 0.16 ms.

- **Do not do the work.** Parse the inlines of a block only when it is drawn (the viewer shows a screenful of a large document, the Quick Look preview its first screen); keep the cache by content hash so an unchanged block, a moved block and a repeated block cost nothing; key terminal rows by the width they actually depend on (a block narrower than the window has the same rows at every wider width); skip an
  unchanged fence's diagram; coalesce edits so a burst draws once.
- **Do less per byte.** A two-stage parse as simdjson does it: a first pass classifies sixteen bytes at a time with nibble lookups (`tbl` on arm64) into bitmasks of special bytes, a second pass walks set bits instead of bytes; bulk-skip a fenced block's lines to its closing fence when no container is open; SIMD for indentation and blank lines, for the pipes of a table row, for the end of a plain text run;
  perfect hashing and byte-class tables (present for entities and ASCII classes); no work for plain ASCII in width, wrapping and grapheme breaking.
- **Spend less memory.** Implicit text runs (store only the markup slots; the text is the gap between them) to shrink the inline tape; pack the open-block state; read a file by mapping it and parse from the mapped bytes with no copy, so a preview's resident memory does not include the file; keep layouts bounded by bytes with least-recently-used eviction and heights only for the rest; one flat open-addressing table for reference labels instead of a dictionary of byte arrays;
  compressed-sparse-row arrays and dense `UInt32` indices in the diagram engine; arenas reset per diagram and reused across diagrams.
- **Take the runtime out of the hot path.** Copy-on-write uniqueness checks and reference counting come out with unsafe buffers inside `unsafe`-justified arenas, noncopyable parser state (`~Copyable`, `borrowing` and `consuming`), `InlineArray` for small stacks, `Span` and `RawSpan` at the boundaries, no existentials, specialisation and `@inlinable` where a profile says so (cross-module optimization is already on). The renderer's rows become byte ranges into the source plus style ids
  (the ADR-0033 rule that a run names its source makes this natural), so a plain run costs no `String`.
- **Do it elsewhere and in parallel.** Layout of the visible blocks and of different diagrams in parallel on a small fixed pool of the cooperative executor; parse ahead of the viewport; **a speculative parallel parse for large documents**, which is the edit machinery reused: chunks are parsed from a clean top-level boundary, and a chunk whose start state did not match the previous chunk's end is parsed again; the inline phase is parallel per leaf once references are known.
  Restart at a clean boundary and resync is the one primitive under incremental edits and parallel parsing.
- **Toolchain.** Cross-module optimization on (read from the build log). Profile-guided optimization and link-time optimization **only in the app and extension builds** (Xcode build settings), never in the libraries, whose manifests may carry no unsafe flags; a probe decides whether the gain is worth the build step. A startup order file for the extension, as ask has for its own launch, and link weight kept to what is used (a probe on whether the preview needs SwiftUI at all, against an AppKit-only view).
- **Draw less.** One drawing view that draws only the visible blocks and invalidates only the rectangle of a changed block (a dirty rectangle, which an AppKit-backed view gives and a full-canvas redraw does not); colours and fonts resolved once per role and appearance and kept; attributed strings only for visible blocks, built without copying text where the bytes are ASCII; no timer or display link running when nothing moves.
- **Verify every optimization.** A scalar reference implementation stays in the tests as the oracle; SIMD kernels are checked against it on random and hostile input over guard pages (Aemi's guarded bytes), under the address sanitizer, and by fuzzing; allocation ceilings and a growth test keep the bounds; mutation testing runs on the changed files.

The work is filed as roadmap 0205 (the parser, complete, streamed and edited) and 0206 (the terminal renderer's rows), with a performance section in each of the engine, viewer and Quick Look entries.

## 14. Risks and what is not known

- Mermaid's grammar is large and informally specified; "all of Mermaid" is not a goal, and unsupported syntax must degrade to source with a reason, never to a wrong drawing (a test per kind lists what is accepted).
- Quality of text layout is a judgement; the oracle is a visual comparison against mmdflux and mermaid-ascii on a corpus, plus a geometric linter (no overlap, no clipped label) in the style of MermaidKit's, which I read about and did not run.
- The Quick Look claims were probed on macOS 27.0.1 with the 27.2 SDK; the floor is 26, and **no macOS 26 machine was available**, so that the extension runs there is unprobed (phase 0 of 0201 needs one, or a virtual machine).
- Quick Look process limits and sandbox reach are unmeasured; the design keeps both fallbacks (placeholder, bounded read).
- The timing numbers in the diary come from a loaded machine and are not a baseline; phase 0 re-measures on a quiet one before any budget is adopted.
- System-font metrics change with the OS and the point size, so layouts with the real font are not byte-stable across machines; the table measurer gives exact goldens, and caches key on the font, size and scale.
- The debug tap in ask must not perturb what it measures: off by default, one flag check when off, a bounded non-blocking queue that drops and counts when full, never a lock held across a write.
- The macOS 26 floor is a deployment target checked by the compiler for API availability; it was not run on a 26 machine, and nothing says it works there until one is tried.
- Incremental parsing is the riskiest piece of AemiMarkdown work: reference and footnote dependencies, lazy continuation and setext reach backwards, and a fence reaches forwards. The answer is phase A first and a differential test of B against it over every spec example and every edit position; if B does not pass it, A stays and the limit is the document size where A stops meeting the budget (about 400 KB, D1).
- The editing probes were one scratch program each: the TextKit 2 numbers are one run per size, the terminal numbers two runs; neither replaces the quiet-machine measurement of 0199 and 0203.
- Nothing here was built, so no claim about the engine is made, only about what exists and what a design would have to meet.
