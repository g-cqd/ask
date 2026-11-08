---
status: done
blocked-by: []
date: 2026-11-08
---

# 0213 — A tool's escapes become colours and links, and the rest is removed

The owner, 2026-11-04 (note n30, task t213): a command's escapes showed as text (`[1;31merror:`, OSC 8 links), with only the ESC
dropped. Parse output into styled spans: SGR colours and attributes, OSC 8 links opened by ask's own rule, and strip everything else.
Nothing from a tool may reach the terminal raw.

## The plan

- `OutputEscapes` (AskTUI) reads a tool's output once, when its block receives it (`Transcript.keep`).
  - It keeps the plain text: folding, the byte and line limits, copying and search all see clean text.
  - Beside it, it keeps per-line spans of style. SGR covers 16, 256 and true colours (semicolon and colon forms), bold, dim, italic,
    underline kinds and strikethrough, each switched off on its own. OSC 8 links are kept only for http, https, file and mailto,
    printable ASCII, and at most 2 KiB, the schemes `LinkOpener` opens.
  - Everything else is removed whole: CSI, OSC (titles, the clipboard's 52), DCS, SOS, PM, APC, two-byte escapes, their 8-bit forms,
    and every control but tab, line feed and carriage return.
  - It is bounded like `TerminalTextFilter`: a line feed, or a sequence of more than 4096 bytes, ends a sequence.
  - A background colour is not drawn, so the block's tint shows.
- The spans are drawn as code tokens are: `FileCode.spans`, placed on wrapped rows by `CodeAccents`, over the output's dim. They are
  shifted for tabs, and mapped past a folded middle. A link becomes the row's link, which ask writes as its own OSC 8.
- A job's lane shows its output with the escapes removed.

## Done when

- `OutputEscapesTests` (13) and `OutputColourTests` (6): red on a stub, or with the ingestion reverted.
- `probe-output-colours.py` (6 checks): a command printing a red bold word, an OSC 8 link, a title change and a line clear. The build
  before shows `[1;31m`; this one shows the plain text, the word red and bold, the link as ask's OSC 8, and never writes the title.
- `docs/screen.md` says so.

## Not in scope

- What the model is sent: it still gets the output as the program wrote it.
- Colours in a job's lane, which is a notice of plain text.
- A setting to turn program colours off: they show whatever `ui.highlight` says, since that setting is about syntax colours.
