---
status: done
blocked-by: []
date: 2026-11-12
---

# 0224 — Paste an image into a prompt

The owner, 2026-11-06 (answering 0208): "Pasting an image into a prompt: yes, as its own entry after this one" (task t238). The
task adds, as the owner's: sent to models that take images, kept in the session's image store, shown in the person's message as
0208 shows tool pictures; a model that takes none refuses it with a reason.

## What is there today

- **The key.** When the terminal passes Command+V or Ctrl+V on instead of pasting, ask reads the Mac's pasteboard itself
  (`HostPasteboard`, roadmap 0082), but only its text.
- **The request.** A tool result carries images (`RequestBlock.toolResult(images:)`, roadmap 0084) and the Anthropic, Responses,
  OpenAI-compatible, Antigravity and Apple encoders send them. A user message is text only (`RequestBlock.text`).
- **The session.** `SessionPayload.user(String)`; pictures are kept once by hash in the session's image store (`SessionImageStore`,
  sealed when encrypted).
- **The model.** `ResolvedModel.acceptsImages` says whether a model takes images.
- **The screen.** Tool pictures show as a caption and, in kitty, Ghostty and WezTerm, as pixels (0208).

## The plan

Asked (the owner): 1, 3, 4, 5. Mine: 2, which the owner chose, with the answers below, on 2026-11-12.

1. **Read an image from the pasteboard.** The same key: when the pasteboard holds a picture, it is taken; bounded as the read
   tool bounds one (`ImageReader`: at most 2000 px on the long side, re-encoded when too large).
2. **Show it in the input.** A token in the draft where it was pasted, `[image 1]`, deleted whole by one Backspace; the caption
   (`PNG · 1280×800 · 245 KB`) on the line above the input while it is attached.
3. **Send it.** A user message gets image blocks beside its text (`RequestBlock.image`), encoded by each provider as a tool
   result's are now. A model that takes no images refuses the paste, with the reason, and so does sending when the model was
   changed since.
4. **Keep it.** The user entry records its images by hash in the session's image store (a new optional field, read by older
   builds as text alone), so a resume shows and sends them.
5. **Show it in the message.** The person's block shows the caption and, where the terminal draws pixels, the picture, as 0208.

## The owner's answers (2026-11-12)

- A picture on the pasteboard wins over its text; text alone pastes as text.
- A pasted or dropped path that names an image file is attached; any other text stays text.
- In the input: the `[image N]` token where it was pasted, and the caption on a line above the input.
- The plan above: build it.

## Built 2026-11-12

| Step | Where | Proof |
|---|---|---|
| 1, pasteboard and path | `HostPasteboard.picture(on:)`: a copied image file, then PNG, then TIFF, over text; `PastedPath.picture` for a pasted or dropped path | `PastedPictureTests`; `probe-paste-image.py` (a dropped path) |
| 2, the input | `PastedPictures`: `[image N]` tokens, numbers never reused; Backspace deletes a token whole; captions in the picker's rows while it is shut | `PastedPictureTests`, red on stubs (16 issues) |
| 3, sending | `RequestBlock.image` on every wire (Anthropic, chat, Responses, Antigravity; Apple ignores it, as it takes none); filtered as tool pictures are; `Conversation.preparePicture` bounds it (`PastedImage`, the read tool's `ImageReader`) and refuses for a model not known to take images | `UserImageWireTests`, `PastedImageTests`; the probe's request |
| 4, keeping | `SessionPayload.user(_, images:)`, by hash in the image store; an older build reads the text; a lost picture becomes a line | `PastedImageSessionTests` |
| 5, showing | the message's block, Markdown or not, live and resumed (`SessionReplay.Step.pictures`); a thread's lane too | `PastedPictureTests`, `ThreadLaneTests`; the probe, live and resumed |

Not verified: a picture copied to the real pasteboard (the probe cannot set the person's pasteboard); the refusal for a model that
takes no images, through the binary; a real terminal.

## Not in this entry

Images from a URL; several pictures in one paste; pasting into a thread's lane is the same input, so it is included.
