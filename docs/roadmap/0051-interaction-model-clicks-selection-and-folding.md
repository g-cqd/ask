---
status: not-started
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

Nothing of it (checked in the source, diary 40): no mouse reporting is enabled, no clipboard is written, the screen discloses and
folds nothing, and the prompt is capped by a hard-coded six rows with its own editor instead of the kit's text types. The
prototype in `docs/prototypes/ui-lab/` simulates thinking and tool blocks that expand, but has no clicks, selection or folding
beyond keys; it cannot answer any question here.

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
2. **A drag is a selection and a click is an action.** A click on selected text does not trigger the component under it. What a
   click inside an existing selection does is open.
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
| `ui.thinking`, `ui.tools` | folded, shown | folded |
| `ui.images` | show, placeholder, never | placeholder |
| `ui.codeFoldLines` | lines above which a code block starts folded, capped at half the viewport | 20 |
| `ui.promptRows` | the most rows the input takes before it scrolls inside itself, capped at a third of the viewport | 6 |
| `ui.scrollLines` | lines one wheel step scrolls | 3 |

## Open questions

- What a copy contains when the selection crosses a **fold** or an image: the placeholder, or what is inside (TerminalKit 0017).
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
