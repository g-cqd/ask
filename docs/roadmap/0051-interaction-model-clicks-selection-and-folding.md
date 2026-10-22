---
status: in-progress
blocked-by: ["0015"]
date: 2026-10-20
decision: ADR-0044
---

# 0051 — The interaction model: clicks, selection and folding, across the whole screen

The owner wants selection that copies and survives scrolling, components that act when clicked, and images and long code that
fold, and wants them to be **consistent, coherent and cohesive** across ask, not built one component at a time. This entry is the
study that has to happen before the screen is built around them. The mechanisms are TerminalKit's (its roadmap 0016 to 0019); the
policy and the meaning of each click are ask's (ADR-0044).

## What ask has today

The real transcript now has mouse selection, highlighting, clipboard writes, wheel scrolling and thinking/tool folds. Header clicks
open individual blocks; Ctrl+T and Ctrl+O change their separate defaults. Five `ui.*` keys configure these policies. Scripted-provider
PTY probes cover live runs and resumed sessions (diaries 50–55). Images, long code, runner clicks and bounded input remain owed.
The real screen now follows the prototype's no-leading-icons and terminal-default-background rules (diary 2026-10-22 (2)).

## What TerminalKit has now (2026-10-20)

ask pins `ad1c072` and consumes the regions, pointer recognizer, content selection, row provenance, drag controller, clipboard plan and
fold store.

| Mechanism | State in TerminalKit | Where |
|---|---|---|
| Terminal facts (mouse, OSC 52, graphics, native-selection keys) | measured in four terminals | ADR-0028 |
| Regions and clicks: a click with a count, drags, wheel steps, over regions the host names | built, tested against four real terminals' streams, zero allocations | ADR-0029, roadmap 0016 |
| Selection: content-anchored, mapped from cells, highlighted, read back; double and triple click | model and drag controller built; ask paints the spans | ADR-0030, roadmap 0017 |
| Clipboard: a plan from what each terminal does (OSC 52, the pasteboard, WezTerm's doubled first write) | built, ask performs it | ADR-0030 |
| Folding: a placeholder-carrying block, per-block state with a default, a scroll that does not move the reader | model built; ask draws thinking/tool folds; images remain | ADR-0031, roadmap 0018 |
| A bounded input that scrolls by display row | **not started** | roadmap 0019 |

What ask must supply to use them: a stable identity for every block it draws, a record of what each row shows (the provenance a selection
needs, every frame), and the placeholder text for anything it folds. The terminal's facts also bear on ask's settings: Terminal.app needs the
pasteboard (`ui.copyOnSelect` must run `pbcopy` there), and the status bar can name the key that returns the terminal's own selection.

## The owner's examples, and what is proposed

Rows marked **owner** are their examples; rows marked **proposed** are mine, to be accepted, changed or dropped.

| Component | Click | Key | Source |
|---|---|---|---|
| Thinking block | disclose or fold it in place | `ctrl+t` (the prototype's, Pi's) | **owner** |
| Count of runners (background jobs and subagents) in the status bar | open the list of them, each with a short description | a command, `/agents` and `/tasks` (roadmap 0048) | **owner** |
| Tool-call block | disclose or fold it | `ctrl+o` | proposed, same as thinking |
| Image | show it, or fold it to its placeholder | | **owner** (folding), proposed (the click) |
| Long code block | show it, or fold it to its placeholder | | **owner** (folding), proposed (the click) |
| "N approval" in the status bar | open the approval request | `p` (the prototype's) | proposed |
| "N lines below" indicator | scroll to the end | `End` | proposed |
| A row in a picker (`/`, `@`) | select it, as Enter does | `Enter` | proposed |
| An attached reference in the input | remove or edit it | | proposed |
| Sidebar sections (workbench) | focus a section | | proposed |

## Conventions to settle (proposed, none decided)

1. **One action, one identity.** Each interactive component has an action identity, and the click, the key and the slash command
   all invoke it, so the three cannot drift. TerminalKit may offer the keyboard path to the same identity (its 0016).
2. **A drag is a selection and a click is an action.** A click on selected text clears it without triggering the component underneath
   (ADR-0056). Ctrl+C copies and consumes a selection; Escape clears it before aborting.
3. **Disclosure is per block, with a default and a command** (Pi's shape, research note on terminal agent UIs): fold one without
   folding all. Fold state belongs to the block, survives scrolling and resizing, and **expanding a block must not move what
   the reader is reading** (diary 35). Whether it survives reload and resume is open.
4. **The target is the whole block or row, never a glyph.** The screen has no leading icons, so a click target cannot be an icon;
   the placeholder carries its own hint in text (`ctrl+t to expand`, as in the prototype).
5. **Every fold leaves a placeholder** (ADR-0044), and it says what is inside: the kind and the size.

## Settings (keys in the layered configuration, roadmap 0039)

The defaults are decided in ADR-0046: the first three by the owner, the rest on evidence, for the owner to overrule.

| Key | Values | Default |
|---|---|---|
| `ui.mouse` | on, off (off gives the terminal its own selection back) | on |
| `ui.copyOnSelect` | on, off | on |
| `ui.thinking`, `ui.tools` | folded, open | folded |
| `ui.images` | show, placeholder, never | placeholder |
| `ui.codeFoldLines` | lines above which a code block starts folded, capped at half the viewport | 20 |
| `ui.promptRows` | the most rows the input takes before it scrolls inside itself, capped at a third of the viewport | 6 |
| `ui.scrollLines` | lines one wheel step scrolls | 3 |

## What landed (2026-10-20, diary 50)

The transcript selects, highlights, copies and scrolls with the pointer (TerminalKit 0016 and 0017 in a real screen): rows carry
provenance, the frame reaches the mouse through a box, the controller owns the pointer, `ScreenClipboard` performs the kit's plan, and
`ScreenOptions` carries the ADR-0046 defaults. **Not yet:** folding and its clicks, any region but the transcript, the `ui.*` keys,
a timer for autoscroll, a key to copy when copy-on-select is off, feedback that a copy happened, and the real-terminal probe.

## What landed next (2026-10-20, diary 51)

A tool's output folds to `▸ bash ls ✓ · 3 lines` and opens on a click on its header or with Ctrl+O; the view keeps the header on its row
while scrolled back; a selection reads what is shown. **Not yet:** thinking blocks (the agent does not send them), long code blocks and
images, the `ui.*` keys, a key to open one block, and a run against the real agent.

## What landed after that (2026-10-20, diary 53)

`ui.mouse`, `ui.copyOnSelect`, `ui.tools` and `ui.scrollLines` are configuration keys, layered, shown by `ask config`, and read at startup.
The keys for features that do not exist yet (`ui.thinking`, `ui.images`, `ui.codeFoldLines`, `ui.promptRows`) are refused until they do.

## What was run (2026-10-20, diary 54)

`Scripts/probe-pointer.py` drives the built binary in a pty with real mouse reports and reads the screen and the OSC 52 copies back (15
checks, with a negative control). It is an emulator, not a physical terminal: the real-terminal probe in "Done when" is still owed for
kitty, Ghostty, WezTerm and Terminal.app, tmux and ssh.

## Thinking in the screen (2026-10-20, diary 55)

`ui.thinking` is implemented. Live reasoning and recorded thinking replay through the same folded-block layout; signatures and redacted
data are never shown. A fake-provider PTY probe runs a read tool, opens thinking and output, copies the output, and resumes the session.
Changed reasoning costs about 2.9 ms for a folded 400-line block; unchanged frames remain about 11 µs (details and limits in diary 55).

## Selection controls (2026-10-22, ADR-0056; diary 2026-10-22 (1))

Copy-on-select off has Ctrl+C; Escape clears first; a click inside selected text cannot open the fold underneath it. The status explains
these controls, reports copy requests/failures without claiming acknowledgement, and names the terminal's native-selection bypass.
The real-binary pointer probe now has 20 passing checks. Host pasteboard completion reporting and sustained edge autoscroll remain owed.

## Text-only hierarchy (2026-10-22, diary 2026-10-22 (2))

Leading user/disclosure glyphs and the painted status surface are gone from the real screen. User text starts at column zero; fold
placeholders say their kind and size; only selected text is inverse. `/help` names the fold shortcuts. Both PTY probes and the existing
turn/resume/multiline regressions pass against these exact strings. Layout switching and pixel separators are still separate work.

## Open questions

- Tool and thinking selections copy what is **shown**, so crossing a fold copies its placeholder. Images still need their copy policy.
- Whether fold state is persisted in the session, which changes the closed session payload (roadmap 0027), or is per run.
- Wrapped lines in the input: Up and Down move between hard lines only, which 0049 still owes, and a bounded input needs
  display rows (TerminalKit 0019). Whether ask adopts the kit's text types first or the kit grows them first.
- Hover, which costs any-motion reporting.
- What a **runner** is in the list: background jobs (roadmap 0031), subagents (0027), or both, and which description each has.
- How the character layout (no pixels) gives the same click regions as the pixel layout. It must, since they share one contract.

## The study

1. List every region the screen draws, in both layouts of roadmap 0015, and give each a target, an action identity, a key and a
   placeholder where it can fold. The table above is its start.
2. ~~Run TerminalKit's probes~~ **Done** (TerminalKit ADR-0028): mouse reports, OSC 52, the bypass key and image cost in kitty, Ghostty,
   WezTerm and Terminal.app. tmux and ssh are still unprobed.
3. Settle the conventions with the owner in an ADR, before any component is built. The defaults are settled (ADR-0046).
4. Build in the order the dependencies fall: regions and clicks, then selection and the clipboard, then folding, then the input.

## Done when

The inventory is complete and agreed; an ADR fixes the conventions and the defaults; the `ui.*` keys exist with tests and show in
`ask config`; the screen uses TerminalKit's regions, selection and folds; a real-terminal probe clicks a thinking block and a
runner count, drags a selection across two blocks, scrolls, and finds it still there and copied.
