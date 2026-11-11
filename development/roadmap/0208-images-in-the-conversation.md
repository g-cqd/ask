---
status: in-progress
blocked-by: []
date: 2026-11-06
---

# 0208 — Images in the conversation

The owner, 2026-11-06: "we still don't display images in the terminal" (task t237).

## What is there today

- **Where images come from:** only tool results. The read tool returns a picture as an image part (roadmap 0084), and an MCP tool
  may return image content. Both go to a model that takes images (`ToolOutput.images`), and a session keeps each picture once, by
  hash, in its `images` store (sealed for an encrypted session, ADR-0138). The person cannot paste an image.
- **What the screen gets:** the tool's text only. `ConversationUpdate.toolFinished` carries no image, nor does a resumed history.
  The block says what the tool said, nothing shows the picture.
- **What TerminalKit can draw:** `GraphicsEncoder` writes kitty graphics commands (transmit, place, delete; RGBA, RGB or PNG;
  direct, file or shared-memory transmission). It has no Unicode placeholders.
- **Which terminals:** 0014 measured cell pixels and drawing in kitty (14×25 cells), Ghostty (16×34) and WezTerm (7×16); all three
  draw kitty graphics. Terminal.app reports a cell size but draws no kitty graphics. 0003 owes the probe that should decide this at
  run time instead of guessing from `TERM_PROGRAM`.

## The approach

1. **Carry the pictures to the screen.** A finished tool's update holds its images (a reference to the session's store, not the
   bytes, so a long session does not hold every picture in memory), live and on resume.
2. **A block for each picture, everywhere.** Under the tool's block: its name, type, pixel size and byte size, folded like output.
   This is all a terminal without graphics shows, and what a copied selection holds.
3. **Pixels with kitty's Unicode placeholders.** The image is transmitted once (by id, from the store's file where the terminal
   is local), and the block's rows are placeholder characters (`U+10EEEE` with the image id in the foreground colour and the row
   and column as diacritics). They are text to the screen: they scroll, wrap, fold, clear and diff like any row, which direct
   placement does not (an image placed at the cursor stays where it was drawn when the transcript moves). TerminalKit gets the
   placeholder cells; ask gets the block.
4. **Size.** At most the transcript's width, and a row cap (a setting, about a third of the screen by default); never upscaled
   past its pixel size. Downscaled for transmission when it is much larger than what is shown.
5. **Lifetime.** Images are deleted from the terminal when their block leaves the laid-out window, and sent again when it comes
   back; the memory budget (0088) holds decoded images to what is shown.

## The owner's answers (2026-11-06)

- Pixels in kitty, Ghostty and WezTerm, by the kitty graphics protocol. Not iTerm2's protocol, sixel, or tmux and ssh, for now;
  they get the block's line.
- A picture shows at once, its height capped (about a third of the screen), and folds on a click.
- Pasting an image into a prompt: yes, as its own entry after this one.

## The questions as they were asked

- Which terminals get pixels: kitty, Ghostty, WezTerm (measured); iTerm2 (its own protocol); sixel terminals; tmux and ssh, where
  the graphics need passthrough.
- Whether a picture shows at once or starts folded (like tool output) and opens on a click.
- Whether the person may paste an image into a prompt (a separate entry if so: the clipboard's image, the model's support).
- Generated images (a model that returns images) are not in scope until a provider ask uses can return them.

## Done when

A picture the read tool returns, and one from an MCP tool, show in kitty, Ghostty and WezTerm in their block, at the right size,
scrolling and folding with the transcript, live and after a resume (an encrypted session's too); every other terminal shows the
block's line; a probe checks the placeholder rows and the transmitted image through the release binary, and the person checks
the look in a real terminal. Idle memory does not change; active memory with three pictures shown is measured against 0088.

## Not in scope

Video, animation, images inside Markdown messages by URL (fetching is its own question), and pixel chrome (0015).

## Phase 1 done (2026-11-06): the pictures reach the screen, a row each

- A finished tool's update carries its pictures (`ToolImage`, the bytes shared with the session's record, not copied), live and on
  resume: `SessionReplay` now keeps a tool result's images, which it used to drop.
- Each shows as a row under the tool's header, folded or not: `PNG · 1280×800 · 245 KB`. The pixel size is read from the header of
  a PNG, GIF, JPEG or WebP (`ImagePixelSize`), nothing decoded. Every terminal shows this row; it is where pixels will go.
- Test first: `ToolImageTests` (sizes from four headers, the row folded and open) and `SessionReplayTests` (images replayed) red on
  stubs; `probe-images.py` (2 checks: live and resumed) red on main's build.
- Phase 2 followed the same day, below.

## Phase 2 done (2026-11-06): the pixels, in kitty, Ghostty and WezTerm (WezTerm since dropped, below)

- TerminalKit 1a2355f: `KittyPlaceholder` (a cell for a row and column, the colour for an image id; kitty's 297 marks generated from
  its own `rowcolumn-diacritics.txt`) and virtual placements (`U=1`). TerminalKit c6c83a8: an APC reply is read whole, as an OSC one
  is; before it, kitty's answer would have been typed into the input as `Gi=…;OK`.
- ask asks once (`TerminalGraphics`, a one-pixel `a=q` query) where the environment says kitty, Ghostty or WezTerm, never through
  tmux or ssh, and nothing else: Terminal.app may print an APC string as text. On `OK`, each PNG a tool returned is sent once, quietly,
  under an id of ask's own (`ScreenImages`, off the screen's thread), placed virtually at a size in cells (`ImagePlacement.fit`: its
  own pixels at most, the transcript's width, a third of the screen's rows, its shape kept), and drawn by rows of placeholder cells in
  its colour under its line. The pictures ask sent are deleted, by id, when the screen closes.
- Test first: `TerminalGraphicsTests`, `ImagePlacementTests`, `ScreenImagesTests` (a placement is laid out again: it was not, and the
  block kept its rows), TerminalKit's `KittyPlaceholderTests`, `KittyPlaceholderWidthTests` and `SequenceRouterAPCTests`, each red
  first. `probe-images.py`, 7 checks: asked as Ghostty, the answer kept out of the input, the PNG sent and placed virtually, its cells
  drawn, live and resumed; as Terminal.app nothing asked or sent. The sweep: 88 of 88 probes.

## Checked in real terminals (2026-11-06)

Run in kitty 0.49.2, Ghostty 1.4.0 and WezTerm, screenshots read for their pixels:

- kitty and Ghostty draw the pictures in their block, at the size placed. Page Up and Page Down move them with the text and leave
  nothing behind; `/new` takes them all away.
- WezTerm takes kitty's graphics but not its Unicode placeholders: it drew the placeholder cells as glyph boxes and the picture at
  the cursor, over the input. It is no longer asked; it keeps the caption line, as any other terminal.
- Fixed from what the wider tests and those runs found:
  - a cleared conversation (`/new`) kept its pictures, placements and choice summary by index, so the next block at that place
    showed the old picture;
  - a picture was sized to the terminal, and ran under a sidebar beside the transcript. It is now sized to the transcript's width
    (`Sidebar.transcriptColumns`: all of it when the sidebar is in the band);
  - a resize or the sidebar opening left a picture too wide. It is placed again, smaller, under the same id, after any event.

## Built 2026-11-11

- A picture is placed again whenever its fit changes, so one narrowed by a small screen grows back when it widens
  (`ToolImageEdgeTests`, red first).
- A click on a picture's line or its cells folds that picture away, leaving its line, and a second shows it; the tool's output
  folds apart from it (`PictureFoldTests`, red first; `probe-images.py`, 9 checks, two of them the click).

## Left

- The look confirmed by the owner, in their own kitty or Ghostty.
- JPEG, GIF and WebP keep their line only: kitty takes PNG or raw pixels, so they need converting first.
- Lifetime: every picture of a resumed session is sent at once; the roadmap's "sent while laid out" is not built, nor measured
  against the memory budget (0088).
